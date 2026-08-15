import Foundation

/// 自测模式：`DSHDesktop --selftest`
/// 等待服务器就绪 + 页面加载完成，打印 JSON 结果后退出（0 = 通过）。
@MainActor
enum SelfTest {
    static func run(appState: AppState, server: ServerManager) async {
        let start = Date()
        Log.info("selftest start, url=\(appState.url.absoluteString), status=\(server.status.label)")

        // 等待服务器运行
        while server.status != .running && Date().timeIntervalSince(start) < 30 {
            try? await Task.sleep(for: .seconds(1))
        }
        Log.info("selftest after-wait status=\(server.status.label), pageLoaded=\(appState.pageLoaded)")

        // 等待页面加载
        while !appState.pageLoaded && Date().timeIntervalSince(start) < 45 {
            try? await Task.sleep(for: .seconds(1))
        }
        Log.info("selftest after-page status=\(server.status.label), pageLoaded=\(appState.pageLoaded), title=\(appState.pageTitle)")

        let result: [String: Any] = [
            "selftest": "ok",
            "status": server.status.label,
            "pageLoaded": appState.pageLoaded,
            "pageTitle": appState.pageTitle,
            "url": appState.url.absoluteString,
            "elapsedMs": Int(Date().timeIntervalSince(start) * 1000),
        ]

        // 判定必须先于 stopAndWait（stopAndWait 会把 status 置为 .stopped）
        let ok = appState.pageLoaded && server.status == .running
        Log.info("selftest result=\(ok ? "PASS" : "FAIL")")
        writeResult(result, ok: ok)

        // 自测启动的服务器要带走，避免遗留孤儿进程
        if server.startedByUs {
            server.stopAndWait()
        }

        exit(ok ? 0 : 1)
    }

    /// 结果写入文件（环境变量 DSH_SELFTEST_OUTPUT=<path>）。
    /// 注意：结果路径不能作为第二个命令行参数传递——两个连续的 `--flag`
    /// 会让 AppKit 的窗口创建卡住约 30 秒（与参数名无关的环境行为），
    /// 所以这里只用单个 `--selftest` 参数 + 环境变量。
    private static func writeResult(_ result: [String: Any], ok: Bool) {
        guard let path = ProcessInfo.processInfo.environment["DSH_SELFTEST_OUTPUT"] else { return }
        var payload = result
        payload["passed"] = ok
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
