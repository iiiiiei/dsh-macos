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

        // 中文通俗说明 Overlay（Appearance 增强，Official 默认零覆盖；
        // 开关关闭时 setEnabled(false) 还原官方原文，不残留）
        if let overlayPath = Bundle.main.path(forResource: "zh-simplified", ofType: "js", inDirectory: "overlays"),
           let overlay = try? String(contentsOfFile: overlayPath, encoding: .utf8) {
            let zhScript = WKUserScript(source: overlay, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            config.userContentController.addUserScript(zhScript)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        // 沉浸式：页面背景透明（配合 fullSizeContentView 顶到顶；WKWebView 的
        // isOpaque 只读，透明由 underPageBackgroundColor 提供）
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        context.coordinator.onSessionViewed = onSessionViewed
        context.coordinator.observeReload()
        context.coordinator.observeEnhancements()
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
            // 运行时断言：WebView 是否覆盖到窗口顶边（顶到顶的最终判定）
            DispatchQueue.main.async {
                Log.info("webview: frame=\(Int(webView.frame.minY)),\(Int(webView.frame.height)) edgeTop=\(webView.frame.minY <= 1)")
            }
            syncEnhancements(webView)
            if CommandLine.arguments.contains("--probe-sidebar") {
                // 等 SPA 渲染完成后再探测
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    self.probeSidebar(webView)
                }
            }
            isLoading = false
            hasLoadedOnce = true
            parent.onLoadState(.loaded(title: webView.title ?? "DeepSeek Harness"))
        }

        // MARK: - Appearance 增强同步（zh Overlay 开关 + 安全区变量）

        private func syncEnhancements(_ webView: WKWebView) {
            // zh Overlay 开关（关 = 还原官方原文）
            let zh = UserDefaults.standard.object(forKey: "zhOverlay") as? Bool ?? true
            webView.evaluateJavaScript("window.__dshZhOverlay && window.__dshZhOverlay.setEnabled(\(zh))") { _, error in
                if let error { Log.info("webview: zh overlay 开关同步失败 \(error.localizedDescription)") }
            }
            // 安全区：用 standardWindowButton 读取 traffic light 实际 frame，动态注入 CSS 变量
            // （禁止散落硬编码魔法数；Official 外观不消费该变量，仅供未来皮肤 Overlay 使用）
            if let metrics = trafficLightMetrics(for: webView) {
                let script = """
                document.documentElement.style.setProperty('--dsh-traffic-left', '\(metrics.left)px');
                document.documentElement.style.setProperty('--dsh-traffic-width', '\(metrics.width)px');
                document.documentElement.style.setProperty('--dsh-traffic-inset', '\(metrics.rowHeight)px');
                """
                webView.evaluateJavaScript(script) { _, _ in }
            }
            // 方案1 布局 Overlay（幂等注入：固定 style id）
            if let layoutPath = Bundle.main.path(forResource: "desktop-layout", ofType: "js", inDirectory: "overlays"),
               let layout = try? String(contentsOfFile: layoutPath, encoding: .utf8) {
                webView.evaluateJavaScript(layout) { _, error in
                    if let error { Log.info("webview: desktop-layout 注入失败 \(error.localizedDescription)") }
                }
            }
        }

        /// 读取红绿灯实际 frame（内容坐标），动态计算左缘、占用宽度与行高
        private func trafficLightMetrics(for webView: WKWebView) -> (left: CGFloat, width: CGFloat, rowHeight: CGFloat)? {
            guard let window = webView.window,
                  let contentView = window.contentView,
                  let close = window.standardWindowButton(.closeButton),
                  let zoom = window.standardWindowButton(.zoomButton) else { return nil }
            // 原始坐标自查：按钮 frame（相对 superview）与 superview frame、contentView bounds
            if let sv = close.superview {
                Log.info("traffic raw: close=\(close.frame) sv=\(sv.frame) svClass=\(type(of: sv)) contentBounds=\(contentView.bounds)")
            }
            let cf = close.convert(close.bounds, to: contentView)
            let zf = zoom.convert(zoom.bounds, to: contentView)
            let left = cf.minX   // x 坐标不受 flipped 影响
            let width = max(zf.maxX, cf.maxX) - left + 8
            // 行高：window 高度与内容布局区（contentLayoutRect，10.10+）的差值，
            // fullSize 下即红绿灯悬浮行高度（系统 API 动态计算，不依赖坐标系换算）
            let rowHeight = max(DesktopLayout.trafficLightRowHeight,
                                window.frame.height - window.contentLayoutRect.height)
            return (left, width, rowHeight)
        }

        /// 设置变化时联动（UserDefaults 通知）
        func observeEnhancements() {
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let webView = self?.webView, webView.url != nil else { return }
                self?.syncEnhancements(webView)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }

        /// 探测折叠侧栏容器（--probe-sidebar 调试模式，输出候选选择器）
        private func probeSidebar(_ webView: WKWebView) {
            let js = """
            (function () {
              const out = [];
              document.querySelectorAll('*').forEach(function (el) {
                const r = el.getBoundingClientRect();
                if (r.width > 10 && r.height > 10 && r.left < 160 && r.width < 400) {
                  out.push({ tag: el.tagName, cls: String(el.className).slice(0, 80),
                             w: Math.round(r.width), h: Math.round(r.height), t: Math.round(r.top),
                             role: el.getAttribute('role'), aria: el.getAttribute('aria-label') });
                }
              });
              return JSON.stringify(out.slice(0, 12));
            })();
            """
            webView.evaluateJavaScript(js) { result, _ in
                Log.info("sidebar probe: \(result ?? "?")")
            }
            // 黄灯（miniaturize）按钮 frame（图标对齐锚点）
            if let window = webView.window, let mini = window.standardWindowButton(.miniaturizeButton) {
                Log.info("traffic mini: frame=\(mini.frame)")
            }
            // 展开态：主内容容器 + 会话选中项（aria-selected / active / selected）
            let expanded = """
            (function () {
              var out = {};
              var all = document.querySelectorAll('div');
              var main = null;
              for (var i = 0; i < all.length; i++) {
                var r = all[i].getBoundingClientRect();
                if (r.width > window.innerWidth * 0.5 && r.left > 200 && r.top >= 0 && r.top < 60 && r.height > 200) {
                  if (!main || r.width < main.r.width) { main = { el: all[i], r: r }; }
                }
              }
              if (main) out.main = { cls: String(main.el.className).slice(0, 80), w: Math.round(main.r.width), t: Math.round(main.r.top), padTop: getComputedStyle(main.el).paddingTop };
              var items = document.querySelectorAll('[aria-selected="true"], [class*="active"], [class*="selected"]');
              var active = null;
              for (var j = 0; j < items.length; j++) {
                var rr = items[j].getBoundingClientRect();
                if (rr.width > 50 && rr.height > 20 && rr.left < 300) {
                  var cs = getComputedStyle(items[j]);
                  active = { cls: String(items[j].className).slice(0, 90), w: Math.round(rr.width), l: Math.round(rr.left), r: Math.round(rr.right), t: Math.round(rr.top), pos: cs.position, csW: cs.width };
                  break;
                }
              }
              if (active) out.active = active;
              // 顶栏最高元素（session log 按钮等）注入 overlay 后的实际 top
              var btns = document.querySelectorAll('button');
              var tops = [];
              for (var b = 0; b < btns.length; b++) {
                var br = btns[b].getBoundingClientRect();
                if (br.top >= 0 && br.top < 120 && br.left > 200) {
                  tops.push({ cls: String(btns[b].className).slice(0, 50), t: Math.round(br.top), aria: (btns[b].getAttribute('aria-label') || '').slice(0, 30) });
                }
              }
              if (tops.length) out.topButtons = tops.slice(0, 6);
              // 选中框/悬停框 computedStyle（宽度机制）
              var rows = document.querySelectorAll('.YDXeBa_sessionRow');
              var rowInfo = [];
              for (var r2 = 0; r2 < Math.min(rows.length, 3); r2++) {
                var cs2 = getComputedStyle(rows[r2]);
                var rr2 = rows[r2].getBoundingClientRect();
                rowInfo.push({ cls: String(rows[r2].className).slice(0, 80), w: Math.round(rr2.width), l: Math.round(rr2.left), r: Math.round(rr2.right), ml: cs2.marginLeft, mr: cs2.marginRight, pl: cs2.paddingLeft, pr: cs2.paddingRight, box: cs2.boxSizing });
              }
              if (rowInfo.length) out.rows = rowInfo;
              // 选中框父级与 logoRow 几何（宽度差异根因）
              var row0 = rows[0];
              if (row0 && row0.parentElement) {
                var pr = row0.parentElement.getBoundingClientRect();
                out.rowParent = { cls: String(row0.parentElement.className).slice(0, 60), l: Math.round(pr.left), r: Math.round(pr.right), w: Math.round(pr.width) };
              }
              var logoRow = document.querySelector('.hHd-Xa_logoRow');
              if (logoRow) {
                var lr2 = logoRow.getBoundingClientRect();
                out.logoRow = { l: Math.round(lr2.left), r: Math.round(lr2.right), w: Math.round(lr2.width) };
              }
              return JSON.stringify(out);
            })();
            """
            webView.evaluateJavaScript(expanded) { result, _ in
                Log.info("layout probe: \(result ?? "?")")
            }
            // 点击折叠
            let collapse = """
            (function () {
              var btns = document.querySelectorAll('button');
              var hit = null;
              for (var i = 0; i < btns.length; i++) {
                var a = btns[i].getAttribute('aria-label') || '';
                var t = (btns[i].textContent || '').trim();
                if (/折叠|收起|collapse|sidebar/i.test(a + t)) { hit = btns[i]; break; }
              }
              if (!hit) return 'NO_COLLAPSE_BUTTON';
              hit.click();
              return 'clicked: ' + (hit.getAttribute('aria-label') || hit.textContent.trim());
            })();
            """
            webView.evaluateJavaScript(collapse) { result, _ in
                Log.info("collapse probe: \(result ?? "?")")
            }
            // 展开态 logo 行避让实测
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let logo = """
                (function () {
                  var el = document.querySelector('.hHd-Xa_logoRow');
                  if (!el) return 'NO_LOGO_ROW';
                  var cs = getComputedStyle(el);
                  var root = getComputedStyle(document.documentElement);
                  return 'marginTop=' + cs.marginTop + ' inset=' + root.getPropertyValue('--dsh-traffic-inset').trim() + ' tl=' + root.getPropertyValue('--dsh-traffic-left').trim() + ' tw=' + root.getPropertyValue('--dsh-traffic-width').trim();
                })();
                """
                webView.evaluateJavaScript(logo) { result, _ in
                    Log.info("logo probe: \(result ?? "?")")
                }
            }
            // 折叠态：侧栏宽度 + 底部图标几何
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let measure = """
                (function () {
                  var out = [];
                  var cols = document.querySelectorAll('div');
                  for (var i = 0; i < cols.length; i++) {
                    var c = cols[i].className;
                    var r = cols[i].getBoundingClientRect();
                    if (typeof c === 'string' && /sidebarCol|rail/i.test(c) && r.width > 0) {
                      out.push({ cls: c.slice(0, 80), w: Math.round(r.width), l: Math.round(r.left), r: Math.round(r.right), t: Math.round(r.top) });
                    }
                  }
                  var rail = document.querySelector('.hHd-Xa_railIn') || document.querySelector('[class*="railIn"]');
                  if (rail) {
                    var rcs = getComputedStyle(rail);
                    out.push({ railStyle: { ml: rcs.marginLeft, mr: rcs.marginRight, pl: rcs.paddingLeft, pr: rcs.paddingRight, w: rcs.width, box: rcs.boxSizing } });
                  }
                  if (rail && rail.children.length) {
                    var last = rail.children[rail.children.length - 1];
                    var lr = last.getBoundingClientRect();
                    out.push({ bottom: { cls: String(last.className).slice(0, 70), w: Math.round(lr.width), l: Math.round(lr.left), r: Math.round(lr.right), t: Math.round(lr.top), b: Math.round(lr.bottom), h: Math.round(lr.height) } });
                    // footArea 内部结构（图标定位方式）
                    var kids = last.children;
                    for (var k = 0; k < kids.length; k++) {
                      var kr = kids[k].getBoundingClientRect();
                      out.push({ footChild: { cls: String(kids[k].className).slice(0, 60), w: Math.round(kr.width), h: Math.round(kr.height), t: Math.round(kr.top), b: Math.round(kr.bottom), l: Math.round(kr.left) } });
                      // settingsArea 内图标几何
                      if (/settings/i.test(String(kids[k].className))) {
                        var inner = kids[k].querySelector('svg, button, [class*="icon"]');
                        if (inner) {
                          var ir = inner.getBoundingClientRect();
                          out.push({ settingsIcon: { cls: String(inner.className).slice(0, 50), t: Math.round(ir.top), b: Math.round(ir.bottom), h: Math.round(ir.height), areaH: Math.round(kr.height) } });
                        }
                      }
                    }
                  }
                  // 折叠态顶部 0-40px 的可点击元素（拖拽带避让判断）
                  var topEls = document.querySelectorAll('button, a, [role="button"]');
                  var tops = [];
                  for (var m = 0; m < topEls.length; m++) {
                    var tr = topEls[m].getBoundingClientRect();
                    if (tr.top < 40 && tr.top >= 0 && tr.left < 200) {
                      tops.push({ cls: String(topEls[m].className).slice(0, 60), t: Math.round(tr.top), b: Math.round(tr.bottom), w: Math.round(tr.width), aria: topEls[m].getAttribute('aria-label') || '' });
                    }
                  }
                  if (tops.length) out.push({ topButtons: tops });
                  return JSON.stringify(out);
                })();
                """
                webView.evaluateJavaScript(measure) { result, _ in
                    Log.info("collapsed probe: \(result ?? "?")")
                }
            }
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
