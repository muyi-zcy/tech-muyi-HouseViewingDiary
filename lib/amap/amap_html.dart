import 'dart:convert';

const _defaultLng = 121.4737;
const _defaultLat = 31.2304;

/// 必须在加载 maps 脚本之前输出，否则逆地理等服务校验失败。
String _amapSecurityScriptHtml(String? securityJsCode) {
  final s = securityJsCode?.trim() ?? '';
  if (s.isEmpty) return '';
  final encoded = jsonEncode(s);
  return '<script type="text/javascript">window._AMapSecurityConfig={securityJsCode:$encoded};</script>';
}

/// 房源地图：默认中心为 [centerLng]/[centerLat]（通常为当前定位）；有标记时自动缩放到包含全部标记。
String buildAmapMarkersHtml({
  required String amapKey,
  required List<Map<String, dynamic>> markers,
  double centerLng = _defaultLng,
  double centerLat = _defaultLat,
  String? securityJsCode,
}) {
  final markersJson = jsonEncode(markers);
  // 城市级默认视野：大致只看到市区/城区范围，避免首屏过度放大
  final zoom = 11;
  final securityHead = _amapSecurityScriptHtml(securityJsCode);
  return '''<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no" />
    <link rel="dns-prefetch" href="https://webapi.amap.com" />
    <link rel="preconnect" href="https://webapi.amap.com" crossorigin />
    $securityHead
    <script src="https://webapi.amap.com/maps?v=2.0&key=$amapKey"></script>
    <style>
      html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; }
      #container { position: absolute; left: 0; top: 0; right: 0; bottom: 0; width: 100%; height: 100%; }
      #searchPanel {
        position: absolute;
        left: 16px;
        top: 12px;
        z-index: 9999;
        right: 16px;
        pointer-events: auto;
      }
      #searchBox {
        display: flex;
        align-items: center;
        gap: 10px;
        background: rgba(255, 255, 255, 0.94);
        border-radius: 999px;
        padding: 10px 14px;
        box-shadow: 0 2px 12px rgba(0,0,0,.12);
        border: 1px solid rgba(108, 99, 255, .15);
        width: 100%;
        box-sizing: border-box;
      }
      #searchInput {
        flex: 1;
        border: 0;
        outline: none;
        background: transparent;
        font-size: 13px;
        color: #2d3436;
      }
      #searchBtn {
        border: 0;
        background: transparent;
        color: #6C63FF;
        font-weight: 700;
        font-size: 13px;
        padding: 0;
      }
      #searchResults {
        margin-top: 8px;
        background: rgba(255,255,255,0.98);
        border-radius: 14px;
        box-shadow: 0 2px 12px rgba(0,0,0,.12);
        overflow-y: auto;
        overflow-x: hidden;
        -webkit-overflow-scrolling: touch;
        display: none;
        max-height: 260px;
        box-sizing: border-box;
      }
      .searchResultItem {
        padding: 10px 12px;
        cursor: pointer;
        border-bottom: 1px solid #f0f0f0;
      }
      .searchResultItem:last-child { border-bottom: none; }
      .searchResultTitle {
        font-weight: 800;
        font-size: 13px;
        color: #2d3436;
        line-height: 1.2;
      }
      .searchResultSub {
        margin-top: 4px;
        font-size: 12px;
        color: #636e72;
        line-height: 1.2;
      }
      /* 去掉高德 Label 容器默认蓝框/描边 */
      .amap-marker-label { border: none !important; outline: none !important; box-shadow: none !important; background: transparent !important; padding: 0 !important; }
    </style>
  </head>
  <body>
    <div id="searchPanel">
      <div id="searchBox">
        <input id="searchInput" type="text" placeholder="搜索附近地区" />
        <button id="searchBtn" type="button">搜索</button>
      </div>
      <div id="searchResults"></div>
    </div>
    <div id="container"></div>
    <script>
      function postToDart(obj) {
        try {
          if (typeof AmapBridge !== 'undefined' && AmapBridge.postMessage) {
            AmapBridge.postMessage(JSON.stringify(obj));
          }
        } catch (e) {}
      }
      var map = new AMap.Map('container', { zoom: $zoom, center: [$centerLng, $centerLat] });
      var rawData = $markersJson;
      var markerObjs = [];
      /** 缩放级别 ≤ 此值时按小区聚合（地图缩小）；放大后显示逐套卡片 */
      var AGGREGATE_ZOOM_MAX = 13;
      var lastOpenId = '';
      var lastOpenTs = 0;
      var lastPickTs = 0;
      /** false：仅隐藏标记旁 HTML 卡片；点击仍通知 Flutter 打开底部抽屉 */
      var mapCardModeEnabled = true;
      var DEFAULT_CITY_ZOOM = 11;
      // 搜索结果“定位点”专用标记（不参与房源 markerObjs 的清理逻辑）
      var searchPickMarker = null;

      // 用于“地图点击创建房源”的逆地理解析（地址/小区）
      var geocoder = null;
      var geocoderReady = false;
      try {
        AMap.plugin(['AMap.Geocoder'], function() {
          try {
            geocoder = new AMap.Geocoder({ radius: 3000, extensions: 'all' });
            geocoderReady = true;
          } catch (e) {}
        });
      } catch (e) {}

      /** 完整结构化地址（与高德「结构化地址」一致，精度最好） */
      function formatFullAddress(rg) {
        if (!rg) return '';
        var fa = (rg.formattedAddress || '').trim();
        if (fa) return fa;
        var ac = rg.addressComponent || {};
        var parts = [];
        if (ac.province) parts.push(ac.province);
        if (ac.city && ac.city !== ac.province) parts.push(ac.city);
        if (ac.district) parts.push(ac.district);
        if (ac.township) parts.push(ac.township);
        if (ac.neighborhood) parts.push(ac.neighborhood);
        var st = (ac.street || '') + (ac.streetNumber || '');
        if (st) parts.push(st);
        return parts.join('');
      }

      /** 提取小区/社区名称，回填“小区名称”表单 */
      function pickCommunityName(rg) {
        if (!rg) return '';
        var ac = rg.addressComponent || {};
        var n = (ac.neighborhood || '').trim();
        if (n) return n;

        var aois = rg.aois || [];
        for (var i = 0; i < aois.length; i++) {
          var a = aois[i];
          if (!a || !a.name) continue;
          var at = (a.type || '') + (a.name || '');
          if (/小区|住宅|房产|社区|花园|苑|公寓|坊|里|村|大厦|广场|别墅|城|园|中心|尚|邸|庭|居/.test(at)) {
            return a.name.trim();
          }
        }
        if (aois.length > 0 && aois[0].name) return aois[0].name.trim();

        var pois = rg.pois || [];
        for (var j = 0; j < pois.length; j++) {
          var p = pois[j];
          if (!p || !p.name) continue;
          var pt = (p.type || '') + (p.name || '');
          if (/小区|住宅|房产|社区|花园|苑|公寓|别墅|坊|里|大厦|写字楼|广场|尚|邸|庭|居/.test(pt)) {
            return p.name.trim();
          }
        }
        if (pois.length > 0 && pois[0].name) return pois[0].name.trim();

        var b = (ac.building || '').trim();
        if (b) return b;
        return '';
      }

      function reverseGeocodeToAddress(lng, lat, cb) {
        if (!geocoderReady || !geocoder) {
          cb('', '');
          return;
        }
        geocoder.getAddress([lng, lat], function(status, result) {
          try {
            if (status === 'complete' && result && result.regeocode) {
              var rg = result.regeocode;
              cb(formatFullAddress(rg) || '', pickCommunityName(rg) || '');
              return;
            }
            if (status === 'complete' && result && result.regeocodes && result.regeocodes.length) {
              var rg0 = result.regeocodes[0];
              cb(formatFullAddress(rg0) || '', pickCommunityName(rg0) || '');
              return;
            }
          } catch (e) {}
          cb('', '');
        });
      }

      window.setMapCardMode = function(enabled) {
        mapCardModeEnabled = !!enabled;
        try { refreshMarkers(); } catch (e1) {}
      };
      function postOpen(id) {
        var sid = String(id || '');
        var now = Date.now();
        if (sid && sid === lastOpenId && now - lastOpenTs < 500) return;
        lastOpenId = sid;
        lastOpenTs = now;
        postToDart({ type: 'open', id: sid });
      }
      window.moveMapTo = function(lng, lat, z) {
        if (!map) return;
        map.setCenter([lng, lat]);
        if (z && z > 0) map.setZoom(z);
        try { map.resize(); } catch (e) {}
      };

      // 附近地区搜索框（点击结果跳转到对应位置）
      var placeSearch = null;
      var placeSearchReady = false;
      try {
        AMap.plugin(['AMap.PlaceSearch'], function() {
          try {
            placeSearch = new AMap.PlaceSearch({ pageSize: 8, pageIndex: 1, citylimit: true });
            placeSearchReady = true;
          } catch (e) {}
        });
      } catch (e) {}

      function showSearchResults(html) {
        var box = document.getElementById('searchResults');
        if (!box) return;
        box.innerHTML = html || '';
        box.style.display = html ? 'block' : 'none';
      }

      function hideSearchResults() {
        var box = document.getElementById('searchResults');
        if (!box) return;
        box.innerHTML = '';
        box.style.display = 'none';
      }

      function parsePoiLngLat(loc) {
        if (!loc) return null;
        if (typeof loc === 'string') {
          var parts = loc.split(',');
          if (parts.length >= 2) return [parseFloat(parts[0]), parseFloat(parts[1])];
        }
        if (loc.lng != null && loc.lat != null) return [parseFloat(loc.lng), parseFloat(loc.lat)];
        if (loc.getLng && loc.getLat) return [parseFloat(loc.getLng()), parseFloat(loc.getLat())];
        return null;
      }

      function doNearbySearch(keyword) {
        try {
          keyword = String(keyword || '').trim();
          if (!keyword) {
            hideSearchResults();
            return;
          }
          if (!placeSearchReady || !placeSearch) {
            showSearchResults('<div class="searchResultItem"><div class="searchResultTitle">正在加载搜索服务…</div></div>');
            return;
          }
          var center = null;
          try {
            center = map.getCenter && map.getCenter();
          } catch (e0) {}
          if (!center) center = { lng: $centerLng, lat: $centerLat };

          showSearchResults('<div class="searchResultItem"><div class="searchResultTitle">搜索中…</div></div>');
          placeSearch.searchNearBy(keyword, center, 20000, function(status, result) {
            try {
              if (status !== 'complete' || !result || !result.poiList || !result.poiList.pois) {
                showSearchResults('');
                return;
              }
              var pois = result.poiList.pois || [];
              if (!pois.length) {
                showSearchResults('');
                return;
              }
              var html = '';
              for (var i = 0; i < pois.length; i++) {
                var p = pois[i];
                var title = p && p.name ? p.name : '';
                var addr = p && (p.address || p.type) ? (p.address || p.type) : '';
                var loc = p && p.location ? p.location : null;
                var lnglat = parsePoiLngLat(loc);
                if (!lnglat) continue;
                var lng = lnglat[0], lat = lnglat[1];
                html += ''
                  + '<div class="searchResultItem" data-lng="' + lng + '" data-lat="' + lat + '">'
                  +   '<div class="searchResultTitle">' + escapeHtml(title) + '</div>'
                  +   (addr ? '<div class="searchResultSub">' + escapeHtml(addr) + '</div>' : '')
                  + '</div>';
              }
              showSearchResults(html);
              var box = document.getElementById('searchResults');
              if (box) {
                var items = box.getElementsByClassName('searchResultItem');
                for (var j = 0; j < items.length; j++) {
                  items[j].onclick = function() {
                    var lng2 = parseFloat(this.getAttribute('data-lng'));
                    var lat2 = parseFloat(this.getAttribute('data-lat'));
                    if (isNaN(lng2) || isNaN(lat2)) return;
                    // 用“不同标记”标识：搜索定位点
                    try {
                      if (searchPickMarker) {
                        try { searchPickMarker.setMap(null); } catch (_) {}
                        searchPickMarker = null;
                      }
                      searchPickMarker = new AMap.Marker({
                        map: map,
                        position: [lng2, lat2],
                        anchor: 'bottom-center',
                        title: '搜索选点'
                      });
                      try {
                        searchPickMarker.setLabel({
                          content: '<div style="max-width:140px;padding:6px 10px;background:#6C63FF;color:#fff;border-radius:999px;font-size:12px;font-weight:800;box-shadow:0 2px 10px rgba(108,99,255,.35);">' +
                            '搜索选点' +
                            '</div>',
                          direction: 'top',
                          offset: new AMap.Pixel(0, -10)
                        });
                      } catch (e3) {}
                    } catch (e2) {}
                    map.setCenter([lng2, lat2]);
                    map.setZoom(14);
                    hideSearchResults();
                  };
                }
              }
            } catch (e1) {
              showSearchResults('');
            }
          });
        } catch (e) {
          showSearchResults('');
        }
      }

      // 绑定搜索事件
      function bindSearchEvents() {
        try {
          var input = document.getElementById('searchInput');
          var btn = document.getElementById('searchBtn');
          if (!input) return;
          if (btn) btn.onclick = function() { doNearbySearch(input.value); };
          input.addEventListener('keydown', function(e) {
            if (e && (e.key === 'Enter' || e.keyCode === 13)) {
              doNearbySearch(input.value);
            }
          });
        } catch (e0) {}
      }
      bindSearchEvents();

      // 地图点击：逆地理后回传给 Flutter（用于创建房源）
      map.on('click', function(e) {
        var now = Date.now();
        if (now - lastOpenTs < 350) return; // 避免“点标记”也触发地图点击创建
        if (now - lastPickTs < 1200) return;
        lastPickTs = now;

        try {
          var lng = e.lnglat.getLng();
          var lat = e.lnglat.getLat();
          reverseGeocodeToAddress(lng, lat, function(addr, community) {
            postToDart({
              type: 'pick',
              longitude: lng,
              latitude: lat,
              location_text: addr || '',
              community_name: community || ''
            });
          });
        } catch (e2) {}
      });

      function escapeHtml(s) {
        return String(s == null ? '' : s)
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')
          .replace(/"/g, '&quot;');
      }
      var cardShell = 'max-width:168px;padding:8px 10px;background:#fff;border:none;outline:none;border-radius:12px;box-shadow:0 2px 12px rgba(0,0,0,.14);text-align:left;';
      function buildMarkerLabelHtml(item) {
        var name = escapeHtml(item.titleLine || item.name);
        var room = escapeHtml(item.roomSummary || '');
        var area = item.area ? escapeHtml(String(item.area)) : '';
        var price = (item.price && item.price !== '--') ? escapeHtml(String(item.price)) : '';
        var st = escapeHtml(item.statusLabel || '');
        var sub = escapeHtml(item.subtitle || '');
        var lines = '<div style="' + cardShell + '">';
        lines += '<div style="font-weight:800;font-size:13px;color:#2d3436;line-height:1.25;">' + name + '</div>';
        if (room || area) {
          lines += '<div style="font-size:11px;color:#636e72;margin-top:4px;line-height:1.35;">' + room;
          if (area) lines += (room ? ' · ' : '') + area + '㎡';
          lines += '</div>';
        }
        if (price) {
          lines += '<div style="font-size:12px;color:#FF6584;font-weight:700;margin-top:4px;">' + price + '</div>';
        }
        if (st) {
          lines += '<div style="font-size:10px;color:#6C63FF;font-weight:600;margin-top:3px;">' + st + '</div>';
        }
        if (sub) {
          lines += '<div style="font-size:10px;color:#b2bec3;margin-top:4px;line-height:1.3;max-height:2.6em;overflow:hidden;">' + sub + '</div>';
        }
        lines += '</div>';
        return lines;
      }
      function buildAggregateLabelHtml(communityName, count) {
        var n = escapeHtml(communityName);
        var c = String(count);
        return '<div style="' + cardShell + '">'
          + '<div style="font-weight:800;font-size:13px;color:#2d3436;line-height:1.25;">' + n + '</div>'
          + '<div style="font-size:12px;color:#636e72;margin-top:6px;font-weight:700;">' + c + ' 套房源</div>'
          + '</div>';
      }
      function clearMarkers() {
        for (var i = 0; i < markerObjs.length; i++) {
          try { markerObjs[i].setMap(null); } catch (e0) {}
        }
        markerObjs = [];
      }
      function centroidOf(items) {
        var slng = 0, slat = 0, n = items.length;
        for (var i = 0; i < n; i++) {
          slng += items[i].lng;
          slat += items[i].lat;
        }
        return [slng / n, slat / n];
      }
      function groupByCommunity(items) {
        var m = {};
        for (var i = 0; i < items.length; i++) {
          var it = items[i];
          var k = (it.name && String(it.name).trim()) ? String(it.name).trim() : '未知小区';
          if (!m[k]) m[k] = [];
          m[k].push(it);
        }
        return m;
      }
      function buildIndividualMarkers() {
        rawData.forEach(function(item) {
          var marker = new AMap.Marker({
            map: map,
            position: [item.lng, item.lat],
            anchor: 'bottom-center',
            title: item.titleLine || item.name
          });
          if (mapCardModeEnabled) {
            try {
              marker.setLabel({
                content: buildMarkerLabelHtml(item),
                direction: 'top',
                offset: new AMap.Pixel(0, -6)
              });
            } catch (e3) {}
          }
          markerObjs.push(marker);
          marker.on('click', function() {
            postOpen(item.id);
          });
        });
      }
      function buildAggregatedMarkers() {
        var groups = groupByCommunity(rawData);
        Object.keys(groups).forEach(function(communityName) {
          var list = groups[communityName];
          var pos = centroidOf(list);
          var marker = new AMap.Marker({
            map: map,
            position: pos,
            anchor: 'bottom-center',
            title: communityName + ' · ' + list.length + '套'
          });
          if (mapCardModeEnabled) {
            try {
              marker.setLabel({
                content: buildAggregateLabelHtml(communityName, list.length),
                direction: 'top',
                offset: new AMap.Pixel(0, -6)
              });
            } catch (e4) {}
          }
          markerObjs.push(marker);
          marker.on('click', function() {
            postOpen(list[0].id);
          });
        });
      }
      function refreshMarkers() {
        clearMarkers();
        if (!rawData || rawData.length === 0) return;
        var z = map.getZoom();
        if (z <= AGGREGATE_ZOOM_MAX && rawData.length > 1) {
          buildAggregatedMarkers();
        } else {
          buildIndividualMarkers();
        }
      }
      map.on('zoomend', function() {
        refreshMarkers();
      });
      map.on('complete', function() {
        try { map.resize(); } catch (e) {}
        refreshMarkers();
        if (markerObjs.length > 0) {
          try {
            map.setFitView(markerObjs, false, [80, 80, 80, 80]);
          } catch (e2) {}
        }
        // 拦截“放得太近”的情况：尽量保持城市级默认视野
        try {
          var z = map.getZoom();
          if (z !== DEFAULT_CITY_ZOOM) map.setZoom(DEFAULT_CITY_ZOOM);
        } catch (e3) {}
        setTimeout(function() { refreshMarkers(); }, 100);
        postToDart({ type: 'ready' });
      });
    </script>
  </body>
</html>''';
}

/// 地图选点（对齐 RN `screens/edit/index.tsx` buildMapPickerHtml）
String buildAmapPickerHtml({
  required String amapKey,
  required double initialLng,
  required double initialLat,
  required String initialAddress,
  required String initialSearchKeyword,
  String? securityJsCode,
}) {
  final escaped = initialAddress
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'");
  final escapedKeyword = initialSearchKeyword
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'");
  final securityHead = _amapSecurityScriptHtml(securityJsCode);
  return '''<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no" />
    <link rel="dns-prefetch" href="https://webapi.amap.com" />
    <link rel="preconnect" href="https://webapi.amap.com" crossorigin />
    $securityHead
    <script src="https://webapi.amap.com/maps?v=2.0&key=$amapKey"></script>
    <style>
      html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #f5f7ff; }
      body { display: flex; flex-direction: column; height: 100vh; min-height: 100vh; box-sizing: border-box; }
      #map { flex: 1; min-height: 0; width: 100%; }
      #searchPanel {
        flex-shrink: 0;
        padding: 10px 12px;
        box-sizing: border-box;
        background: #ffffff;
        border-bottom: 1px solid #e8ebf7;
      }
      #searchBox {
        display: flex;
        align-items: center;
        gap: 10px;
        background: rgba(108, 99, 255, 0.06);
        border: 1px solid rgba(108, 99, 255, .15);
        border-radius: 999px;
        padding: 10px 14px;
        box-sizing: border-box;
      }
      #searchInput {
        flex: 1;
        border: 0;
        outline: none;
        background: transparent;
        font-size: 13px;
        color: #2d3436;
      }
      #searchBtn {
        border: 0;
        background: transparent;
        color: #6C63FF;
        font-weight: 800;
        font-size: 13px;
        padding: 0;
        cursor: pointer;
      }
      #searchResults {
        margin-top: 8px;
        display: none;
        max-height: 220px;
        overflow-y: auto;
        overflow-x: hidden;
        -webkit-overflow-scrolling: touch;
        background: #ffffff;
        border-radius: 14px;
        box-shadow: 0 2px 12px rgba(0,0,0,.12);
      }
      .searchResultItem {
        padding: 10px 12px;
        cursor: pointer;
        border-bottom: 1px solid #f0f0f0;
      }
      .searchResultItem:last-child { border-bottom: none; }
      .searchResultTitle {
        font-weight: 800;
        font-size: 13px;
        color: #2d3436;
        line-height: 1.2;
      }
      .searchResultSub {
        margin-top: 4px;
        font-size: 12px;
        color: #636e72;
        line-height: 1.2;
      }
      .bar {
        flex-shrink: 0;
        min-height: 56px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 8px 12px;
        box-sizing: border-box;
        border-bottom: 1px solid #e8ebf7;
        background: #ffffff;
        font-size: 13px;
      }
      #tips {
        flex: 1;
        min-width: 0;
        margin-right: 10px;
        line-height: 1.4;
        font-size: 13px;
        color: #2d3436;
        max-height: 3.15em;
        overflow: hidden;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
      }
      .btn {
        border: 0;
        border-radius: 999px;
        padding: 8px 14px;
        color: #fff;
        background: #6C63FF;
      }
    </style>
  </head>
  <body>
    <div class="bar">
      <span id="tips">${escaped.isEmpty ? '点击地图选择位置' : escaped}</span>
      <button type="button" class="btn" id="confirm">确认选点</button>
    </div>
    <div id="searchPanel">
      <div id="searchBox">
        <input id="searchInput" type="text" placeholder="搜索附近地区" />
        <button id="searchBtn" type="button">搜索</button>
      </div>
      <div id="searchResults"></div>
    </div>
    <div id="map"></div>
    <script>
      function postToDart(obj) {
        try {
          if (typeof AmapBridge !== 'undefined' && AmapBridge.postMessage) {
            AmapBridge.postMessage(JSON.stringify(obj));
          }
        } catch (e) {}
      }
      var selected = { lng: $initialLng, lat: $initialLat, address: '$escaped', communityName: '' };
      var autoSearchKeyword = '$escapedKeyword';

      /** 完整结构化地址（与高德「结构化地址」一致，精度最好） */
      function formatFullAddress(rg) {
        if (!rg) return '';
        var fa = (rg.formattedAddress || '').trim();
        if (fa) return fa;
        var ac = rg.addressComponent || {};
        var parts = [];
        if (ac.province) parts.push(ac.province);
        if (ac.city && ac.city !== ac.province) parts.push(ac.city);
        if (ac.district) parts.push(ac.district);
        if (ac.township) parts.push(ac.township);
        if (ac.neighborhood) parts.push(ac.neighborhood);
        var st = (ac.street || '') + (ac.streetNumber || '');
        if (st) parts.push(st);
        return parts.join('');
      }

      /** 提取小区/社区名称，回填「小区名称」表单 */
      function pickCommunityName(rg) {
        if (!rg) return '';
        var ac = rg.addressComponent || {};
        var n = (ac.neighborhood || '').trim();
        if (n) return n;

        var aois = rg.aois || [];
        for (var i = 0; i < aois.length; i++) {
          var a = aois[i];
          if (!a || !a.name) continue;
          var at = (a.type || '') + (a.name || '');
          if (/小区|住宅|房产|社区|花园|苑|公寓|坊|里|村|大厦|广场|别墅|城|园|中心|尚|邸|庭|居/.test(at)) {
            return a.name.trim();
          }
        }
        if (aois.length > 0 && aois[0].name) return aois[0].name.trim();

        var pois = rg.pois || [];
        for (var j = 0; j < pois.length; j++) {
          var p = pois[j];
          if (!p || !p.name) continue;
          var pt = (p.type || '') + (p.name || '');
          if (/小区|住宅|房产|社区|花园|苑|公寓|别墅|坊|里|大厦|写字楼|广场|尚|邸|庭|居/.test(pt)) {
            return p.name.trim();
          }
        }
        if (pois.length > 0 && pois[0].name) return pois[0].name.trim();

        var b = (ac.building || '').trim();
        if (b) return b;

        return '';
      }

      /** JS API 2.0 必须在 AMap.plugin 回调内 new Geocoder，否则逆地理会失败 */
      AMap.plugin(['AMap.Geocoder'], function() {
        var geocoder = new AMap.Geocoder({ radius: 3000, extensions: 'all' });
        var map = new AMap.Map('map', { zoom: 16, center: [selected.lng, selected.lat] });
        var marker = new AMap.Marker({ position: [selected.lng, selected.lat], map: map, draggable: true });

        // ======= 搜索附近地区 =======
        var placeSearch = null;
        var placeSearchReady = false;

        function showSearchResults(html) {
          var box = document.getElementById('searchResults');
          if (!box) return;
          box.innerHTML = html || '';
          box.style.display = html ? 'block' : 'none';
        }

        function hideSearchResults() {
          var box = document.getElementById('searchResults');
          if (!box) return;
          box.innerHTML = '';
          box.style.display = 'none';
        }

        function escapeHtml(s) {
          return String(s == null ? '' : s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
        }

        function parsePoiLngLat(loc) {
          if (!loc) return null;
          if (typeof loc === 'string') {
            var parts = loc.split(',');
            if (parts.length >= 2) return [parseFloat(parts[0]), parseFloat(parts[1])];
          }
          if (loc.lng != null && loc.lat != null) return [parseFloat(loc.lng), parseFloat(loc.lat)];
          if (loc.getLng && loc.getLat) return [parseFloat(loc.getLng()), parseFloat(loc.getLat())];
          return null;
        }

        function setPickedPoint(lng, lat) {
          selected.lng = lng;
          selected.lat = lat;
          marker.setPosition([selected.lng, selected.lat]);
          map.setCenter([selected.lng, selected.lat]);
          updateAddress(selected.lng, selected.lat);
        }

        function doNearbySearch(keyword) {
          try {
            keyword = String(keyword || '').trim();
            if (!keyword) {
              hideSearchResults();
              return;
            }
            if (!placeSearchReady || !placeSearch) {
              showSearchResults('<div class="searchResultItem"><div class="searchResultTitle">正在加载搜索服务…</div></div>');
              return;
            }

            var center = null;
            try {
              center = map.getCenter && map.getCenter();
            } catch (e0) {}
            if (!center) center = { lng: selected.lng, lat: selected.lat };

            showSearchResults('<div class="searchResultItem"><div class="searchResultTitle">搜索中…</div></div>');
            placeSearch.searchNearBy(keyword, center, 20000, function(status, result) {
              try {
                if (status !== 'complete' || !result || !result.poiList || !result.poiList.pois) {
                  showSearchResults('');
                  return;
                }
                var pois = result.poiList.pois || [];
                if (!pois.length) {
                  showSearchResults('');
                  return;
                }

                var html = '';
                for (var i = 0; i < pois.length; i++) {
                  var p = pois[i];
                  var title = p && p.name ? p.name : '';
                  var addr = p && (p.address || p.type) ? (p.address || p.type) : '';
                  var loc = p && p.location ? p.location : null;
                  var lnglat = parsePoiLngLat(loc);
                  if (!lnglat) continue;
                  var lng = lnglat[0], lat = lnglat[1];
                  html += ''
                    + '<div class="searchResultItem" data-lng="' + lng + '" data-lat="' + lat + '">'
                    +   '<div class="searchResultTitle">' + escapeHtml(title) + '</div>'
                    +   (addr ? '<div class="searchResultSub">' + escapeHtml(addr) + '</div>' : '')
                    + '</div>';
                }
                showSearchResults(html);

                var box = document.getElementById('searchResults');
                if (box) {
                  var items = box.getElementsByClassName('searchResultItem');
                  for (var j = 0; j < items.length; j++) {
                    items[j].onclick = function() {
                      var lng2 = parseFloat(this.getAttribute('data-lng'));
                      var lat2 = parseFloat(this.getAttribute('data-lat'));
                      if (isNaN(lng2) || isNaN(lat2)) return;
                      // 使用同一个“选点 marker”替换位置
                      try {
                        setPickedPoint(lng2, lat2);
                      } catch (e1) {}
                      hideSearchResults();
                    };
                  }
                }
              } catch (e1) {
                showSearchResults('');
              }
            });
          } catch (e) {
            showSearchResults('');
          }
        }

        function bindSearchEvents() {
          try {
            var input = document.getElementById('searchInput');
            var btn = document.getElementById('searchBtn');
            if (btn) btn.onclick = function() { doNearbySearch(input.value); };
            if (input) {
              input.addEventListener('keydown', function(e) {
                if (e && (e.key === 'Enter' || e.keyCode === 13)) {
                  doNearbySearch(input.value);
                }
              });
            }
          } catch (e0) {}
        }

        bindSearchEvents();

        // 注入 PlaceSearch，并在未设置地点时自动以“小区名称”触发一次搜索
        try {
          AMap.plugin(['AMap.PlaceSearch'], function() {
            try {
              placeSearch = new AMap.PlaceSearch({ pageSize: 8, pageIndex: 1, citylimit: true });
              placeSearchReady = true;
              var input = document.getElementById('searchInput');
              if (input && autoSearchKeyword && autoSearchKeyword.trim()) {
                input.value = autoSearchKeyword;
                doNearbySearch(autoSearchKeyword);
              }
            } catch (e) {}
          });
        } catch (e) {}

        function setMarkerLabel(text) {
          var t = (text || '').trim();
          if (!t) return;
          try {
            marker.setLabel({
              content: '<div style="max-width:220px;padding:4px 8px;background:#fff;border-radius:8px;box-shadow:0 1px 4px rgba(0,0,0,.15);font-size:12px;line-height:1.35;color:#2d3436;">' + t.replace(/</g, '&lt;') + '</div>',
              direction: 'top',
              offset: new AMap.Pixel(0, -6)
            });
          } catch (e) {}
        }

        function applyRegeocode(rg) {
          if (!rg) return;
          selected.address = formatFullAddress(rg);
          selected.communityName = pickCommunityName(rg);
          if (!selected.address) {
            document.getElementById('tips').innerText = '点击地图选择位置';
            return;
          }
          var tip = selected.communityName
            ? (selected.communityName + ' · ' + selected.address)
            : selected.address;
          document.getElementById('tips').innerText = tip;
          setMarkerLabel(tip);
        }

        function updateAddress(lng, lat) {
          document.getElementById('tips').innerText = '正在解析位置…';
          geocoder.getAddress([lng, lat], function(status, result) {
            if (status === 'complete' && result && result.regeocode) {
              applyRegeocode(result.regeocode);
              return;
            }
            if (status === 'complete' && result && result.regeocodes && result.regeocodes.length) {
              applyRegeocode(result.regeocodes[0]);
              return;
            }
            selected.address = '';
            selected.communityName = '';
            document.getElementById('tips').innerText = '无法解析该点地址，请稍移动选点';
          });
        }

        map.on('click', function(e) {
          selected.lng = e.lnglat.getLng();
          selected.lat = e.lnglat.getLat();
          marker.setPosition([selected.lng, selected.lat]);
          updateAddress(selected.lng, selected.lat);
        });

        marker.on('dragend', function(e) {
          selected.lng = e.lnglat.getLng();
          selected.lat = e.lnglat.getLat();
          updateAddress(selected.lng, selected.lat);
        });

        map.on('complete', function() {
          try { map.resize(); } catch (e) {}
        });

        if (!selected.address) {
          updateAddress(selected.lng, selected.lat);
        } else {
          document.getElementById('tips').innerText = selected.address;
          setMarkerLabel(selected.address);
        }

        document.getElementById('confirm').onclick = function() {
          postToDart({
            type: 'picked',
            longitude: selected.lng,
            latitude: selected.lat,
            location_text: selected.address || '',
            community_name: selected.communityName || ''
          });
        };
      });
    </script>
  </body>
</html>''';
}
