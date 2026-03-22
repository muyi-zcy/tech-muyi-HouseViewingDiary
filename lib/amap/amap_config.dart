import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 与 RN `EXPO_PUBLIC_AMAP_KEY` 同源。
/// 优先级：`--dart-define=AMAP_KEY=xxx` > `assets/amap.env`
String getAmapWebKey() {
  const fromDefine = String.fromEnvironment('AMAP_KEY', defaultValue: '');
  if (fromDefine.isNotEmpty) return fromDefine;
  final a = dotenv.env['AMAP_KEY']?.trim() ?? '';
  if (a.isNotEmpty) return a;
  final b = dotenv.env['EXPO_PUBLIC_AMAP_KEY']?.trim() ?? '';
  if (b.isNotEmpty) return b;
  return '';
}

/// Web 端「安全密钥」对应 JS：`window._AMapSecurityConfig.securityJsCode`，须先于 maps 脚本注入。
/// 优先级：`--dart-define=AMAP_SECURITY_JSCODE=xxx` > `assets/amap.env`
String getAmapSecurityJsCode() {
  const fromDefine = String.fromEnvironment('AMAP_SECURITY_JSCODE', defaultValue: '');
  if (fromDefine.isNotEmpty) return fromDefine;
  final a = dotenv.env['AMAP_SECURITY_JSCODE']?.trim() ?? '';
  if (a.isNotEmpty) return a;
  final b = dotenv.env['EXPO_PUBLIC_AMAP_SECURITY_JSCODE']?.trim() ?? '';
  if (b.isNotEmpty) return b;
  return '';
}
