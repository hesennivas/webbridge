import Foundation

/// detects the hybrid framework behind a page via a one-shot JS probe, and maps it to a
/// short "how to enable inspection" tip surfaced on the target badge.
enum FrameworkDetection {

    /// evaluated once per console connection; returns a framework name or "".
    static let probe = """
    (() => {
      if (window.ReactNativeWebView) return 'React Native';
      if (window.Capacitor) return 'Capacitor';
      if (window.cordova || window.Ionic || document.querySelector('ion-app')) return 'Ionic/Cordova';
      if (window._flutter || window.flutterCanvasKit) return 'Flutter';
      if (window.__REACT_DEVTOOLS_GLOBAL_HOOK__ && window.__REACT_DEVTOOLS_GLOBAL_HOOK__.renderers && window.__REACT_DEVTOOLS_GLOBAL_HOOK__.renderers.size) return 'React';
      if (window.Vue || document.querySelector('[data-v-app]')) return 'Vue';
      return '';
    })()
    """

    static func guide(_ framework: String) -> String {
        switch framework {
        case "React Native":
            return "Android: set the WebView's webviewDebuggingEnabled (RN 0.71+) or call setWebContentsDebuggingEnabled(true). iOS: set WKWebView.isInspectable = true (iOS 16.4+)."
        case "Capacitor":
            return "Android debug builds expose WebViews automatically. iOS needs isInspectable = true on the bridge WebView (iOS 16.4+)."
        case "Ionic/Cordova":
            return "Android debug builds are inspectable automatically. iOS needs Web Inspector enabled and isInspectable = true on the WebView."
        case "Flutter":
            return "Flutter web/InAppWebView: enable debugging on the platform WebView; iOS requires isInspectable = true."
        default:
            return "Debug builds expose a DevTools socket on Android. iOS WebViews need isInspectable = true (iOS 16.4+)."
        }
    }
}
