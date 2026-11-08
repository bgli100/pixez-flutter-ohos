// 分叉：OHOS 继续使用 webview_flutter 的 OHOS 移植版（gitcode CPF-Flutter），
// 不跟上游 0.9.114 的 webview_all 迁移（webview_all 无 OHOS 实现）。
// 本文件保留上游 0.9.114 对初始化时序 / 释放时机的修复，只把 webview_all 的 API 换回 webview_flutter。
import 'package:webview_flutter/webview_flutter.dart';

export 'package:webview_flutter/webview_flutter.dart';

// 初始化可能在上层页面已经关闭后才完成（桌面端尤其如此），每步前确认页面仍活跃。
Future<void> initializeWebViewController(
  WebViewController controller, {
  required bool Function() isActive,
  NavigationDelegate? navigationDelegate,
  String? userAgent,
  required Future<void> Function() load,
}) async {
  try {
    if (!isActive()) return;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    if (!isActive()) return;
    if (navigationDelegate != null) {
      await controller.setNavigationDelegate(navigationDelegate);
    }
    if (!isActive()) return;
    if (userAgent != null) await controller.setUserAgent(userAgent);
    if (!isActive()) return;
    await load();
  } catch (_) {
    // 页面仍在时错误应暴露出来；页面已关闭则其后续工作可安全丢弃。
    if (isActive()) rethrow;
  }
}

// webview_flutter 的移动端（含 OHOS）控制器随 WebViewWidget 释放，无需手动销毁原生句柄。
void disposeWebViewController(WebViewController? controller) {}
