import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:house_viewing_diary_flutter/amap/amap_config.dart';
import 'package:house_viewing_diary_flutter/amap/current_location.dart';
import 'package:house_viewing_diary_flutter/amap/amap_web_page.dart';
import 'package:house_viewing_diary_flutter/amap/webview_init_stub.dart' if (dart.library.html) 'package:house_viewing_diary_flutter/amap/webview_init_web.dart' as webview_init;
import 'package:house_viewing_diary_flutter/file_image_widget.dart';
import 'package:house_viewing_diary_flutter/local_media_preview.dart';
import 'package:house_viewing_diary_flutter/voice_note_dir_stub.dart'
    if (dart.library.io) 'package:house_viewing_diary_flutter/voice_note_dir_io.dart' as voice_note_dir;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _storageKey = 'house_viewings_flutter';
const _tagsStorageKey = 'house_viewing_tags_flutter';
/// 与 RN `client/constants/theme.ts` light 主题对齐
const _bgRoot = Color(0xFFF0F0F3);
const _bgTertiary = Color(0xFFE8E8EB);
const _textPrimary = Color(0xFF2D3436);
const _textSecondary = Color(0xFF636E72);
const _textMuted = Color(0xFFB2BEC3);
const _borderLight = Color(0xFFE8E8EB);
const _border = Color(0xFFD1D9E6);
const _primary = Color(0xFF6C63FF);
const _accent = Color(0xFFFF6584);
const _errorColor = Color(0xFFFF6B6B);
const _defaultTagList = ['边户', '高层', '电梯房', '近地铁', '采光好', '南北通透'];

BoxDecoration _neuOuter() {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(24),
    boxShadow: const [
      BoxShadow(
        color: Color(0x66D1D9E6),
        offset: Offset(6, 6),
        blurRadius: 10,
      ),
    ],
  );
}

BoxDecoration _neuInner() {
  return BoxDecoration(
    color: _bgRoot,
    borderRadius: BorderRadius.circular(24),
    boxShadow: const [
      BoxShadow(
        color: Colors.white,
        offset: Offset(-6, -6),
        blurRadius: 10,
      ),
    ],
  );
}

/// 看房记录详情/编辑页的分块卡片
Widget _viewingDetailSection({required String title, required List<Widget> children}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    decoration: _neuOuter(),
    child: Container(
      decoration: _neuInner(),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _textPrimary)),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  webview_init.registerWebViewForWeb();
  try {
    await dotenv.load(fileName: 'assets/amap.env');
  } catch (e, st) {
    debugPrint('加载 assets/amap.env 失败（地图 Key 可用 --dart-define=AMAP_KEY）：$e\n$st');
  }
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: _bgRoot,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const HouseViewingDiaryApp());
}

class HouseViewingDiaryApp extends StatelessWidget {
  const HouseViewingDiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '看房日记',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _primary),
        useMaterial3: true,
        scaffoldBackgroundColor: _bgRoot,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          foregroundColor: _textPrimary,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _bgTertiary,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _borderLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _borderLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _primary, width: 1.4),
          ),
        ),
      ),
      home: const RootPage(),
    );
  }
}

enum ViewStatus { pending, viewed, interested, booked, abandoned }

extension ViewStatusX on ViewStatus {
  String get label {
    switch (this) {
      case ViewStatus.pending:
        return '待看';
      case ViewStatus.viewed:
        return '已看';
      case ViewStatus.interested:
        return '感兴趣';
      case ViewStatus.booked:
        return '已定';
      case ViewStatus.abandoned:
        return '放弃';
    }
  }

  Color get color {
    switch (this) {
      case ViewStatus.pending:
        return const Color(0xFF6C63FF);
      case ViewStatus.viewed:
        return const Color(0xFF00B894);
      case ViewStatus.interested:
        return const Color(0xFFFDCB6E);
      case ViewStatus.booked:
        return const Color(0xFF00B894);
      case ViewStatus.abandoned:
        return const Color(0xFFB2BEC3);
    }
  }

  Color get bgColor => color.withValues(alpha: 0.14);
}

/// 单次看房记录（一套房可有多条）
class ViewingHistoryEntry {
  ViewingHistoryEntry({
    required this.id,
    required this.viewedAt,
    required this.status,
    this.comment,
    this.voiceNotePaths = const [],
    this.mediaUris = const [],
  });

  final String id;
  final DateTime viewedAt;
  final ViewStatus status;
  final String? comment;
  /// 本地录音文件路径列表（可多段，按录制顺序）
  final List<String> voiceNotePaths;
  final List<String> mediaUris;

  Map<String, dynamic> toJson() => {
        'id': id,
        'viewedAt': viewedAt.toIso8601String(),
        'status': status.name,
        'comment': comment,
        'voiceNotePaths': voiceNotePaths,
        // 兼容仅读 voiceNotePath 的旧逻辑
        if (voiceNotePaths.isNotEmpty) 'voiceNotePath': voiceNotePaths.first,
        'mediaUris': mediaUris,
      };

  ViewingHistoryEntry copyWith({
    String? id,
    DateTime? viewedAt,
    ViewStatus? status,
    String? comment,
    List<String>? voiceNotePaths,
    List<String>? mediaUris,
  }) {
    return ViewingHistoryEntry(
      id: id ?? this.id,
      viewedAt: viewedAt ?? this.viewedAt,
      status: status ?? this.status,
      comment: comment ?? this.comment,
      voiceNotePaths: voiceNotePaths ?? this.voiceNotePaths,
      mediaUris: mediaUris ?? this.mediaUris,
    );
  }

  /// 容错解析，避免脏数据导致详情页闪退。
  /// [listIndex] 用于无 id 的旧数据：生成稳定 uuid，避免每次加载 id 变化导致「编辑保存不生效」。
  static ViewingHistoryEntry? tryParse(Map<String, dynamic> json, {int listIndex = 0}) {
    try {
      DateTime viewedAt;
      final va = json['viewedAt'];
      if (va is String && va.isNotEmpty) {
        viewedAt = DateTime.tryParse(va) ?? DateTime.now();
      } else if (va is int) {
        viewedAt = DateTime.fromMillisecondsSinceEpoch(va);
      } else {
        viewedAt = DateTime.now();
      }

      final idRaw = json['id'];
      final comment = json['comment'] is String ? json['comment'] as String? : json['comment']?.toString();
      final String id;
      if (idRaw is String && idRaw.isNotEmpty) {
        id = idRaw;
      } else {
        final seed = 'vhe_${listIndex}_${viewedAt.millisecondsSinceEpoch}_${comment ?? ''}';
        id = const Uuid().v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8', seed);
      }

      final st = json['status']?.toString();
      final status = ViewStatus.values.firstWhere(
        (e) => e.name == st,
        orElse: () => ViewStatus.pending,
      );

      var voiceNotePaths = <String>[];
      final vpl = json['voiceNotePaths'];
      if (vpl is List) {
        voiceNotePaths = vpl.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
      if (voiceNotePaths.isEmpty) {
        final vp = json['voiceNotePath'];
        if (vp is String && vp.isNotEmpty) voiceNotePaths = [vp];
      }

      List<String> mediaUris = const [];
      final mu = json['mediaUris'];
      if (mu is List) {
        mediaUris = mu.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }

      return ViewingHistoryEntry(
        id: id,
        viewedAt: viewedAt,
        status: status,
        comment: comment,
        voiceNotePaths: voiceNotePaths,
        mediaUris: mediaUris,
      );
    } catch (e, st) {
      debugPrint('ViewingHistoryEntry.tryParse: $e\n$st');
      return null;
    }
  }

  factory ViewingHistoryEntry.fromJson(Map<String, dynamic> json) {
    final o = tryParse(json);
    if (o != null) return o;
    return ViewingHistoryEntry(
      id: const Uuid().v4(),
      viewedAt: DateTime.now(),
      status: ViewStatus.pending,
    );
  }
}

List<ViewingHistoryEntry> _parseViewingHistoryFromJson(Map<String, dynamic> json) {
  final raw = json['viewingHistory'];
  if (raw is List && raw.isNotEmpty) {
    final out = <ViewingHistoryEntry>[];
    for (var i = 0; i < raw.length; i++) {
      final e = raw[i];
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final parsed = ViewingHistoryEntry.tryParse(m, listIndex: i);
      if (parsed != null) out.add(parsed);
    }
    if (out.isNotEmpty) return out;
  }
  final vd = json['viewingDate'];
  if (vd != null) {
    final d = DateTime.tryParse(vd as String);
    if (d != null) {
      return [
        ViewingHistoryEntry(
          id: const Uuid().v4(),
          viewedAt: d,
          status: ViewStatus.values.firstWhere(
            (e) => e.name == json['status'],
            orElse: () => ViewStatus.pending,
          ),
          comment: json['comment']?.toString(),
        ),
      ];
    }
  }
  return [];
}

bool _pathLooksLikeVideo(String path) {
  final lowered = path.toLowerCase();
  return lowered.endsWith('.mp4') ||
      lowered.endsWith('.mov') ||
      lowered.endsWith('.m4v') ||
      lowered.endsWith('.webm') ||
      lowered.endsWith('.avi');
}

/// 照片用缩略图，视频用图标占位（[fileImageOrPlaceholder] 对视频文件会解码失败）
Widget mediaThumb(String path, {double width = 70, double height = 70}) {
  if (_pathLooksLikeVideo(path)) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF2D3436),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.videocam_rounded, color: Colors.white70, size: 32),
    );
  }
  return fileImageOrPlaceholder(path, width: width, height: height);
}

class HouseViewing {
  HouseViewing({
    required this.id,
    required this.communityName,
    required this.status,
    required this.createdAt,
    this.address,
    this.building,
    this.roomNumber,
    this.totalUnits,
    this.totalFloors,
    this.bedrooms,
    this.livingRooms,
    this.bathrooms,
    this.area,
    this.price,
    this.agentName,
    this.agentPhone,
    this.latitude,
    this.longitude,
    this.locationText,
    this.sourceUrl,
    this.tags = const [],
    this.mediaUris = const [],
    this.viewingHistory = const [],
  });

  final String id;
  final String communityName;
  final String? address;
  final String? building;
  final String? roomNumber;
  final int? totalUnits;
  final int? totalFloors;
  final int? bedrooms;
  final int? livingRooms;
  final int? bathrooms;
  final String? area;
  final String? price;
  final ViewStatus status;
  final String? agentName;
  final String? agentPhone;
  final double? latitude;
  final double? longitude;
  final String? locationText;
  final String? sourceUrl;
  final List<String> tags;
  final List<String> mediaUris;
  final List<ViewingHistoryEntry> viewingHistory;
  final DateTime createdAt;

  /// 列表排序：有看房记录时取最近一条看房时间，否则用创建时间
  DateTime get sortTime {
    if (viewingHistory.isEmpty) return createdAt;
    return viewingHistory.map((e) => e.viewedAt).reduce((a, b) => a.isAfter(b) ? a : b);
  }

  HouseViewing copyWith({
    String? communityName,
    String? address,
    String? building,
    String? roomNumber,
    int? totalUnits,
    int? totalFloors,
    int? bedrooms,
    int? livingRooms,
    int? bathrooms,
    String? area,
    String? price,
    ViewStatus? status,
    String? agentName,
    String? agentPhone,
    double? latitude,
    double? longitude,
    String? locationText,
    String? sourceUrl,
    List<String>? tags,
    List<String>? mediaUris,
    List<ViewingHistoryEntry>? viewingHistory,
  }) {
    return HouseViewing(
      id: id,
      communityName: communityName ?? this.communityName,
      status: status ?? this.status,
      createdAt: createdAt,
      address: address ?? this.address,
      building: building ?? this.building,
      roomNumber: roomNumber ?? this.roomNumber,
      totalUnits: totalUnits ?? this.totalUnits,
      totalFloors: totalFloors ?? this.totalFloors,
      bedrooms: bedrooms ?? this.bedrooms,
      livingRooms: livingRooms ?? this.livingRooms,
      bathrooms: bathrooms ?? this.bathrooms,
      area: area ?? this.area,
      price: price ?? this.price,
      agentName: agentName ?? this.agentName,
      agentPhone: agentPhone ?? this.agentPhone,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationText: locationText ?? this.locationText,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      tags: tags ?? this.tags,
      mediaUris: mediaUris ?? this.mediaUris,
      viewingHistory: viewingHistory ?? this.viewingHistory,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'communityName': communityName,
      'address': address,
      'building': building,
      'roomNumber': roomNumber,
      'totalUnits': totalUnits,
      'totalFloors': totalFloors,
      'bedrooms': bedrooms,
      'livingRooms': livingRooms,
      'bathrooms': bathrooms,
      'area': area,
      'price': price,
      'status': status.name,
      'agentName': agentName,
      'agentPhone': agentPhone,
      'latitude': latitude,
      'longitude': longitude,
      'locationText': locationText,
      'sourceUrl': sourceUrl,
      'tags': tags,
      'mediaUris': mediaUris,
      'viewingHistory': viewingHistory.map((e) => e.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static HouseViewing fromJson(Map<String, dynamic> json) {
    return HouseViewing(
      id: json['id'] as String,
      communityName: json['communityName'] as String,
      status: ViewStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ViewStatus.pending,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      address: json['address'] as String?,
      building: json['building'] as String?,
      roomNumber: json['roomNumber'] as String?,
      totalUnits: json['totalUnits'] as int?,
      totalFloors: json['totalFloors'] as int?,
      bedrooms: json['bedrooms'] as int?,
      livingRooms: json['livingRooms'] as int?,
      bathrooms: json['bathrooms'] as int?,
      area: json['area'] as String?,
      price: json['price'] as String?,
      agentName: json['agentName'] as String?,
      agentPhone: json['agentPhone'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      locationText: json['locationText'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      mediaUris: (json['mediaUris'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      viewingHistory: _parseViewingHistoryFromJson(json),
    );
  }
}

/// 与编辑页「自动计算均价」同一套规则。
String? unitPriceHintFromHouseViewing(HouseViewing item) {
  final area = double.tryParse(item.area?.trim() ?? '');
  if (area == null || area <= 0) return null;
  final raw = (item.price ?? '').replaceAll(RegExp(r'\s'), '');
  final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(raw);
  if (m == null) return null;
  var n = double.tryParse(m.group(1)!);
  if (n == null || n <= 0) return null;
  if (raw.contains('万')) n = n * 10000;
  final unit = n / area;
  return '${unit.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (mm) => '${mm[1]},')} 元/㎡';
}

/// 地图标记卡片大标题：小区 + 楼号 + 房号
String mapMarkerTitleLine(HouseViewing e) {
  final c = e.communityName.trim();
  final rawB = (e.building ?? '').trim();
  final b = rawB.isEmpty ? '' : (rawB.endsWith('栋') ? rawB : '$rawB栋');
  final r = (e.roomNumber ?? '').trim();
  final parts = <String>[];
  if (c.isNotEmpty) parts.add(c);
  if (b.isNotEmpty) parts.add(b);
  if (r.isNotEmpty) parts.add(r);
  if (parts.isEmpty) return '未命名房源';
  return parts.join(' ');
}

class HouseViewingStore {
  static final _uuid = Uuid();

  static Future<List<HouseViewing>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return _seedData();
    final list = (jsonDecode(raw) as List<dynamic>)
        .map((e) => HouseViewing.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return list;
  }

  static Future<void> saveAll(List<HouseViewing> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  static Future<List<HouseViewing>> _seedData() async {
    final now = DateTime.now();
    final samples = <HouseViewing>[
      HouseViewing(
        id: _uuid.v4(),
        communityName: '阳光花园',
        building: '1',
        roomNumber: '301',
        totalUnits: 2,
        totalFloors: 18,
        bedrooms: 3,
        livingRooms: 2,
        bathrooms: 1,
        area: '120',
        price: '350万',
        status: ViewStatus.pending,
        tags: const ['边户', '采光好'],
        createdAt: now,
        viewingHistory: [
          ViewingHistoryEntry(
            id: _uuid.v4(),
            viewedAt: now,
            status: ViewStatus.pending,
          ),
        ],
      ),
      HouseViewing(
        id: _uuid.v4(),
        communityName: '翡翠湾花园',
        address: '浦东新区翡翠路88号',
        building: '3',
        roomNumber: '1201',
        totalUnits: 2,
        totalFloors: 33,
        bedrooms: 3,
        livingRooms: 2,
        bathrooms: 2,
        area: '128',
        price: '580万',
        status: ViewStatus.viewed,
        agentName: '王经理',
        agentPhone: '13812345678',
        tags: const ['高层', '近地铁'],
        latitude: 31.230416,
        longitude: 121.473701,
        locationText: '上海市（示例坐标，可编辑页重新选点）',
        createdAt: now.subtract(const Duration(days: 2)),
        viewingHistory: [
          ViewingHistoryEntry(
            id: _uuid.v4(),
            viewedAt: now.subtract(const Duration(days: 2)),
            status: ViewStatus.viewed,
            comment: '采光很好，户型方正，离地铁近。',
          ),
        ],
      ),
    ];
    await saveAll(samples);
    return samples;
  }
}

/// 与 RN `getGlobalTags` / `addGlobalTag` 行为一致
class GlobalTagStore {
  static Future<List<String>> getTags() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tagsStorageKey);
    if (raw == null || raw.isEmpty) return List<String>.from(_defaultTagList);
    try {
      final list = (jsonDecode(raw) as List<dynamic>).map((e) => e.toString()).toList();
      if (list.isEmpty) return List<String>.from(_defaultTagList);
      final merged = <String>{..._defaultTagList, ...list};
      return merged.take(50).toList();
    } catch (_) {
      return List<String>.from(_defaultTagList);
    }
  }

  static Future<List<String>> addTag(String tag) async {
    final t = tag.trim();
    final existing = await getTags();
    if (t.isEmpty) return existing;
    if (existing.contains(t)) return existing;
    final next = [...existing, t].take(50).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tagsStorageKey, jsonEncode(next));
    return next;
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;
  final GlobalKey<_MapPageState> _mapPageKey = GlobalKey<_MapPageState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: [
            const HomePage(),
            const StatsPage(),
            MapPage(key: _mapPageKey),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() => _index = value);
          if (value == 2) {
            _mapPageKey.currentState?.refreshMapData();
          }
        },
        height: 68,
        backgroundColor: _bgRoot,
        indicatorColor: const Color(0x226C63FF),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '看房记录'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: '统计'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: '地图'),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<HouseViewing> _items = [];
  bool _loading = true;
  String _keyword = '';
  ViewStatus? _filter;
  final _searchController = TextEditingController();

  static const int _kCalendarOrigin = 1200;
  late final PageController _calendarPageController;
  int _calendarVisiblePage = _kCalendarOrigin;

  @override
  void initState() {
    super.initState();
    _calendarPageController = PageController(initialPage: _kCalendarOrigin);
    _reload();
  }

  @override
  void dispose() {
    _calendarPageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// [page] 为 [PageView] 页码，中心页对应当前月。
  DateTime _monthForPage(int page) {
    final now = DateTime.now();
    return DateTime(now.year, now.month + (page - _kCalendarOrigin), 1);
  }

  Widget _buildMonthHeatGrid(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final totalDays = DateTime(month.year, month.month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7;
    final countMap = <int, int>{};
    for (final v in _items) {
      for (final h in v.viewingHistory) {
        final d = h.viewedAt;
        if (d.year == month.year && d.month == month.month) {
          countMap[d.day] = (countMap[d.day] ?? 0) + 1;
        }
      }
    }
    final maxCount = countMap.values.isEmpty ? 0 : countMap.values.reduce((a, b) => a > b ? a : b);
    Color heatColor(int c) {
      if (c == 0 || maxCount == 0) return _bgTertiary;
      final r = c / maxCount;
      if (r <= 0.34) return const Color(0x476C63FF);
      if (r <= 0.67) return const Color(0x856C63FF);
      return const Color(0xD16C63FF);
    }

    final rows = ((totalDays + startWeekday) / 7).ceil();
    final gridHeight = rows * 34.0 + (rows > 0 ? (rows - 1) * 6.0 : 0.0);

    return SizedBox(
      height: gridHeight,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (int i = 0; i < startWeekday; i++) const SizedBox(width: 34, height: 34),
          for (int day = 1; day <= totalDays; day++)
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: heatColor(countMap[day] ?? 0),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: (countMap[day] ?? 0) > 0 ? Colors.white : _textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _reload() async {
    final data = await HouseViewingStore.readAll();
    if (!mounted) return;
    setState(() {
      _items = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final filtered = _items.where((e) {
      final matchKeyword = _keyword.trim().isEmpty ||
          e.communityName.contains(_keyword) ||
          (e.address?.contains(_keyword) ?? false) ||
          (e.building?.contains(_keyword) ?? false);
      final matchStatus = _filter == null || e.status == _filter;
      return matchKeyword && matchStatus;
    }).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/images/logo.jpg',
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 48, height: 48),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text('看房日记', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('记录每一次看房的点点滴滴', style: TextStyle(color: _textSecondary, fontSize: 14)),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: _bgRoot,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _borderLight),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('看房日历', style: TextStyle(fontWeight: FontWeight.w700, color: _textPrimary)),
                      Text(
                        '${_monthForPage(_calendarVisiblePage).year}年${_monthForPage(_calendarVisiblePage).month}月',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: _primary, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('左右滑动切换月份', style: TextStyle(fontSize: 12, color: _textMuted)),
                  const SizedBox(height: 10),
                  const Row(
                    children: [
                      Expanded(child: Center(child: Text('日', style: TextStyle(fontSize: 12, color: _textMuted, fontWeight: FontWeight.w600)))),
                      Expanded(child: Center(child: Text('一', style: TextStyle(fontSize: 12, color: _textMuted, fontWeight: FontWeight.w600)))),
                      Expanded(child: Center(child: Text('二', style: TextStyle(fontSize: 12, color: _textMuted, fontWeight: FontWeight.w600)))),
                      Expanded(child: Center(child: Text('三', style: TextStyle(fontSize: 12, color: _textMuted, fontWeight: FontWeight.w600)))),
                      Expanded(child: Center(child: Text('四', style: TextStyle(fontSize: 12, color: _textMuted, fontWeight: FontWeight.w600)))),
                      Expanded(child: Center(child: Text('五', style: TextStyle(fontSize: 12, color: _textMuted, fontWeight: FontWeight.w600)))),
                      Expanded(child: Center(child: Text('六', style: TextStyle(fontSize: 12, color: _textMuted, fontWeight: FontWeight.w600)))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 248,
                    child: PageView.builder(
                      controller: _calendarPageController,
                      onPageChanged: (i) => setState(() => _calendarVisiblePage = i),
                      itemBuilder: (context, pageIndex) {
                        final month = _monthForPage(pageIndex);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: _buildMonthHeatGrid(month),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('颜色越深表示当天看房次数越多', style: TextStyle(fontSize: 12, color: _textMuted)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索小区、地址...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _keyword.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除',
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _keyword = '');
                        },
                      ),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: _bgTertiary,
              ),
              onChanged: (v) => setState(() => _keyword = v),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('全部'),
                  selected: _filter == null,
                  backgroundColor: _bgTertiary,
                  side: const BorderSide(color: Color(0x66FFFFFF)),
                  onSelected: (_) => setState(() => _filter = null),
                ),
                for (final s in ViewStatus.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _filter == s,
                    backgroundColor: Colors.white,
                    selectedColor: s.bgColor,
                    side: BorderSide(color: _filter == s ? s.color : const Color(0xFFE5E9F5)),
                    labelStyle: TextStyle(color: _filter == s ? s.color : _textSecondary, fontWeight: FontWeight.w600),
                    onSelected: (_) => setState(() => _filter = s),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (filtered.isEmpty) const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('暂无记录')),
            ),
            for (final item in filtered)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: _neuOuter(),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => DetailPage(item: item)),
                      );
                      _reload();
                    },
                    child: Container(
                      decoration: _neuInner(),
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.communityName,
                                  style: const TextStyle(color: _textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: item.status.bgColor, borderRadius: BorderRadius.circular(999)),
                                child: Text(item.status.label, style: TextStyle(color: item.status.color, fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${item.bedrooms ?? '-'}室${item.livingRooms ?? '-'}厅${item.bathrooms ?? '-'}卫 · ${item.area ?? '--'}㎡ · ${item.building ?? '--'}栋 ${item.roomNumber ?? ''}',
                            style: const TextStyle(color: _textSecondary, fontSize: 13),
                          ),
                          if ((item.price ?? '').isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(item.price!, style: const TextStyle(color: _accent, fontWeight: FontWeight.w700)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EditPage()),
          );
          _reload();
        },
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        child: const Icon(Icons.add, size: 26),
      ),
    );
  }
}

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.item});

  final HouseViewing item;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late HouseViewing _item;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  Future<void> _reloadFromStore() async {
    final list = await HouseViewingStore.readAll();
    for (final e in list) {
      if (e.id == _item.id) {
        if (mounted) setState(() => _item = e);
        return;
      }
    }
  }

  Future<void> _removeHistoryEntry(String entryId) async {
    final all = await HouseViewingStore.readAll();
    final idx = all.indexWhere((e) => e.id == _item.id);
    if (idx < 0) return;
    final h = all[idx];
    final next = h.viewingHistory.where((e) => e.id != entryId).toList();
    ViewStatus newStatus = ViewStatus.pending;
    if (next.isNotEmpty) {
      final sorted = [...next]..sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
      newStatus = sorted.first.status;
    }
    all[idx] = h.copyWith(viewingHistory: next, status: newStatus);
    await HouseViewingStore.saveAll(all);
    if (mounted) await _reloadFromStore();
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    Widget iconCircle({
      required IconData icon,
      required Color bg,
      required Color iconColor,
      VoidCallback? onTap,
    }) {
      final child = Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Icon(icon, size: 18, color: iconColor),
      );
      if (onTap == null) return child;
      return InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: child);
    }

    Widget infoRow({
      required IconData icon,
      required Color iconColor,
      required Color iconBg,
      required String label,
      required String value,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(18)),
              alignment: Alignment.center,
              child: Icon(icon, size: 14, color: iconColor),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 80,
              child: Text(label, style: const TextStyle(color: _textMuted, fontSize: 13)),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
    }

    Widget sectionCard({required String title, required List<Widget> children}) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: _neuOuter(),
        child: Container(
          decoration: _neuInner(),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _textPrimary)),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      );
    }

    final roomType = '${item.bedrooms ?? '-'}室${item.livingRooms ?? '-'}厅${item.bathrooms ?? '-'}卫';
    final unitHint = unitPriceHintFromHouseViewing(item);
    String buildingLabel() {
      final b = item.building?.trim();
      if (b == null || b.isEmpty) return '—';
      if (b.endsWith('栋')) return b;
      return '$b栋';
    }

    final historySorted = [...item.viewingHistory]..sort((a, b) => b.viewedAt.compareTo(a.viewedAt));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _bgRoot,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                children: [
                  iconCircle(
                    icon: Icons.arrow_back_rounded,
                    bg: _bgTertiary,
                    iconColor: _textPrimary,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('房源详情', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _textPrimary)),
                  ),
                  iconCircle(
                    icon: Icons.post_add_rounded,
                    bg: _bgTertiary,
                    iconColor: _primary,
                    onTap: () async {
                      final ok = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute<bool>(builder: (_) => AddViewingHistoryPage(house: item)),
                      );
                      if (ok == true && context.mounted) await _reloadFromStore();
                    },
                  ),
                  const SizedBox(width: 4),
                  iconCircle(
                    icon: Icons.edit_rounded,
                    bg: _bgTertiary,
                    iconColor: _primary,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => EditPage(item: item)),
                      );
                      if (context.mounted) await _reloadFromStore();
                    },
                  ),
                  const SizedBox(width: 4),
                  iconCircle(
                    icon: Icons.delete_outline_rounded,
                    bg: _bgTertiary,
                    iconColor: const Color(0xFFE35D6A),
                    onTap: () async {
                      final all = await HouseViewingStore.readAll();
                      all.removeWhere((e) => e.id == item.id);
                      await HouseViewingStore.saveAll(all);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: _bgTertiary,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(color: Color(0x55D1D9E6), offset: Offset(3, 3), blurRadius: 8),
                    BoxShadow(color: Color(0xCCFFFFFF), offset: Offset(-3, -3), blurRadius: 8),
                  ],
                ),
                padding: const EdgeInsets.all(4),
                child: TabBar(
                  dividerHeight: 0,
                  tabAlignment: TabAlignment.fill,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(color: Color(0x14000000), offset: Offset(0, 2), blurRadius: 6),
                    ],
                  ),
                  indicatorPadding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                  labelColor: _primary,
                  unselectedLabelColor: _textSecondary,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  tabs: const [
                    Tab(text: '房源信息'),
                    Tab(text: '看房记录'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                    children: [
          sectionCard(
            title: '基本信息',
            children: [
              infoRow(
                icon: Icons.apartment_rounded,
                iconColor: _primary,
                iconBg: const Color(0x336C63FF),
                label: '小区',
                value: item.communityName,
              ),
              if ((item.locationText ?? '').trim().isNotEmpty)
                infoRow(
                  icon: Icons.my_location_outlined,
                  iconColor: _primary,
                  iconBg: const Color(0x336C63FF),
                  label: '位置描述',
                  value: item.locationText!.trim(),
                ),
              if ((item.address ?? '').trim().isNotEmpty)
                infoRow(
                  icon: Icons.map_outlined,
                  iconColor: const Color(0xFF00B894),
                  iconBg: const Color(0x2200B894),
                  label: '详细地址',
                  value: item.address!.trim(),
                ),
              infoRow(
                icon: Icons.domain_outlined,
                iconColor: _primary,
                iconBg: const Color(0x336C63FF),
                label: '楼栋',
                value: buildingLabel(),
              ),
              infoRow(
                icon: Icons.grid_view_outlined,
                iconColor: _primary,
                iconBg: const Color(0x336C63FF),
                label: '总单元',
                value: item.totalUnits == null ? '—' : '${item.totalUnits} 单元',
              ),
              infoRow(
                icon: Icons.door_front_door_outlined,
                iconColor: _primary,
                iconBg: const Color(0x336C63FF),
                label: '房号',
                value: (item.roomNumber ?? '').trim().isEmpty ? '—' : item.roomNumber!.trim(),
              ),
              infoRow(
                icon: Icons.stairs_outlined,
                iconColor: _primary,
                iconBg: const Color(0x336C63FF),
                label: '总楼层',
                value: item.totalFloors == null ? '—' : '${item.totalFloors} 层',
              ),
              if (item.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: item.tags
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0x1F6C63FF),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(tag, style: const TextStyle(color: _primary, fontWeight: FontWeight.w600, fontSize: 12)),
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
          sectionCard(
            title: '房型信息',
            children: [
              infoRow(
                icon: Icons.home_work_outlined,
                iconColor: _primary,
                iconBg: const Color(0x336C63FF),
                label: '户型',
                value: roomType,
              ),
              infoRow(
                icon: Icons.square_foot_outlined,
                iconColor: _primary,
                iconBg: const Color(0x336C63FF),
                label: '面积',
                value: (item.area ?? '').trim().isEmpty ? '—' : '${item.area} ㎡',
              ),
              infoRow(
                icon: Icons.sell_outlined,
                iconColor: _accent,
                iconBg: const Color(0x22FF6584),
                label: '价格',
                value: (item.price ?? '').trim().isEmpty ? '未填写' : item.price!.trim(),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  unitHint != null ? '自动计算均价：$unitHint' : '填写面积和价格后可计算均价',
                  style: TextStyle(
                    color: unitHint != null ? _primary : _textMuted,
                    fontSize: 13,
                    fontWeight: unitHint != null ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          if (item.mediaUris.isNotEmpty)
            sectionCard(
              title: '照片视频',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final uri in item.mediaUris)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => showLocalMediaPreview(context, uri),
                          borderRadius: BorderRadius.circular(12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: mediaThumb(uri, width: 92, height: 92),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          if ((item.agentName ?? '').isNotEmpty || (item.agentPhone ?? '').isNotEmpty)
            sectionCard(
              title: '联系方式',
              children: [
                if ((item.agentName ?? '').isNotEmpty)
                  infoRow(
                    icon: Icons.person_outline,
                    iconColor: _primary,
                    iconBg: const Color(0x336C63FF),
                    label: '中介',
                    value: item.agentName!,
                  ),
                if ((item.agentPhone ?? '').isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: infoRow(
                          icon: Icons.phone_outlined,
                          iconColor: const Color(0xFF00B894),
                          iconBg: const Color(0x2200B894),
                          label: '电话',
                          value: item.agentPhone!,
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () async {
                          final uri = Uri.parse('tel:${item.agentPhone}');
                          await launchUrl(uri);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        icon: const Icon(Icons.phone, size: 14),
                        label: const Text('拨打'),
                      ),
                    ],
                  ),
              ],
            ),
          sectionCard(
            title: '来源与记录',
            children: [
              if ((item.sourceUrl ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () => launchUrl(Uri.parse(item.sourceUrl!.trim())),
                    child: Row(
                      children: [
                        const Icon(Icons.link, size: 18, color: _primary),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('打开原分享链接', style: TextStyle(color: _primary, fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                        const Icon(Icons.open_in_new, size: 16, color: _primary),
                      ],
                    ),
                  ),
                ),
              infoRow(
                icon: Icons.schedule_outlined,
                iconColor: _textMuted,
                iconBg: _bgTertiary,
                label: '创建时间',
                value: DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt),
              ),
            ],
          ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    children: [
                      if (historySorted.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(8, 48, 8, 8),
                          child: Center(
                            child: Text(
                              '暂无看房记录\n点击右上角「添加」按钮记录每次看房',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _textMuted, height: 1.5),
                            ),
                          ),
                        )
                      else
                        for (final h in historySorted)
                          Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: _neuOuter(),
                            child: Container(
                              decoration: _neuInner(),
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () async {
                                          final changed = await Navigator.push<bool>(
                                            context,
                                            MaterialPageRoute<bool>(
                                              builder: (_) => ViewingHistoryDetailPage(house: item, entry: h),
                                            ),
                                          );
                                          if (changed == true && context.mounted) await _reloadFromStore();
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.only(right: 4, bottom: 4),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      DateFormat('yyyy-MM-dd HH:mm').format(h.viewedAt),
                                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _textPrimary),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: h.status.bgColor,
                                                      borderRadius: BorderRadius.circular(999),
                                                    ),
                                                    child: Text(
                                                      h.status.label,
                                                      style: TextStyle(color: h.status.color, fontWeight: FontWeight.w700, fontSize: 12),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if ((h.comment ?? '').trim().isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                Text(h.comment!.trim(), maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _textSecondary, fontSize: 14, height: 1.45)),
                                              ],
                                              if (h.voiceNotePaths.isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Icon(Icons.mic_rounded, size: 16, color: _primary.withValues(alpha: 0.9)),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      h.voiceNotePaths.length > 1 ? '语音备忘 ${h.voiceNotePaths.length} 段' : '语音备忘',
                                                      style: TextStyle(color: _primary.withValues(alpha: 0.95), fontSize: 13, fontWeight: FontWeight.w600),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                              if (h.mediaUris.isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 6,
                                                  children: [
                                                    for (final u in h.mediaUris.take(4))
                                                      GestureDetector(
                                                        onTap: () => showLocalMediaPreview(context, u),
                                                        child: ClipRRect(
                                                          borderRadius: BorderRadius.circular(8),
                                                          child: mediaThumb(u, width: 48, height: 48),
                                                        ),
                                                      ),
                                                    if (h.mediaUris.length > 4)
                                                      Text('+${h.mediaUris.length - 4}', style: const TextStyle(color: _textMuted, fontSize: 12)),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFE35D6A)),
                                    onPressed: () => _removeHistoryEntry(h.id),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

String _fmtAudioDuration(Duration d) {
  final t = d.inSeconds.clamp(0, 86400 * 365);
  final mm = t ~/ 60;
  final ss = (t % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}

/// 微信风格语音条：浅绿气泡、大播放钮、时长，整段可点。
/// 每条语音独立使用自己的 AudioPlayer，避免多条共用导致「点一条全部显示播放」。
class VoiceMemoPlaybackBar extends StatefulWidget {
  const VoiceMemoPlaybackBar({
    super.key,
    required this.path,
    this.label = '语音备忘',
  });

  final String path;
  final String label;

  @override
  State<VoiceMemoPlaybackBar> createState() => _VoiceMemoPlaybackBarState();
}

class _VoiceMemoPlaybackBarState extends State<VoiceMemoPlaybackBar> {
  late final AudioPlayer _player;
  /// 仅表示正在加载/解码音频文件（setAudioSource），不包含正在播放的时长。
  bool _loadingSource = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前平台不支持本地语音播放')),
        );
      }
      return;
    }
    final p = _player;
    if (_loadingSource) return;
    if (p.playing) {
      await p.pause();
      return;
    }
    setState(() => _loadingSource = true);
    try {
      await p.setFilePath(widget.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法加载：$e')));
      }
      return;
    } finally {
      if (mounted) setState(() => _loadingSource = false);
    }
    // 部分平台上 await play() 会直到播完才返回，导致整段误显示为「加载中」
    unawaited(_startPlayback(p));
  }

  Future<void> _startPlayback(AudioPlayer p) async {
    try {
      await p.play();
    } catch (e, st) {
      debugPrint('play: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法播放：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _toggle,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF9EEA6A), Color(0xFF95EC69)],
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x2607C160), offset: Offset(0, 3), blurRadius: 8),
            ],
          ),
          child: Row(
            children: [
              StreamBuilder<PlayerState>(
                stream: p.playerStateStream,
                initialData: p.playerState,
                builder: (context, snap) {
                  final playing = snap.data?.playing ?? false;
                  return Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: _loadingSource
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF07C160)),
                          )
                        : Icon(
                            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: const Color(0xFF07C160),
                            size: 28,
                          ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF2D3436)),
                    ),
                    const SizedBox(height: 4),
                    StreamBuilder<Duration?>(
                      stream: p.durationStream,
                      initialData: p.duration,
                      builder: (context, durSnap) {
                        final dur = durSnap.data ?? p.duration ?? Duration.zero;
                        return StreamBuilder<Duration>(
                          stream: p.positionStream,
                          initialData: p.position,
                          builder: (context, posSnap) {
                            final pos = posSnap.data ?? Duration.zero;
                            return Text(
                              dur == Duration.zero ? '点击播放' : '${_fmtAudioDuration(pos)} / ${_fmtAudioDuration(dur)}',
                              style: const TextStyle(color: Color(0xFF636E72), fontSize: 13, fontWeight: FontWeight.w600),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              const Icon(Icons.graphic_eq_rounded, color: Color(0xFF07C160), size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单条看房记录详情（含语音播放、图片/视频备注）
class ViewingHistoryDetailPage extends StatefulWidget {
  const ViewingHistoryDetailPage({super.key, required this.house, required this.entry});

  final HouseViewing house;
  final ViewingHistoryEntry entry;

  @override
  State<ViewingHistoryDetailPage> createState() => _ViewingHistoryDetailPageState();
}

class _ViewingHistoryDetailPageState extends State<ViewingHistoryDetailPage> {
  late ViewingHistoryEntry _entry;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  Future<void> _reloadEntry() async {
    final all = await HouseViewingStore.readAll();
    for (final house in all) {
      if (house.id != widget.house.id) continue;
      for (final e in house.viewingHistory) {
        if (e.id == _entry.id) {
          if (mounted) setState(() => _entry = e);
          return;
        }
      }
    }
  }

  Future<HouseViewing?> _houseFromStore() async {
    final all = await HouseViewingStore.readAll();
    for (final h in all) {
      if (h.id == widget.house.id) return h;
    }
    return null;
  }

  Future<void> _deleteEntry() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除这条看房记录？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    final all = await HouseViewingStore.readAll();
    final idx = all.indexWhere((e) => e.id == widget.house.id);
    if (idx < 0) return;
    final h = all[idx];
    final next = h.viewingHistory.where((e) => e.id != _entry.id).toList();
    ViewStatus newStatus = ViewStatus.pending;
    if (next.isNotEmpty) {
      final sorted = [...next]..sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
      newStatus = sorted.first.status;
    }
    all[idx] = h.copyWith(viewingHistory: next, status: newStatus);
    await HouseViewingStore.saveAll(all);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final h = _entry;
    return Scaffold(
      backgroundColor: _bgRoot,
      appBar: AppBar(
        title: const Text('看房记录', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑',
            onPressed: () async {
              final fresh = await _houseFromStore();
              if (fresh == null) return;
              if (!context.mounted) return;
              final ok = await Navigator.push<bool>(
                context,
                MaterialPageRoute<bool>(
                  builder: (_) => AddViewingHistoryPage(house: fresh, editing: _entry),
                ),
              );
              if (!context.mounted) return;
              if (ok == true) await _reloadEntry();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE35D6A)),
            onPressed: _deleteEntry,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            _viewingDetailSection(
              title: '基本信息',
              children: [
                Text(
                  widget.house.communityName,
                  style: const TextStyle(color: _textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Text(
                  DateFormat('yyyy-MM-dd HH:mm').format(h.viewedAt),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _textPrimary),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: h.status.bgColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    h.status.label,
                    style: TextStyle(color: h.status.color, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
            if ((h.comment ?? '').trim().isNotEmpty)
              _viewingDetailSection(
                title: '文字备注',
                children: [
                  Text(h.comment!.trim(), style: const TextStyle(color: _textPrimary, fontSize: 15, height: 1.5)),
                ],
              ),
            if (h.voiceNotePaths.isNotEmpty)
              _viewingDetailSection(
                title: '语音备忘',
                children: [
                  for (var i = 0; i < h.voiceNotePaths.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    VoiceMemoPlaybackBar(
                      path: h.voiceNotePaths[i],
                      label: h.voiceNotePaths.length > 1 ? '第 ${i + 1} 段语音' : '点击播放语音备忘',
                    ),
                  ],
                ],
              ),
            if (h.mediaUris.isNotEmpty)
              _viewingDetailSection(
                title: '图片 / 视频',
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final uri in h.mediaUris)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => showLocalMediaPreview(context, uri),
                            borderRadius: BorderRadius.circular(12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: mediaThumb(uri, width: 96, height: 96),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('点击缩略图全屏预览', style: TextStyle(color: _textMuted, fontSize: 12)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 微信风格录音波形条（装饰动画）
class _WeChatVoiceWaveBars extends StatelessWidget {
  const _WeChatVoiceWaveBars({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(5, (i) {
            final t = animation.value * 2 * math.pi + i * 0.55;
            final h = 5.0 + 24 * (0.5 + 0.5 * math.sin(t));
            return Container(
              width: 4,
              height: h,
              decoration: BoxDecoration(
                color: const Color(0xFF07C160),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

/// 独立于「编辑房源」的新增 / 编辑看房记录页
class AddViewingHistoryPage extends StatefulWidget {
  const AddViewingHistoryPage({super.key, required this.house, this.editing});

  final HouseViewing house;
  /// 非空时为编辑已有记录
  final ViewingHistoryEntry? editing;

  @override
  State<AddViewingHistoryPage> createState() => _AddViewingHistoryPageState();
}

class _AddViewingHistoryPageState extends State<AddViewingHistoryPage> with TickerProviderStateMixin {
  late DateTime _viewedAt;
  late ViewStatus _status;
  final _comment = TextEditingController();
  bool _saving = false;
  bool _hasChanges = false;

  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  final List<String> _voicePaths = [];

  final List<String> _mediaPaths = [];
  final ImagePicker _imagePicker = ImagePicker();

  late AnimationController _recordPulseController;

  Future<bool> _requestPop() async {
    if (!_hasChanges) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('有未保存的修改'),
        content: const Text('确定要离开吗？修改将丢失。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('离开')),
        ],
      ),
    );
    return leave == true;
  }

  @override
  void initState() {
    super.initState();
    _recordPulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 720));
    final e = widget.editing;
    if (e != null) {
      _viewedAt = e.viewedAt;
      _status = e.status;
      _comment.text = e.comment ?? '';
      _voicePaths.addAll(List<String>.from(e.voiceNotePaths));
      _mediaPaths.addAll(List<String>.from(e.mediaUris));
    } else {
      _viewedAt = DateTime.now();
      _status = ViewStatus.pending;
    }
    _comment.addListener(() => setState(() => _hasChanges = true));
  }

  Future<String?> _newVoiceFilePath() async {
    if (kIsWeb) return null;
    final dir = await getApplicationDocumentsDirectory();
    await voice_note_dir.ensureVoiceNotesDirectory(dir.path);
    return '${dir.path}/voice_notes/${const Uuid().v4()}.m4a';
  }

  Future<void> _toggleRecording() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网页版暂不支持录音备忘')),
        );
      }
      return;
    }
    if (_recording) {
      final path = await _recorder.stop();
      if (!mounted) return;
      _recordPulseController.stop();
      _recordPulseController.reset();
      setState(() {
        _recording = false;
        if (path != null && path.isNotEmpty) {
          _voicePaths.add(path);
          _hasChanges = true;
        }
      });
      return;
    }
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能录音')),
        );
      }
      return;
    }
    final out = await _newVoiceFilePath();
    if (out == null) return;
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: out,
      );
      if (mounted) {
        setState(() => _recording = true);
        _recordPulseController.repeat(reverse: true);
      }
    } catch (e, st) {
      debugPrint('record start: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法开始录音：$e')),
        );
      }
    }
  }

  Future<void> _clearVoice() async {
    if (_recording) {
      await _recorder.cancel();
      _recordPulseController.stop();
      _recordPulseController.reset();
      if (mounted) setState(() => _recording = false);
    }
    if (mounted) setState(() {
      _voicePaths.clear();
      _hasChanges = true;
    });
  }

  void _removeVoiceAt(int i) {
    setState(() {
      _voicePaths.removeAt(i);
      _hasChanges = true;
    });
  }

  Future<void> _pickMedia() async {
    try {
      final files = await _imagePicker.pickMultipleMedia();
      if (files.isEmpty) return;
      setState(() {
        for (final f in files) {
          final p = f.path;
          if (p.isNotEmpty) _mediaPaths.add(p);
        }
        _hasChanges = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择媒体失败：$e')));
      }
    }
  }

  void _removeMediaAt(int i) {
    setState(() {
      _mediaPaths.removeAt(i);
      _hasChanges = true;
    });
  }

  @override
  void dispose() {
    _recordPulseController.dispose();
    if (_recording) {
      unawaited(_recorder.stop());
    }
    unawaited(_recorder.dispose());
    _comment.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _viewedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(colorScheme: ColorScheme.light(primary: _primary, onPrimary: Colors.white)),
        child: child!,
      ),
    );
    if (d != null) setState(() {
      _viewedAt = d;
      _hasChanges = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final all = await HouseViewingStore.readAll();
      final idx = all.indexWhere((e) => e.id == widget.house.id);
      if (idx < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('找不到该房源，请返回后重试')),
          );
        }
        return;
      }
      final h = all[idx];
      final editId = widget.editing?.id;
      final entry = ViewingHistoryEntry(
        id: editId ?? const Uuid().v4(),
        viewedAt: _viewedAt,
        status: _status,
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
        voiceNotePaths: List<String>.from(_voicePaths),
        mediaUris: List<String>.from(_mediaPaths),
      );
      final List<ViewingHistoryEntry> nextHistory;
      if (editId == null) {
        nextHistory = [...h.viewingHistory, entry];
      } else {
        final list = List<ViewingHistoryEntry>.from(h.viewingHistory);
        final i = list.indexWhere((x) => x.id == editId);
        if (i >= 0) {
          list[i] = entry;
          nextHistory = list;
        } else {
          // 列表中未找到同 id（曾用随机 id 导致不同步），直接追加新条目，避免覆盖失败
          nextHistory = [...h.viewingHistory, entry];
        }
      }
      final sorted = [...nextHistory]..sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
      final houseStatus = sorted.isNotEmpty ? sorted.first.status : ViewStatus.pending;
      all[idx] = h.copyWith(
        viewingHistory: nextHistory,
        status: houseStatus,
      );
      await HouseViewingStore.saveAll(all);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(editId == null ? '看房记录已保存' : '修改已保存')),
      );
      _hasChanges = false;
      Navigator.pop(context, true);
    } catch (e, st) {
      debugPrint('save viewing history: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy-MM-dd').format(_viewedAt);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await _requestPop();
        if (leave && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: _bgRoot,
        appBar: AppBar(
          title: Text(
            widget.editing == null ? '新增看房记录' : '编辑看房记录',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              final leave = await _requestPop();
              if (leave && context.mounted) Navigator.pop(context);
            },
          ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _viewingDetailSection(
              title: '基本信息',
              children: [
                Text('小区：${widget.house.communityName}', style: const TextStyle(color: _textSecondary, fontSize: 14)),
                const SizedBox(height: 14),
                const Text('看房时间', style: TextStyle(color: _textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _pickDate,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: _bgTertiary,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0x99FFFFFF)),
                      ),
                      child: Text(dateStr, style: const TextStyle(fontSize: 15, color: _textPrimary)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('状态', style: TextStyle(color: _textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ViewStatus.values.map((s) {
                    final on = _status == s;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => setState(() {
                          _status = s;
                          _hasChanges = true;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: on ? s.bgColor : _bgTertiary,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: on ? Colors.transparent : const Color(0x99FFFFFF)),
                          ),
                          child: Text(
                            s.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: on ? s.color : _textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            _viewingDetailSection(
              title: '语音备忘',
              children: [
                const Text('可多次录制，每点一次停止即追加一段', style: TextStyle(color: _textMuted, fontSize: 12)),
                const SizedBox(height: 8),
                    Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _recording
                          ? const [Color(0xFFE8F8EF), Color(0xFFF4FFF8)]
                          : const [_bgTertiary, _bgTertiary],
                    ),
                    border: Border.all(color: const Color(0x99FFFFFF)),
                    boxShadow: _recording
                        ? const [
                            BoxShadow(color: Color(0x3307C160), blurRadius: 14, spreadRadius: 0),
                          ]
                        : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (_recording) ...[
                        SizedBox(
                          width: 52,
                          height: 40,
                          child: _WeChatVoiceWaveBars(animation: _recordPulseController),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _recording ? '正在录音' : '点按右侧按钮开始新的一段',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: _recording ? const Color(0xFF07C160) : _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _recording ? '点击右侧红色按钮结束并保存本段' : '参考微信语音：波形动画 + 绿色麦克风 / 红色停止',
                              style: const TextStyle(color: _textMuted, fontSize: 12, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      _recording
                          ? ScaleTransition(
                              scale: Tween<double>(begin: 0.94, end: 1.06).animate(
                                CurvedAnimation(parent: _recordPulseController, curve: Curves.easeInOut),
                              ),
                              child: Material(
                                color: const Color(0xFFFA5151),
                                elevation: 4,
                                shadowColor: const Color(0x55FA5151),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _toggleRecording,
                                  child: const SizedBox(
                                    width: 52,
                                    height: 52,
                                    child: Icon(Icons.stop_rounded, color: Colors.white, size: 26),
                                  ),
                                ),
                              ),
                            )
                          : Material(
                              color: const Color(0xFF07C160),
                              elevation: 2,
                              shadowColor: const Color(0x4407C160),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _toggleRecording,
                                child: const SizedBox(
                                  width: 52,
                                  height: 52,
                                  child: Icon(Icons.mic_rounded, color: Colors.white, size: 26),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
                if (_voicePaths.isNotEmpty || _recording) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _clearVoice,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: Text(_voicePaths.length > 1 ? '清除全部录音' : '清除录音'),
                    ),
                  ),
                ],
                if (_voicePaths.isNotEmpty) ...[
                  if (_recording) Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('正在录制新的一段…', style: TextStyle(color: _primary.withValues(alpha: 0.9), fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < _voicePaths.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: VoiceMemoPlaybackBar(
                              path: _voicePaths[i],
                              label: _voicePaths.length > 1 ? '第 ${i + 1} 段（试听）' : '本条语音备忘（可试听）',
                            ),
                          ),
                          IconButton(
                            tooltip: '删除本段',
                            onPressed: () => _removeVoiceAt(i),
                            icon: const Icon(Icons.close_rounded, size: 20, color: _textMuted),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
            _viewingDetailSection(
              title: '图片 / 视频备注',
              children: [
                Row(
                  children: [
                    const Expanded(child: SizedBox.shrink()),
                    OutlinedButton.icon(
                      onPressed: _pickMedia,
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                      label: const Text('添加'),
                    ),
                  ],
                ),
                if (_mediaPaths.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _mediaPaths.length; i++)
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => showLocalMediaPreview(context, _mediaPaths[i]),
                                borderRadius: BorderRadius.circular(12),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: mediaThumb(_mediaPaths[i], width: 72, height: 72),
                                ),
                              ),
                            ),
                            Positioned(
                              top: -6,
                              right: -6,
                              child: Material(
                                color: const Color(0xFFE35D6A),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => _removeMediaAt(i),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ],
            ),
            _viewingDetailSection(
              title: '文字备注',
              children: [
                TextField(
                  controller: _comment,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: '本次看房的感受…',
                    filled: true,
                    fillColor: _bgTertiary,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }
}

enum _PickerField { building, totalUnits, totalFloors, bedrooms, livingRooms, bathrooms }

class EditPage extends StatefulWidget {
  const EditPage({super.key, this.item});

  final HouseViewing? item;

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  final _formKey = GlobalKey<FormState>();
  final _community = TextEditingController();
  final _address = TextEditingController();
  final _building = TextEditingController();
  final _totalUnits = TextEditingController(text: '2');
  final _room = TextEditingController();
  final _totalFloors = TextEditingController();
  final _bedrooms = TextEditingController();
  final _living = TextEditingController();
  final _bath = TextEditingController();
  final _area = TextEditingController();
  final _price = TextEditingController();
  final _agent = TextEditingController();
  final _phone = TextEditingController();
  final _shareContent = TextEditingController();
  final _newTag = TextEditingController();
  final _sourceUrl = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _locationText = TextEditingController();

  ViewStatus _status = ViewStatus.pending;
  List<String> _globalTags = [];
  List<String> _selectedTags = [];
  List<String> _mediaUris = [];
  bool _saving = false;
  bool _hasChanges = false;

  static const _inputBorderSide = BorderSide(color: Color(0x99FFFFFF));

  Future<bool> _requestPop() async {
    if (!_hasChanges) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('有未保存的修改'),
        content: const Text('确定要离开吗？修改将丢失。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('离开')),
        ],
      ),
    );
    return leave == true;
  }

  InputDecoration _fieldDeco({String? label, String? hint, String? errorText}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      isDense: true,
      filled: true,
      fillColor: _bgTertiary,
      labelStyle: const TextStyle(color: _textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
      hintStyle: const TextStyle(color: _textMuted, fontSize: 15),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: _inputBorderSide),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: _inputBorderSide),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _primary, width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _errorColor),
      ),
    );
  }

  Widget _editSection({required String title, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: _neuOuter(),
      child: Container(
        decoration: _neuInner(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _textPrimary)),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(color: _textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  Widget _selectRow({required String label, required String value, required String placeholder, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(label),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _bgTertiary,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x99FFFFFF)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        value.isEmpty ? placeholder : value,
                        style: TextStyle(
                          fontSize: 15,
                          color: value.isEmpty ? _textMuted : _textPrimary,
                        ),
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_up, size: 18, color: _textMuted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _optionsFor(_PickerField f) {
    List<int> range(int a, int b) => [for (var i = a; i <= b; i++) i];
    switch (f) {
      case _PickerField.building:
      case _PickerField.totalUnits:
        return range(1, 20).map((e) => '$e').toList();
      case _PickerField.totalFloors:
        return range(1, 80).map((e) => '$e').toList();
      case _PickerField.bedrooms:
        return range(1, 6).map((e) => '$e').toList();
      case _PickerField.livingRooms:
        return range(0, 4).map((e) => '$e').toList();
      case _PickerField.bathrooms:
        return range(1, 4).map((e) => '$e').toList();
    }
  }

  String? _currentPickerValue(_PickerField f) {
    switch (f) {
      case _PickerField.building:
        return _building.text;
      case _PickerField.totalUnits:
        return _totalUnits.text;
      case _PickerField.totalFloors:
        return _totalFloors.text;
      case _PickerField.bedrooms:
        return _bedrooms.text;
      case _PickerField.livingRooms:
        return _living.text;
      case _PickerField.bathrooms:
        return _bath.text;
    }
  }

  void _setPickerValue(_PickerField f, String v) {
    switch (f) {
      case _PickerField.building:
        _building.text = v;
        break;
      case _PickerField.totalUnits:
        _totalUnits.text = v;
        break;
      case _PickerField.totalFloors:
        _totalFloors.text = v;
        break;
      case _PickerField.bedrooms:
        _bedrooms.text = v;
        break;
      case _PickerField.livingRooms:
        _living.text = v;
        break;
      case _PickerField.bathrooms:
        _bath.text = v;
        break;
    }
  }

  void _openPicker(_PickerField field, String title) {
    final options = _optionsFor(field);
    final current = _currentPickerValue(field);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.58),
            decoration: const BoxDecoration(
              color: _bgRoot,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary)),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('关闭', style: TextStyle(color: _primary, fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: options.length,
                    itemBuilder: (c, i) {
                      final opt = options[i];
                      final active = current == opt;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              setState(() {
                                _setPickerValue(field, opt);
                                _hasChanges = true;
                              });
                              Navigator.pop(ctx);
                            },
                            child: Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                color: active ? const Color(0x286C63FF) : _bgTertiary,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                opt,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: active ? _primary : _textPrimary,
                                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _unitPriceText() {
    final area = double.tryParse(_area.text.trim());
    if (area == null || area <= 0) return null;
    final raw = _price.text.replaceAll(RegExp(r'\s'), '');
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(raw);
    if (m == null) return null;
    var n = double.tryParse(m.group(1)!);
    if (n == null || n <= 0) return null;
    if (raw.contains('万')) n = n * 10000;
    final unit = n / area;
    return '${unit.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} 元/㎡';
  }

  void _applyShareParse() {
    final text = _shareContent.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先粘贴分享内容或链接')));
      return;
    }
    final link = RegExp(r'https?://[^\s]+').firstMatch(text)?.group(0);
    if (link != null) _sourceUrl.text = link;

    String? pick(RegExp re) => re.firstMatch(text)?.group(1)?.trim();

    final community = pick(RegExp(r'(?:小区|楼盘|项目|房源)\s*[:：]\s*([^\n，,。；;]{2,30})', caseSensitive: false)) ??
        pick(RegExp(r'【([^】]{2,30})】'));
    if (community != null && community.isNotEmpty) _community.text = community;

    final b = pick(RegExp(r'(\d+)\s*栋'));
    if (b != null) _building.text = b;

    final units = pick(RegExp(r'(?:总单元|共)\s*(\d+)\s*单元'));
    if (units != null) _totalUnits.text = units;

    final room = pick(RegExp(r'(\d{2,4})\s*(?:室|房号)', caseSensitive: false)) ??
        pick(RegExp(r'(?:房号)\s*[:：]\s*([A-Za-z0-9-]{2,10})', caseSensitive: false));
    if (room != null) _room.text = room;

    final floorSlash = RegExp(r'(?:楼层)?\s*(\d+)\s*/\s*(\d+)\s*层').firstMatch(text);
    if (floorSlash != null) _totalFloors.text = floorSlash.group(2)!;

    final rtm = RegExp(r'(\d)\s*室\s*(\d)\s*厅\s*(\d)\s*卫').firstMatch(text);
    if (rtm != null) {
      _bedrooms.text = rtm.group(1)!;
      _living.text = rtm.group(2)!;
      _bath.text = rtm.group(3)!;
    }

    final ar = pick(RegExp(r'(\d+(?:\.\d+)?)\s*(?:㎡|m²|平米|平方)', caseSensitive: false));
    if (ar != null) _area.text = ar;

    final pr = pick(RegExp(r'(?:总价|售价|价格|租金)\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?\s*(?:万|元/月|元))', caseSensitive: false));
    if (pr != null) _price.text = pr;

    final phone = pick(RegExp(r'(1[3-9]\d{9})'));
    if (phone != null) _phone.text = phone;

    final agent = pick(RegExp(r'(?:经纪人|联系人|置业顾问)\s*[:：]?\s*([^\s，。,；;]{2,10})', caseSensitive: false));
    if (agent != null) _agent.text = agent;

    if (RegExp(r'已看|看过').hasMatch(text)) {
      _status = ViewStatus.viewed;
    } else if (RegExp(r'感兴趣|意向').hasMatch(text)) {
      _status = ViewStatus.interested;
    } else if (RegExp(r'已定|已订|已下定').hasMatch(text)) {
      _status = ViewStatus.booked;
    } else if (RegExp(r'放弃|不考虑').hasMatch(text)) {
      _status = ViewStatus.abandoned;
    }

    final tagHits = _defaultTagList.where((t) => text.contains(t)).toList();
    if (tagHits.isNotEmpty) {
      setState(() {
        _selectedTags = {..._selectedTags, ...tagHits}.toList();
      });
    }

    setState(() => _hasChanges = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已尝试解析并填充字段')));
  }

  Future<void> _pickMedia() async {
    final picker = ImagePicker();
    final list = await picker.pickMultipleMedia();
    if (list.isEmpty) return;
    setState(() {
      _mediaUris.addAll(list.map((x) => x.path));
      _hasChanges = true;
    });
  }

  Future<void> _loadGlobalTags() async {
    final t = await GlobalTagStore.getTags();
    if (mounted) setState(() => _globalTags = t);
  }

  @override
  void initState() {
    super.initState();
    _loadGlobalTags();
    final item = widget.item;
    if (item != null) {
      _community.text = item.communityName;
      _address.text = item.address ?? '';
      _building.text = item.building ?? '';
      _totalUnits.text = item.totalUnits?.toString() ?? '2';
      _room.text = item.roomNumber ?? '';
      _totalFloors.text = item.totalFloors?.toString() ?? '';
      _bedrooms.text = item.bedrooms?.toString() ?? '';
      _living.text = item.livingRooms?.toString() ?? '';
      _bath.text = item.bathrooms?.toString() ?? '';
      _area.text = item.area ?? '';
      _price.text = item.price ?? '';
      _agent.text = item.agentName ?? '';
      _phone.text = item.agentPhone ?? '';
      _sourceUrl.text = item.sourceUrl ?? '';
      _lat.text = item.latitude?.toString() ?? '';
      _lng.text = item.longitude?.toString() ?? '';
      _locationText.text = item.locationText ?? '';
      _status = item.status;
      _selectedTags = List<String>.from(item.tags);
      _mediaUris = List<String>.from(item.mediaUris);
    }
    void markDirty() => _hasChanges = true;
    _community.addListener(markDirty);
    _address.addListener(markDirty);
    _building.addListener(markDirty);
    _totalUnits.addListener(markDirty);
    _room.addListener(markDirty);
    _totalFloors.addListener(markDirty);
    _bedrooms.addListener(markDirty);
    _living.addListener(markDirty);
    _bath.addListener(markDirty);
    _area.addListener(markDirty);
    _price.addListener(markDirty);
    _agent.addListener(markDirty);
    _phone.addListener(markDirty);
    _shareContent.addListener(markDirty);
    _newTag.addListener(markDirty);
    _sourceUrl.addListener(markDirty);
    _lat.addListener(markDirty);
    _lng.addListener(markDirty);
    _locationText.addListener(markDirty);
  }

  @override
  void dispose() {
    for (final c in [
      _community,
      _address,
      _building,
      _totalUnits,
      _room,
      _totalFloors,
      _bedrooms,
      _living,
      _bath,
      _area,
      _price,
      _agent,
      _phone,
      _shareContent,
      _newTag,
      _sourceUrl,
      _lat,
      _lng,
      _locationText,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _openMapPicker() async {
    final key = getAmapWebKey();
    if (key.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请配置高德 Key：在 assets/amap.env 填写 AMAP_KEY，或执行 flutter run --dart-define=AMAP_KEY=你的Key'),
        ),
      );
      return;
    }
    var initialLng = double.tryParse(_lng.text.trim()) ?? 121.4737;
    var initialLat = double.tryParse(_lat.text.trim()) ?? 31.2304;
    if (_lat.text.trim().isEmpty || _lng.text.trim().isEmpty) {
      final pos = await tryGetBestLocation();
      if (pos != null) {
        initialLng = pos.longitude;
        initialLat = pos.latitude;
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height * 0.92;
        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: _bgRoot,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: h,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 8, 4),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('关闭', style: TextStyle(color: _primary, fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                        const Expanded(
                          child: Text(
                            '地图选点',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _textPrimary),
                          ),
                        ),
                        const SizedBox(width: 64),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: _borderLight),
                  Expanded(
                    child: AmapPickerWebView(
                      amapKey: key,
                      initialLng: initialLng,
                      initialLat: initialLat,
                      initialAddress: _locationText.text,
                      onPicked: (lat, lng, text, communityName) {
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        setState(() {
                          _lat.text = lat.toString();
                          _lng.text = lng.toString();
                          _locationText.text = text;
                          if (communityName.trim().isNotEmpty) {
                            _community.text = communityName.trim();
                          }
                          _hasChanges = true;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final all = await HouseViewingStore.readAll();
      final parsedBed = int.tryParse(_bedrooms.text.trim());
      final parsedLiving = int.tryParse(_living.text.trim());
      final parsedBath = int.tryParse(_bath.text.trim());
      final parsedUnits = int.tryParse(_totalUnits.text.trim());
      final parsedFloors = int.tryParse(_totalFloors.text.trim());
      final lat = double.tryParse(_lat.text.trim());
      final lng = double.tryParse(_lng.text.trim());

      final common = (
        communityName: _community.text.trim(),
        status: _status,
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        building: _building.text.trim().isEmpty ? null : _building.text.trim(),
        roomNumber: _room.text.trim().isEmpty ? null : _room.text.trim(),
        totalUnits: parsedUnits,
        totalFloors: parsedFloors,
        bedrooms: parsedBed,
        livingRooms: parsedLiving,
        bathrooms: parsedBath,
        area: _area.text.trim().isEmpty ? null : _area.text.trim(),
        price: _price.text.trim().isEmpty ? null : _price.text.trim(),
        agentName: _agent.text.trim().isEmpty ? null : _agent.text.trim(),
        agentPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        sourceUrl: _sourceUrl.text.trim().isEmpty ? null : _sourceUrl.text.trim(),
        latitude: lat,
        longitude: lng,
        locationText: _locationText.text.trim().isEmpty ? null : _locationText.text.trim(),
        tags: List<String>.from(_selectedTags),
        mediaUris: List<String>.from(_mediaUris),
      );

      if (widget.item == null) {
        all.add(
          HouseViewing(
            id: const Uuid().v4(),
            communityName: common.communityName,
            status: common.status,
            createdAt: DateTime.now(),
            address: common.address,
            building: common.building,
            roomNumber: common.roomNumber,
            totalUnits: common.totalUnits,
            totalFloors: common.totalFloors,
            bedrooms: common.bedrooms,
            livingRooms: common.livingRooms,
            bathrooms: common.bathrooms,
            area: common.area,
            price: common.price,
            agentName: common.agentName,
            agentPhone: common.agentPhone,
            latitude: common.latitude,
            longitude: common.longitude,
            locationText: common.locationText,
            sourceUrl: common.sourceUrl,
            tags: common.tags,
            mediaUris: common.mediaUris,
            viewingHistory: const [],
          ),
        );
      } else {
        final idx = all.indexWhere((e) => e.id == widget.item!.id);
        if (idx >= 0) {
          final prev = all[idx];
          all[idx] = prev.copyWith(
            communityName: common.communityName,
            status: common.status,
            address: common.address,
            building: common.building,
            roomNumber: common.roomNumber,
            totalUnits: common.totalUnits,
            totalFloors: common.totalFloors,
            bedrooms: common.bedrooms,
            livingRooms: common.livingRooms,
            bathrooms: common.bathrooms,
            area: common.area,
            price: common.price,
            agentName: common.agentName,
            agentPhone: common.agentPhone,
            latitude: common.latitude,
            longitude: common.longitude,
            locationText: common.locationText,
            sourceUrl: common.sourceUrl,
            tags: common.tags,
            mediaUris: common.mediaUris,
            viewingHistory: prev.viewingHistory,
          );
        }
      }
      await HouseViewingStore.saveAll(all);
      if (mounted) {
        _hasChanges = false;
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.item != null;
    final unitHint = _unitPriceText();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await _requestPop();
        if (leave && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: _bgRoot,
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Row(
                  children: [
                    Material(
                      color: _bgTertiary,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () async {
                          final leave = await _requestPop();
                          if (leave && context.mounted) Navigator.pop(context);
                        },
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(Icons.arrow_back_rounded, size: 20, color: _textPrimary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isEditing ? '编辑记录' : '新增记录',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _textPrimary),
                      ),
                    ),
                    TextButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(isEditing ? '保存' : '创建', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              if (!isEditing)
                _editSection(
                  title: '分享内容自动解析',
                  children: [
                    const Text(
                      '粘贴房源分享链接或文本，支持自动提取小区、户型、面积、价格、联系人等信息',
                      style: TextStyle(color: _textSecondary, fontSize: 13, height: 1.45),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _shareContent,
                      maxLines: 5,
                      minLines: 5,
                      decoration: _fieldDeco(hint: '粘贴分享链接或分享文案...'),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: _primary,
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: _applyShareParse,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: Text('立即解析并填充', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_sourceUrl.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: InkWell(
                          onTap: () => launchUrl(Uri.parse(_sourceUrl.text)),
                          child: const Row(
                            children: [
                              Icon(Icons.open_in_new, size: 16, color: _primary),
                              SizedBox(width: 6),
                              Text('打开解析到的链接', style: TextStyle(color: _primary, fontWeight: FontWeight.w600, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              _editSection(
                title: '基本信息',
                children: [
                  _fieldLabel('小区名称 *'),
                  TextFormField(
                    controller: _community,
                    decoration: _fieldDeco(hint: '请输入小区名称'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? '请输入小区名称' : null,
                  ),
                  const SizedBox(height: 16),
                  _fieldLabel('地图位置'),
                  Material(
                    color: const Color(0x1F6C63FF),
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _openMapPicker,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0x386C63FF)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.location_on_outlined, size: 18, color: _primary),
                            const SizedBox(width: 8),
                            Text(
                              (_lat.text.isNotEmpty && _lng.text.isNotEmpty) ? '重新选点' : '地图选点',
                              style: const TextStyle(color: _primary, fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _fieldLabel('位置描述（选点自动填入，可改）'),
                  TextFormField(
                    controller: _locationText,
                    decoration: _fieldDeco(hint: '中文地址，与地图选点联动'),
                    maxLines: 2,
                    onChanged: (_) => setState(() {}),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _selectRow(
                          label: '楼栋',
                          value: _building.text,
                          placeholder: '请选择楼栋',
                          onTap: () => _openPicker(_PickerField.building, '楼栋'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _selectRow(
                          label: '总单元',
                          value: _totalUnits.text,
                          placeholder: '请选择总单元',
                          onTap: () => _openPicker(_PickerField.totalUnits, '总单元'),
                        ),
                      ),
                    ],
                  ),
                  _fieldLabel('房号'),
                  TextFormField(controller: _room, decoration: _fieldDeco(hint: '如：1201')),
                  _selectRow(
                    label: '总楼层',
                    value: _totalFloors.text,
                    placeholder: '请选择总楼层',
                    onTap: () => _openPicker(_PickerField.totalFloors, '总楼层'),
                  ),
                  _fieldLabel('房源标签'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _globalTags.map((tag) {
                      final on = _selectedTags.contains(tag);
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () {
                            setState(() {
                              if (on) {
                                _selectedTags.remove(tag);
                              } else {
                                _selectedTags.add(tag);
                              }
                              _hasChanges = true;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: on ? const Color(0x286C63FF) : _bgTertiary,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: on ? Colors.transparent : const Color(0x99FFFFFF)),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: on ? _primary : _textSecondary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _newTag,
                          decoration: _fieldDeco(hint: '输入新标签，如：满五唯一'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 46,
                        child: Material(
                          color: _primary,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              final raw = _newTag.text;
                              final next = await GlobalTagStore.addTag(raw);
                              final added = raw.trim();
                              _newTag.clear();
                              if (mounted) {
                                setState(() {
                                  _globalTags = next;
                                  if (added.isNotEmpty && !_selectedTags.contains(added)) {
                                    _selectedTags.add(added);
                                  }
                                  _hasChanges = true;
                                });
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 18),
                              child: Center(child: Text('添加', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              _editSection(
                title: '房型信息',
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _selectRow(
                          label: '卧室',
                          value: _bedrooms.text,
                          placeholder: '请选择室数',
                          onTap: () => _openPicker(_PickerField.bedrooms, '卧室'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _selectRow(
                          label: '客厅',
                          value: _living.text,
                          placeholder: '请选择厅数',
                          onTap: () => _openPicker(_PickerField.livingRooms, '客厅'),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _selectRow(
                          label: '卫生间',
                          value: _bath.text,
                          placeholder: '请选择卫数',
                          onTap: () => _openPicker(_PickerField.bathrooms, '卫生间'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('面积(㎡)'),
                            TextFormField(
                              controller: _area,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: _fieldDeco(),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _fieldLabel('价格'),
                  TextFormField(
                    controller: _price,
                    decoration: _fieldDeco(hint: '如：300万 或 5000元/月'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    unitHint != null ? '自动计算均价：$unitHint' : '填写面积和价格后自动计算均价',
                    style: TextStyle(
                      color: unitHint != null ? _primary : _textMuted,
                      fontSize: 13,
                      fontWeight: unitHint != null ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
              _editSection(
                title: '房源状态',
                children: [
                  const Text(
                    '用于列表筛选；每次看房的日期与备注请在详情页「看房记录」中添加',
                    style: TextStyle(color: _textMuted, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  _fieldLabel('当前状态'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ViewStatus.values.map((s) {
                      final on = _status == s;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => setState(() {
                            _status = s;
                            _hasChanges = true;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: on ? s.bgColor : _bgTertiary,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: on ? Colors.transparent : const Color(0x99FFFFFF)),
                            ),
                            child: Text(
                              s.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: on ? s.color : _textSecondary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              _editSection(
                title: '照片视频',
                children: [
                  const Text(
                    '支持相册多选图片与视频',
                    style: TextStyle(color: _textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _mediaUris.length; i++)
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: mediaThumb(_mediaUris[i]),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Material(
                                color: Colors.black54,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => setState(() {
                                    _mediaUris.removeAt(i);
                                    _hasChanges = true;
                                  }),
                                  child: const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Icon(Icons.close, size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _pickMedia,
                          child: Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: _bgTertiary,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _border, style: BorderStyle.solid),
                            ),
                            child: const Icon(Icons.add, color: _textMuted, size: 28),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              _editSection(
                title: '联系方式',
                children: [
                  _fieldLabel('中介姓名'),
                  TextFormField(controller: _agent, decoration: _fieldDeco(hint: '中介或房主姓名')),
                  _fieldLabel('联系电话'),
                  TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: _fieldDeco(hint: '联系电话')),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

/// 与 [RootPage] 中 `NavigationBar(height: 68)` 一致，用于子页底部留白，避免内容被底栏遮住。
const double _rootBottomNavBarHeight = 68;

const _statsWechatArticleUrl = 'https://mp.weixin.qq.com/s/jdAeeKh5Ict1-VFjOj8l5w';

/// 仅允许加载本篇公众号文章（同一路径，可带查询参数）；拦截页内其它主框架跳转。
bool _isAllowedStatsWechatArticleUrl(String url) {
  try {
    final u = Uri.parse(url);
    if (u.scheme != 'http' && u.scheme != 'https') return false;
    if (u.host != 'mp.weixin.qq.com') return false;
    return u.path.startsWith('/s/jdAeeKh5Ict1-VFjOj8l5w');
  } catch (_) {
    return false;
  }
}

/// 统计页 footer 打开的公众号文章（应用内 WebView）
class StatsWechatArticlePage extends StatefulWidget {
  const StatsWechatArticlePage({super.key});

  @override
  State<StatsWechatArticlePage> createState() => _StatsWechatArticlePageState();
}

class _StatsWechatArticlePageState extends State<StatsWechatArticlePage> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            if (_isAllowedStatsWechatArticleUrl(request.url)) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(_statsWechatArticleUrl));
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(_statsWechatArticleUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Scaffold(
      backgroundColor: _bgRoot,
      appBar: AppBar(
        title: const Text('关于我们', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
          Positioned(
            left: 0,
            right: 0,
            bottom: h * 0.18,
            child: Center(
              child: Material(
                color: Colors.white.withValues(alpha: 0.94),
                elevation: 1,
                shadowColor: Colors.black26,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                  side: BorderSide(color: _primary.withValues(alpha: 0.25)),
                ),
                child: InkWell(
                  onTap: _openInBrowser,
                  borderRadius: BorderRadius.circular(999),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Text(
                      '点击跳转',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _primary, letterSpacing: 0.2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HouseViewing>>(
      future: HouseViewingStore.readAll(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        final total = data.length;
        final counts = <ViewStatus, int>{
          for (final s in ViewStatus.values) s: data.where((e) => e.status == s).length,
        };
        final bottomSafe = MediaQuery.of(context).padding.bottom;
        final footerBottomPad = bottomSafe + _rootBottomNavBarHeight + 10;
        return Scaffold(
          appBar: AppBar(title: const Text('统计概览', style: TextStyle(fontWeight: FontWeight.w800))),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                  children: [
                    Text('总记录：$total', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    for (final s in ViewStatus.values)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: _neuOuter(),
                        child: Container(
                          decoration: _neuInner(),
                          child: ListTile(
                            leading: CircleAvatar(backgroundColor: s.bgColor, child: Icon(Icons.pie_chart, color: s.color, size: 18)),
                            title: Text(s.label),
                            trailing: Text('${counts[s] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text('成功率（已定/总记录）：${total == 0 ? 0 : ((counts[ViewStatus.booked]! / total) * 100).round()}%'),
                  ],
                ),
              ),
              Material(
                color: _bgRoot,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => const StatsWechatArticlePage()),
                    );
                  },
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 10, 20, footerBottomPad),
                    child: Center(
                      child: Text(
                        'by：沐乙师傅还不收工-有点草率杂货铺出品',
                        style: TextStyle(
                          color: _textSecondary,
                          fontSize: 12,
                          height: 1.4,
                          decoration: TextDecoration.underline,
                          decorationColor: _textMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MapPageData {
  _MapPageData({required this.items, this.userLatitude, this.userLongitude});

  final List<HouseViewing> items;
  final double? userLatitude;
  final double? userLongitude;
}

/// 地图标记点击后从底部展示的房源摘要（非全屏详情页）
class _MapHouseBottomSheet extends StatelessWidget {
  const _MapHouseBottomSheet({
    required this.item,
    required this.onViewFullDetail,
    required this.onEdit,
  });

  final HouseViewing item;
  final VoidCallback onViewFullDetail;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final roomType = '${item.bedrooms ?? '-'}室${item.livingRooms ?? '-'}厅${item.bathrooms ?? '-'}卫';
    final title = mapMarkerTitleLine(item);
    final sub = (item.locationText ?? item.address ?? '').trim();
    final price = (item.price ?? '').trim().isEmpty ? '未填写' : item.price!.trim();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: _bgTertiary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textPrimary, height: 1.25),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: item.status.bgColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        item.status.label,
                        style: TextStyle(color: item.status.color, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        roomType,
                        style: const TextStyle(color: _textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    sub.length > 120 ? '${sub.substring(0, 117)}…' : sub,
                    style: const TextStyle(color: _textMuted, fontSize: 13, height: 1.4),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '价格：$price',
                  style: const TextStyle(color: _textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _textSecondary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('关闭'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: onViewFullDetail,
                        style: FilledButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('完整详情'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('编辑'),
                    style: TextButton.styleFrom(
                      foregroundColor: _primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late Future<_MapPageData> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  /// 切换回地图 Tab 或本地数据变更后刷新 WebView 上的标记数据
  void refreshMapData() {
    setState(() {
      _loadFuture = _load();
    });
  }

  /// 首屏仅用缓存定位，避免长时间阻塞在冷启动 GPS。
  Future<_MapPageData> _load() async {
    final items = await HouseViewingStore.readAll();
    final pos = await tryGetLastKnownLocation();
    return _MapPageData(
      items: items,
      userLatitude: pos?.latitude,
      userLongitude: pos?.longitude,
    );
  }

  @override
  void dispose() {
    _showMarkerCard.dispose();
    super.dispose();
  }

  bool _mapTilesReady = false;
  bool _locating = false;
  final ValueNotifier<bool> _showMarkerCard = ValueNotifier<bool>(true);
  WebViewController? _mapWebController;

  Future<void> _moveMapToMyLocation() async {
    if (_mapWebController == null || !_mapTilesReady) return;
    setState(() => _locating = true);
    final pos = await tryGetBestLocation();
    if (!mounted) return;
    setState(() => _locating = false);
    if (pos == null) return;
    final lng = pos.longitude;
    final lat = pos.latitude;
    try {
      await _mapWebController!.runJavaScript(
        'try{if(window.moveMapTo)window.moveMapTo($lng,$lat,16);}catch(e){}',
      );
    } catch (_) {}
  }

  /// 与地图内嵌 JS 同步：关闭时仅隐藏标记旁 HTML 卡片；点击标点仍由 JS 通知 Flutter 打开底部抽屉。
  Future<void> _syncMapCardModeToWebView() async {
    if (_mapWebController == null) return;
    final on = _showMarkerCard.value;
    try {
      await _mapWebController!.runJavaScript(
        'try{if(typeof window.setMapCardMode==="function")window.setMapCardMode($on);}catch(e){}',
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: _bgRoot,
      body: FutureBuilder<_MapPageData>(
          future: _loadFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final key = getAmapWebKey();
            final bundle = snapshot.data!;
            final all = bundle.items;
            final withCoord = all.where((e) => e.latitude != null && e.longitude != null).toList();
            String markerSubtitle(HouseViewing e) {
              final t = (e.locationText ?? e.address ?? '').trim();
              if (t.length <= 40) return t;
              return '${t.substring(0, 37)}…';
            }
            final payload = withCoord
                .map(
                  (e) => <String, dynamic>{
                    'id': e.id,
                    'name': e.communityName,
                    'titleLine': mapMarkerTitleLine(e),
                    'price': (e.price ?? '').trim().isEmpty ? '--' : e.price!.trim(),
                    'lat': e.latitude,
                    'lng': e.longitude,
                    'roomSummary': '${e.bedrooms ?? '-'}室${e.livingRooms ?? '-'}厅${e.bathrooms ?? '-'}卫',
                    'area': (e.area ?? '').trim(),
                    'statusLabel': e.status.label,
                    'subtitle': markerSubtitle(e),
                  },
                )
                .toList();

            const fallbackLng = 121.4737;
            const fallbackLat = 31.2304;
            final centerLng = bundle.userLongitude ?? fallbackLng;
            final centerLat = bundle.userLatitude ?? fallbackLat;

            Widget mapLayer;
            if (key.isEmpty) {
              mapLayer = Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (withCoord.isEmpty)
                        const Text(
                          '暂无带经纬度的房源，请先在「编辑记录」里使用地图选点',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _textMuted, height: 1.4),
                        )
                      else ...[
                        const Text(
                          '未配置 AMAP_KEY，地图暂不可用',
                          style: TextStyle(color: Color(0xFFFDCB6E), fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '请在 assets/amap.env 中填写 AMAP_KEY（与 RN 的 EXPO_PUBLIC_AMAP_KEY 相同）',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _textMuted, height: 1.4, fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            } else {
              mapLayer = AmapHouseMapWebView(
                amapKey: key,
                markerPayload: payload,
                centerLongitude: centerLng,
                centerLatitude: centerLat,
                onMapLoadStarted: () {
                  if (mounted) setState(() => _mapTilesReady = false);
                },
                onMapJsReady: () {
                  if (!mounted) return;
                  setState(() => _mapTilesReady = true);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    unawaited(_syncMapCardModeToWebView());
                  });
                },
                onWebViewControllerCreated: (c) => _mapWebController = c,
                onOpenDetail: (id) async {
                  final list = await HouseViewingStore.readAll();
                  HouseViewing? found;
                  for (final e in list) {
                    if (e.id == id) {
                      found = e;
                      break;
                    }
                  }
                  if (found == null || !context.mounted) return;
                  final house = found;
                  await showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: Colors.transparent,
                    builder: (sheetCtx) => _MapHouseBottomSheet(
                      item: house,
                      onViewFullDetail: () {
                        Navigator.pop(sheetCtx);
                        Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(builder: (_) => DetailPage(item: house)),
                        );
                      },
                      onEdit: () async {
                        Navigator.pop(sheetCtx);
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(builder: (_) => EditPage(item: house)),
                        );
                        if (mounted) refreshMapData();
                      },
                    ),
                  );
                },
              );
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(child: mapLayer),
                if (key.isNotEmpty && !_mapTilesReady)
                  Positioned.fill(
                    child: ColoredBox(
                      color: _bgRoot.withValues(alpha: 0.85),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(strokeWidth: 2.2),
                            SizedBox(height: 12),
                            Text('地图加载中…', style: TextStyle(color: _textSecondary, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (key.isNotEmpty)
                  Positioned(
                    top: 8,
                    right: 12,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.94),
                      elevation: 1,
                      shadowColor: const Color(0x33000000),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          _showMarkerCard.value = !_showMarkerCard.value;
                          setState(() {});
                          unawaited(_syncMapCardModeToWebView());
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ValueListenableBuilder<bool>(
                                valueListenable: _showMarkerCard,
                                builder: (_, showCard, __) => Icon(
                                  showCard ? Icons.credit_card : Icons.credit_card_off_outlined,
                                  size: 20,
                                  color: showCard ? _primary : _textMuted,
                                ),
                              ),
                              const SizedBox(width: 6),
                              ValueListenableBuilder<bool>(
                                valueListenable: _showMarkerCard,
                                builder: (_, showCard, __) => Text(
                                  showCard ? '卡片' : '无卡片',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: showCard ? _primary : _textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (key.isNotEmpty)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Material(
                      elevation: 3,
                      shadowColor: const Color(0x33000000),
                      shape: const CircleBorder(),
                      color: Colors.white,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _locating ? null : _moveMapToMyLocation,
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: _locating
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(
                                  Icons.my_location,
                                  color: _mapTilesReady ? _primary : _textMuted,
                                  size: 24,
                                ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
    );
  }
}
