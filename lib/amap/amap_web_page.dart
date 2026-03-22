import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'amap_config.dart';
import 'amap_html.dart';

/// Android 默认 Surface 纹理模式常导致高德 WebGL 地图首帧空白或白屏，需 Hybrid Composition。
/// 底部弹层内 WebView 需抢占手势，否则地图无法拖拽/点选。
Widget _platformWebViewWidget(WebViewController controller) {
  PlatformWebViewWidgetCreationParams params = PlatformWebViewWidgetCreationParams(
    controller: controller.platform,
    layoutDirection: TextDirection.ltr,
    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
    },
  );
  if (WebViewPlatform.instance is AndroidWebViewPlatform) {
    params = AndroidWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
      params,
      displayWithHybridComposition: true,
    );
  }
  return WebViewWidget.fromPlatformCreationParams(params: params);
}

bool get _inlineWebViewAvailable => WebViewPlatform.instance != null;

/// 房源地图 WebView（点击标记通过 [onOpenDetail] 回传记录 id）
class AmapHouseMapWebView extends StatefulWidget {
  const AmapHouseMapWebView({
    super.key,
    required this.amapKey,
    required this.markerPayload,
    required this.onOpenDetail,
    this.centerLongitude = 121.4737,
    this.centerLatitude = 31.2304,
    this.onMapLoadStarted,
    this.onMapJsReady,
    this.onWebViewControllerCreated,
  });

  final String amapKey;
  final List<Map<String, dynamic>> markerPayload;
  final void Function(String id) onOpenDetail;

  /// 无房源标记时的地图中心（通常为当前定位）；有标记时脚本内会 setFitView。
  final double centerLongitude;
  final double centerLatitude;

  /// WebView 开始加载 / 高德 map complete（瓦片可交互）时回调，用于首屏遮罩。
  final VoidCallback? onMapLoadStarted;
  final VoidCallback? onMapJsReady;
  final void Function(WebViewController controller)? onWebViewControllerCreated;

  @override
  State<AmapHouseMapWebView> createState() => _AmapHouseMapWebViewState();
}

class _AmapHouseMapWebViewState extends State<AmapHouseMapWebView> {
  WebViewController? _controller;
  String _lastHtmlKey = '';
  String? _lastOpenedDetailId;
  DateTime? _lastOpenedDetailAt;

  String _htmlCacheKey() =>
      '${jsonEncode(widget.markerPayload)}_${widget.centerLongitude}_${widget.centerLatitude}_${widget.amapKey}_${getAmapSecurityJsCode()}';

  @override
  void initState() {
    super.initState();
    if (_inlineWebViewAvailable) {
      _createController();
    }
  }

  @override
  void didUpdateWidget(covariant AmapHouseMapWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_inlineWebViewAvailable) return;
    if (oldWidget.amapKey != widget.amapKey) {
      _createController();
      return;
    }
    final next = _htmlCacheKey();
    if (next != _lastHtmlKey) {
      _lastHtmlKey = next;
      _reloadHtml();
    }
  }

  Future<void> _createController() async {
    _notifyLoadStarted();
    final html = buildAmapMarkersHtml(
      amapKey: widget.amapKey,
      markers: widget.markerPayload,
      centerLng: widget.centerLongitude,
      centerLat: widget.centerLatitude,
      securityJsCode: getAmapSecurityJsCode(),
    );
    _lastHtmlKey = _htmlCacheKey();
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF0F0F3))
      ..addJavaScriptChannel(
        'AmapBridge',
        onMessageReceived: (JavaScriptMessage m) {
          try {
            final map = jsonDecode(m.message) as Map<String, dynamic>;
            if (map['type'] == 'ready') {
              widget.onMapJsReady?.call();
              return;
            }
            if (map['type'] == 'open' && map['id'] != null) {
              final id = map['id'].toString();
              final now = DateTime.now();
              if (_lastOpenedDetailId == id &&
                  _lastOpenedDetailAt != null &&
                  now.difference(_lastOpenedDetailAt!) < const Duration(milliseconds: 500)) {
                return;
              }
              _lastOpenedDetailId = id;
              _lastOpenedDetailAt = now;
              widget.onOpenDetail(id);
            }
          } catch (_) {}
        },
      )
      ..loadHtmlString(html, baseUrl: 'https://webapi.amap.com/');
    if (mounted) {
      setState(() => _controller = c);
      widget.onWebViewControllerCreated?.call(c);
    }
  }

  void _notifyLoadStarted() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onMapLoadStarted?.call();
    });
  }

  Future<void> _reloadHtml() async {
    _notifyLoadStarted();
    final html = buildAmapMarkersHtml(
      amapKey: widget.amapKey,
      markers: widget.markerPayload,
      centerLng: widget.centerLongitude,
      centerLat: widget.centerLatitude,
      securityJsCode: getAmapSecurityJsCode(),
    );
    await _controller?.loadHtmlString(html, baseUrl: 'https://webapi.amap.com/');
  }

  Future<void> _openMarkerInBrowser(Map<String, dynamic> item) async {
    final lat = (item['lat'] as num?)?.toDouble();
    final lng = (item['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final name = item['name']?.toString() ?? '房源';
    final uri = Uri.parse(
      'https://uri.amap.com/marker?position=$lng,$lat&name=${Uri.encodeComponent(name)}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (!_inlineWebViewAvailable) {
      return _MapDesktopFallback(
        markers: widget.markerPayload,
        onOpenDetail: widget.onOpenDetail,
        onOpenInBrowser: _openMarkerInBrowser,
      );
    }
    final c = _controller;
    if (c == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return _platformWebViewWidget(c);
  }
}

class _MapDesktopFallback extends StatelessWidget {
  const _MapDesktopFallback({
    required this.markers,
    required this.onOpenDetail,
    required this.onOpenInBrowser,
  });

  final List<Map<String, dynamic>> markers;
  final void Function(String id) onOpenDetail;
  final Future<void> Function(Map<String, dynamic> item) onOpenInBrowser;

  @override
  Widget build(BuildContext context) {
    const textMuted = Color(0xFFB2BEC3);
    const textSecondary = Color(0xFF636E72);
    const primary = Color(0xFF6C63FF);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Text(
            '当前为 Windows / Linux 桌面版，系统未提供内嵌 WebView。\n'
            '请使用 Android / iOS 模拟器或真机查看完整地图，或在下列表中打开浏览器查看位置。',
            style: TextStyle(color: textSecondary, fontSize: 13, height: 1.45),
          ),
        ),
        Expanded(
          child: markers.isEmpty
              ? const Center(child: Text('暂无带坐标的房源', style: TextStyle(color: textMuted)))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: markers.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final item = markers[i];
                    final id = item['id'] as String? ?? '';
                    final name = item['name']?.toString() ?? '';
                    final titleLine = item['titleLine']?.toString() ?? name;
                    final lat = item['lat'];
                    final lng = item['lng'];
                    final room = item['roomSummary']?.toString() ?? '';
                    final price = item['price']?.toString() ?? '';
                    final sub = item['subtitle']?.toString() ?? '';
                    final subLines = [
                      if (room.isNotEmpty) room,
                      if (price.isNotEmpty && price != '--') price,
                      if (sub.isNotEmpty) sub,
                      '$lat, $lng',
                    ].join('\n');
                    return ListTile(
                      title: Text(titleLine),
                      isThreeLine: subLines.split('\n').length > 2,
                      subtitle: Text(subLines, style: const TextStyle(fontSize: 12, height: 1.35)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '浏览器打开',
                            icon: const Icon(Icons.map_outlined, color: primary),
                            onPressed: () => onOpenInBrowser(item),
                          ),
                          IconButton(
                            tooltip: '详情',
                            icon: const Icon(Icons.chevron_right),
                            onPressed: id.isEmpty ? null : () => onOpenDetail(id),
                          ),
                        ],
                      ),
                      onTap: id.isEmpty ? null : () => onOpenDetail(id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// 全屏/大半屏地图选点
class AmapPickerWebView extends StatefulWidget {
  const AmapPickerWebView({
    super.key,
    required this.amapKey,
    required this.initialLng,
    required this.initialLat,
    required this.initialAddress,
    required this.onPicked,
  });

  final String amapKey;
  final double initialLng;
  final double initialLat;
  final String initialAddress;
  /// [communityName] 为逆地理提取的小区/社区名，用于回填「小区名称」。
  final void Function(double latitude, double longitude, String locationText, String communityName) onPicked;

  @override
  State<AmapPickerWebView> createState() => _AmapPickerWebViewState();
}

class _AmapPickerWebViewState extends State<AmapPickerWebView> {
  WebViewController? _controller;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;
  late final TextEditingController _addrCtrl;

  @override
  void initState() {
    super.initState();
    _latCtrl = TextEditingController(text: widget.initialLat.toString());
    _lngCtrl = TextEditingController(text: widget.initialLng.toString());
    _addrCtrl = TextEditingController(text: widget.initialAddress);
    if (_inlineWebViewAvailable) {
      final html = buildAmapPickerHtml(
        amapKey: widget.amapKey,
        initialLng: widget.initialLng,
        initialLat: widget.initialLat,
        initialAddress: widget.initialAddress,
        securityJsCode: getAmapSecurityJsCode(),
      );
      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..addJavaScriptChannel(
          'AmapBridge',
          onMessageReceived: (JavaScriptMessage m) {
            try {
              final map = jsonDecode(m.message) as Map<String, dynamic>;
              if (map['type'] == 'picked') {
                final lat = (map['latitude'] as num?)?.toDouble();
                final lng = (map['longitude'] as num?)?.toDouble();
                if (lat != null && lng != null) {
                  final text = (map['location_text'] as String?)?.trim() ?? '';
                  final community = (map['community_name'] as String?)?.trim() ?? '';
                  widget.onPicked(lat, lng, text, community);
                }
              }
            } catch (_) {}
          },
        )
        ..loadHtmlString(html, baseUrl: 'https://webapi.amap.com/');
      setState(() => _controller = c);
    }
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  void _submitManual() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lng == null) {
      return;
    }
    widget.onPicked(lat, lng, _addrCtrl.text.trim(), '');
  }

  Future<void> _openReferenceMap() async {
    final lng = double.tryParse(_lngCtrl.text.trim()) ?? widget.initialLng;
    final lat = double.tryParse(_latCtrl.text.trim()) ?? widget.initialLat;
    final uri = Uri.parse(
      'https://uri.amap.com/marker?position=$lng,$lat&name=${Uri.encodeComponent('选点参考')}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (!_inlineWebViewAvailable) {
      const textSecondary = Color(0xFF636E72);
      const primary = Color(0xFF6C63FF);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '桌面版无法内嵌高德选点页。请填写经纬度（可从高德网页地图复制），或点击按钮在浏览器中打开参考位置。',
              style: TextStyle(color: textSecondary, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _latCtrl,
              decoration: const InputDecoration(labelText: '纬度 latitude'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lngCtrl,
              decoration: const InputDecoration(labelText: '经度 longitude'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addrCtrl,
              decoration: const InputDecoration(labelText: '位置描述（可选）'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _openReferenceMap,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('在浏览器打开当前坐标（高德）'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _submitManual,
              style: FilledButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
    final c = _controller;
    if (c == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return _platformWebViewWidget(c);
  }
}
