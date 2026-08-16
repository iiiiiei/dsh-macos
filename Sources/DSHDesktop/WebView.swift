import SwiftUI
import WebKit

/// 内嵌 DSH Web GUI 的 WKWebView 封装
struct HarnessWebView: NSViewRepresentable {
    let url: URL
    var onSessionViewed: ((String) -> Void)?
    var onLoadState: (LoadState) -> Void = { _ in }

    enum LoadState {
        case loading
        case loaded(title: String)
        case failed
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "DSHDesktop/1.0"
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // 注入 fetch 钩子：GUI 每次打开/切换会话都会调用 session.history（或发送
        // session.prompt），拦截后把 sessionId 上报给应用，使 token 统计跟随
        // 用户当前打开的对话窗口。
        let hook = """
        (function () {
          if (window.__dshSessionHook) return;
          window.__dshSessionHook = true;
          const orig = window.fetch;
          window.fetch = function () {
            try {
              // DSH 浏览器客户端 doFetch 传入的是 URL 对象（new URL(path, base)），
              // 取 href 而不是 .url
              const req = arguments[0];
              let url = '';
              if (typeof req === 'string') url = req;
              else if (req && typeof req.href === 'string') url = req.href;
              else if (req && typeof req.url === 'string') url = req.url;
              // 任何带 sessionId 的会话方法都可能暴露“当前打开的会话”
              if (url.indexOf('/api/session.') !== -1) {
                const body = arguments[1] && typeof arguments[1].body === 'string' ? JSON.parse(arguments[1].body) : null;
                if (body && body.payload && body.payload.sessionId) {
                  window.webkit.messageHandlers.dshSession.postMessage({
                    method: body.method,
                    sessionId: body.payload.sessionId
                  });
                }
              }
            } catch (e) {}
            return orig.apply(this, arguments);
          };
        })();
        """
        let userScript = WKUserScript(source: hook, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(context.coordinator, name: "dshSession")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        context.coordinator.onSessionViewed = onSessionViewed
        context.coordinator.observeReload()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // 只在首次加载时由我们发起；此后 SPA 的路由变化（pushState 等）
        // 会改变 webView.url，不能再按地址差异重载根页面，否则会打断应用。
        // 手动刷新走菜单栏“刷新页面”（reload）。
        guard !context.coordinator.hasLoadedOnce else { return }
        guard !context.coordinator.isLoading else { return }
        if webView.url?.absoluteString != url.absoluteString {
            // 同步置位 isLoading，避免 didStartProvisional 异步到达前
            // 被另一次 updateNSView 重复发起加载
            context.coordinator.isLoading = true
            Log.info("webview: load \(url.absoluteString)")
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: HarnessWebView
        weak var webView: WKWebView?
        private var reloadObserver: NSObjectProtocol?
        var isLoading = false
        private(set) var hasLoadedOnce = false

        /// 上报 GUI 当前打开的会话（来自 fetch 钩子）
        var onSessionViewed: ((String) -> Void)?

        init(_ parent: HarnessWebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "dshSession",
                  let body = message.body as? [String: Any],
                  let sessionId = body["sessionId"] as? String else { return }
            Log.info("webview: GUI 打开会话 \(sessionId)")
            onSessionViewed?(sessionId)
        }

        deinit {
            if let reloadObserver {
                NotificationCenter.default.removeObserver(reloadObserver)
            }
        }

        /// 菜单栏“刷新页面”支持
        func observeReload() {
            reloadObserver = NotificationCenter.default.addObserver(
                forName: .dshReloadRequested, object: nil, queue: .main
            ) { [weak self] _ in
                self?.webView?.reload()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Log.info("webview: didFinish title=\(webView.title ?? "-")")
            // 验证会话钩子注入（调试用）
            webView.evaluateJavaScript("window.__dshSessionHook === true") { result, _ in
                Log.info("webview: session hook 注入 = \(result ?? "?")")
            }
            isLoading = false
            hasLoadedOnce = true
            parent.onLoadState(.loaded(title: webView.title ?? "DeepSeek Harness"))
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }

        // MARK: - 下载处理（WKWebView 不保存 <a download>，这里拦截导出请求由原生下载）

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               url.path.contains("/api/session.export") {
                decisionHandler(.cancel)
                Task {
                    await Self.download(url: url)
                }
                return
            }
            decisionHandler(.allow)
        }

        /// 原生下载 session 导出 ZIP 到 ~/Downloads 并提示
        @MainActor
        static func download(url: URL) async {
            Log.info("download: 开始下载 \(url.absoluteString)")
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    Log.info("download: HTTP 非 200")
                    return
                }
                // 文件名：session-log-<id>.zip
                let sessionId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "sessionId" })?.value ?? "session"
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
                let file = downloads.appendingPathComponent("session-log-\(sessionId).zip")
                try data.write(to: file)
                Log.info("download: 已保存 \(file.path)")
                // 通知 + 在 Finder 中显示
                let script = "display notification \"已保存 \(file.lastPathComponent)\" with title \"DSH Desktop 会话导出\""
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                try? process.run()
                NSWorkspace.shared.activateFileViewerSelecting([file])
            } catch {
                Log.info("download: 失败 \(error.localizedDescription)")
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Log.info("webview: didFailProvisional \(error.localizedDescription)")
            isLoading = false
            parent.onLoadState(.failed)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Log.info("webview: didFail \(error.localizedDescription)")
            isLoading = false
            parent.onLoadState(.failed)
        }

        /// 新窗口请求（target=_blank 等）直接在当前视图打开，避免弹窗
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        /// 麦克风 / 摄像头权限（DSH 可能用于语音输入等）
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
    }
}
