import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:webview_flutter_web/webview_flutter_web.dart';

/// Web 端必须手动注册，否则 [WebViewPlatform.instance] 为 null。
void registerWebViewForWeb() {
  WebViewPlatform.instance = WebWebViewPlatform();
}
