import 'package:http/http.dart' as http;

/// 从分享文案 / 网页补充解析出的字段（均为可选，按需填入表单）。
class ListingShareFields {
  ListingShareFields({
    this.community,
    this.address,
    this.price,
    this.area,
    this.bedrooms,
    this.livingRooms,
    this.bathrooms,
    this.totalFloors,
    this.sourceUrl,
    this.locationHint,
    this.unitPriceYuanPerSqm,
    this.rawPlatform,
  });

  final String? community;
  final String? address;
  final String? price;
  final String? area;
  final int? bedrooms;
  final int? livingRooms;
  final int? bathrooms;
  final int? totalFloors;
  final String? sourceUrl;
  /// 区域/商圈等位置提示，可写入「位置描述」
  final String? locationHint;
  final String? unitPriceYuanPerSqm;
  final String? rawPlatform;

  /// 合并时 **优先保留 this**（本地粘贴解析），网页仅补空白字段。
  ListingShareFields merge(ListingShareFields? other) {
    if (other == null) return this;
    return ListingShareFields(
      community: community ?? other.community,
      address: address ?? other.address,
      price: price ?? other.price,
      area: area ?? other.area,
      bedrooms: bedrooms ?? other.bedrooms,
      livingRooms: livingRooms ?? other.livingRooms,
      bathrooms: bathrooms ?? other.bathrooms,
      totalFloors: totalFloors ?? other.totalFloors,
      sourceUrl: sourceUrl ?? other.sourceUrl,
      locationHint: locationHint ?? other.locationHint,
      unitPriceYuanPerSqm: unitPriceYuanPerSqm ?? other.unitPriceYuanPerSqm,
      rawPlatform: rawPlatform ?? other.rawPlatform,
    );
  }
}

String? extractFirstHttpUrl(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final lower = t.toLowerCase();
  var idx = lower.indexOf('https://');
  if (idx < 0) idx = lower.indexOf('http://');
  if (idx < 0) return null;
  var end = t.length;
  for (var k = idx; k < t.length; k++) {
    final ch = t[k];
    if (ch == ' ' || ch == '\n' || ch == '\r' || ch == '】' || ch == '"' || ch == '>' || ch == '<') {
      end = k;
      break;
    }
    // 句号结束句子（URL 内极少出现未编码的。）
    if (ch == '。' && k + 1 < t.length && (t[k + 1] == '来' || t[k + 1] == '（')) {
      end = k;
      break;
    }
  }
  var url = t.substring(idx, end);
  while (url.isNotEmpty && '，,；;。）)'.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }
  if (url.isEmpty) return null;
  final parsed = Uri.tryParse(url);
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) return null;
  return url;
}

bool _isAnjukeUrl(String u) => u.contains('anjuke.com');
bool _isBeikeUrl(String u) => u.contains('ke.com') || u.contains('lianjia.com');

/// 安居客 App 分享：`小区 | 总价 | 户型面积 | 区域商圈URL【安居客】`
ListingShareFields? parseAnjukePipeLine(String text) {
  if (!text.contains('|')) return null;
  if (!text.contains('anjuke') && !text.contains('安居客')) return null;

  final parts = text.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  if (parts.length < 3) return null;

  final community = parts[0];
  final price = parts[1];
  String? area;
  int? bed;
  int? liv;
  String? locationHint;
  String? url;

  final layoutArea = parts[2];
  final la = RegExp(r'(\d)\s*室\s*(\d)\s*厅').firstMatch(layoutArea);
  if (la != null) {
    bed = int.tryParse(la.group(1)!);
    liv = int.tryParse(la.group(2)!);
  }
  final ar = RegExp(r'(\d+(?:\.\d+)?)\s*(?:㎡|m²|平米|平方)').firstMatch(layoutArea);
  if (ar != null) area = ar.group(1);

  if (parts.length >= 4) {
    final last = parts.sublist(3).join(' | ');
    url = extractFirstHttpUrl(last) ?? RegExp(r'https?://[^\s]+').firstMatch(last)?.group(0);
    var hint = last;
    if (url != null) {
      hint = last.replaceAll(url, '').trim();
    }
    if (hint.isNotEmpty) locationHint = hint;
  }

  return ListingShareFields(
    community: community.isNotEmpty ? community : null,
    price: price.isNotEmpty ? price : null,
    area: area,
    bedrooms: bed,
    livingRooms: liv,
    sourceUrl: url,
    locationHint: locationHint,
    rawPlatform: 'anjuke',
  );
}

/// 贝壳 APP：`小区,室厅,面积,单价,总价,楼层/总层,朝向，详情：URL`
ListingShareFields? parseBeikeShareLine(String text) {
  final norm = text.replaceAll('，', ',');
  if (!norm.contains('ke.com') && !norm.contains('贝壳')) return null;

  final url = extractFirstHttpUrl(norm);
  final core = norm.split('详情').first;

  final m = RegExp(
    r'([^,]+),(\d+)室(\d+)厅,(\d+(?:\.\d+)?)平米,([\d,]+)元/平,(\d+(?:\.\d+)?)万,([^,/]+)/(\d+)层',
  ).firstMatch(core);

  if (m == null) return null;

  final community = m.group(1)!.trim();
  final bed = int.tryParse(m.group(2)!);
  final liv = int.tryParse(m.group(3)!);
  final area = m.group(4);
  final unitRaw = m.group(5)!.replaceAll(',', '');
  final price = '${m.group(6)}万';
  final totalFloors = int.tryParse(m.group(8)!);

  return ListingShareFields(
    community: community.isNotEmpty ? community : null,
    price: price,
    area: area,
    bedrooms: bed,
    livingRooms: liv,
    totalFloors: totalFloors,
    sourceUrl: url,
    unitPriceYuanPerSqm: unitRaw.isNotEmpty ? '$unitRaw 元/㎡' : null,
    rawPlatform: 'beike',
  );
}

String? _metaContent(String html, String nameOrProp) {
  final re1 = RegExp(
    '<meta[^>]+(?:name|property)=["\']($nameOrProp)["\'][^>]+content=["\']([^"\']*)["\']',
    caseSensitive: false,
  );
  final m1 = re1.firstMatch(html);
  if (m1 != null) return m1.group(2)?.trim();
  final re2 = RegExp(
    '<meta[^>]+content=["\']([^"\']*)["\'][^>]+(?:name|property)=["\']($nameOrProp)["\']',
    caseSensitive: false,
  );
  final m2 = re2.firstMatch(html);
  return m2?.group(1)?.trim();
}


String? _titleFromHtml(String html) {
  final m = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false).firstMatch(html);
  return m?.group(1)?.trim();
}

String _stripListingSiteSuffix(String title) {
  var s = title;
  s = s.replaceAll(RegExp(r'\s*[-_|]\s*芜湖.*?二手房.*$', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'\s*[-_|].*安居客.*$', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'\s*[-_|].*贝壳.*$', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'\s*[-_|].*链家.*$', caseSensitive: false), '');
  return s.trim();
}

/// 请求移动版页面，从 title / meta 补充小区名与位置描述（可能失败，不抛异常）。
Future<ListingShareFields> fetchListingPageHints(Uri uri) async {
  try {
    final resp = await http
        .get(
          uri,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          },
        )
        .timeout(const Duration(seconds: 12));

    if (resp.statusCode != 200 || resp.body.isEmpty) {
      return ListingShareFields();
    }

    final body = resp.body;
    final ogTitle = _metaContent(body, 'og:title');
    final ogDesc = _metaContent(body, 'og:description');
    final title = _titleFromHtml(body);

    String? nameFromTitle = ogTitle ?? title;
    if (nameFromTitle != null && nameFromTitle.isNotEmpty) {
      nameFromTitle = _stripListingSiteSuffix(nameFromTitle);
    }

    final loc = (ogDesc != null && ogDesc.isNotEmpty) ? ogDesc : null;

    return ListingShareFields(
      community: (nameFromTitle != null && nameFromTitle.isNotEmpty) ? nameFromTitle : null,
      locationHint: loc,
      sourceUrl: uri.toString(),
      rawPlatform: _isAnjukeUrl(uri.host) ? 'anjuke_web' : (_isBeikeUrl(uri.host) ? 'beike_web' : null),
    );
  } catch (_) {
    return ListingShareFields();
  }
}

/// 主入口：先按平台解析粘贴文案，再根据 URL 尝试拉网页补充。
Future<ListingShareFields> parseListingShareWithOptionalWeb(String pasted) async {
  final text = pasted.trim();
  if (text.isEmpty) {
    return ListingShareFields();
  }

  ListingShareFields? local;

  final urlStr = extractFirstHttpUrl(text);
  if (urlStr != null) {
    final u = Uri.tryParse(urlStr);
    if (u != null && u.hasScheme) {
      if (_isAnjukeUrl(urlStr)) {
        local = parseAnjukePipeLine(text);
      } else if (_isBeikeUrl(urlStr)) {
        local = parseBeikeShareLine(text);
      }
    }
  }

  local ??= parseAnjukePipeLine(text);
  local ??= parseBeikeShareLine(text);

  if (local == null) {
    local = ListingShareFields(sourceUrl: urlStr, rawPlatform: 'generic');
  } else if (local.sourceUrl == null && urlStr != null) {
    local = local.merge(ListingShareFields(sourceUrl: urlStr));
  }

  final fetchUri = Uri.tryParse(local.sourceUrl ?? urlStr ?? '');
  if (fetchUri == null || !fetchUri.hasScheme || !{'http', 'https'}.contains(fetchUri.scheme)) {
    return local;
  }

  if (!_isAnjukeUrl(fetchUri.toString()) && !_isBeikeUrl(fetchUri.toString())) {
    return local;
  }

  final web = await fetchListingPageHints(fetchUri);
  return local.merge(web);
}

/// 通用规则（与 main 中原有逻辑一致），不依赖平台；仅对仍为空的字段赋值。
void applyGenericTextHeuristics(String text, void Function(String key, String value) setIfEmpty) {
  String? pick(RegExp re) => re.firstMatch(text)?.group(1)?.trim();
  final urlStr = extractFirstHttpUrl(text);

  final fromLabel = pick(RegExp(r'(?:小区|楼盘|项目|房源)\s*[:：]\s*([^\n，,。；;]{2,30})', caseSensitive: false));
  final bracket = pick(RegExp(r'【([^】]{2,30})】'));
  final community = fromLabel ??
      (bracket != null && !RegExp(r'^(安居客|贝壳|贝壳找房|链家)').hasMatch(bracket) ? bracket : null);
  if (community != null && community.isNotEmpty) setIfEmpty('community', community);

  final b = pick(RegExp(r'(\d+)\s*栋'));
  if (b != null) setIfEmpty('building', b);

  final units = pick(RegExp(r'(?:总单元|共)\s*(\d+)\s*单元'));
  if (units != null) setIfEmpty('totalUnits', units);

  final room = pick(RegExp(r'(\d{2,4})\s*(?:室|房号)', caseSensitive: false)) ??
      pick(RegExp(r'(?:房号)\s*[:：]\s*([A-Za-z0-9-]{2,10})', caseSensitive: false));
  if (room != null) setIfEmpty('room', room);

  final floorSlash = RegExp(r'(?:楼层)?\s*(\d+)\s*/\s*(\d+)\s*层').firstMatch(text);
  if (floorSlash != null) setIfEmpty('totalFloors', floorSlash.group(2)!);

  final rtm3 = RegExp(r'(\d)\s*室\s*(\d)\s*厅\s*(\d)\s*卫').firstMatch(text);
  if (rtm3 != null) {
    setIfEmpty('bedrooms', rtm3.group(1)!);
    setIfEmpty('living', rtm3.group(2)!);
    setIfEmpty('bath', rtm3.group(3)!);
  } else {
    final rtm2 = RegExp(r'(\d)\s*室\s*(\d)\s*厅').firstMatch(text);
    if (rtm2 != null) {
      setIfEmpty('bedrooms', rtm2.group(1)!);
      setIfEmpty('living', rtm2.group(2)!);
    }
  }

  final ar = pick(RegExp(r'(\d+(?:\.\d+)?)\s*(?:㎡|m²|平米|平方)', caseSensitive: false));
  if (ar != null) setIfEmpty('area', ar);

  final pr = pick(RegExp(r'(?:总价|售价|价格|租金)\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?\s*(?:万|元/月|元))', caseSensitive: false));
  if (pr != null) setIfEmpty('price', pr);

  final phone = pick(RegExp(r'(1[3-9]\d{9})'));
  if (phone != null) setIfEmpty('phone', phone);

  final agent = pick(RegExp(r'(?:经纪人|联系人|置业顾问)\s*[:：]?\s*([^\s，。,；;]{2,10})', caseSensitive: false));
  if (agent != null) setIfEmpty('agent', agent);

  if (urlStr != null && urlStr.isNotEmpty) setIfEmpty('sourceUrl', urlStr);
}
