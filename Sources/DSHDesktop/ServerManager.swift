import Foundation

/// 管理 dsh 服务器进程：检测 / 启动 / 监控 / 停止
@MainActor
final class ServerManager: ObservableObject {
    static let shared = ServerManager(appState: .shared)

    @Published var status: ServerStatus = .unknown
    @Published private(set) var serverProcess: Process?
    @Published private(set) var lastCommand: String = ""

    /// 本次运行中是否由我们启动了服务器（用于退出时决定是否停止）
    private(set) var startedByUs = false

    private let appState: AppState
    private var pollTask: Task<Void, Never>?
    private var stopping = false
    private var outputPipe: Pipe?
    private var spawnAt: Date?

    init(appState: AppState) {
        self.appState = appState
    }

    deinit {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
    }

    // MARK: - 检测

    /// 检测目标端口上是否已有 DSH 实例在运行（attach 模式，不归我们管）。
    /// 仅在我们没有亲自启动服务器时执行：否则会把 startedByUs 误置为
    /// false，导致退出应用时本该带走的服务器变成孤儿进程。
    func attach() async {
        guard serverProcess == nil else { return }
        let url = appState.url
        if await isHealthy(url) {
            Log.info("attach: 检测到运行中的 DSH 实例 at \(url.absoluteString)")
            startedByUs = false
            status = .running
            startPolling()
        } else if status != .starting {
            // 用户可能在 attach 完成前手动点了“启动”（status=.starting），
            // 此时不能把状态覆盖回 .stopped
            Log.info("attach: 端口 \(appState.port) 无实例，状态=stopped")
            status = .stopped
        }
    }

    // MARK: - 启动 / 停止

    func start() {
        guard serverProcess == nil, status != .starting else { return }
        stopping = false
        status = .starting
        lastCommand = appState.serverCommand

        let command = appState.serverCommand
        let port = appState.port

        Task {
            do {
                let resolved = try await Self.resolveCommand(command)
                Log.info("start: resolved command = \(resolved), port = \(port)")
                // 解析期间用户可能又点了启动/停止，防止重复 spawn
                guard self.serverProcess == nil else {
                    Log.info("start: 解析完成时已有进程在运行，放弃本次启动")
                    return
                }
                try spawn(resolved: resolved, port: port)
                startPolling()
            } catch {
                Log.info("start: 失败 \(error.localizedDescription)")
                status = .error("无法启动服务器：\(error.localizedDescription)")
            }
        }
    }

    func stop() {
        guard let process = serverProcess else { return }
        stopping = true
        status = .stopped
        process.terminate()
        // 3 秒内未退出则强杀
        Task {
            try? await Task.sleep(for: .seconds(3))
            if let p = self.serverProcess, p.isRunning {
                kill(p.processIdentifier, SIGKILL)
            }
        }
    }

    /// 同步停止并等待退出（用于应用退出 / 自测）
    func stopAndWait() {
        guard let process = serverProcess, process.isRunning else { return }
        stopping = true
        process.terminate()
        let deadline = Date().addingTimeInterval(4)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        serverProcess = nil
        status = .stopped
    }

    // MARK: - 进程

    private func spawn(resolved: String, port: Int) throws {
        // 端口边界保护：0 / 负值 / 越界会让应用连不上服务器
        let safePort = min(max(port, 1), 65535)
        let process = Process()
        spawnAt = Date()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        var full = resolved
        if !full.contains("--port") {
            full += " --port \(safePort)"
        }
        // exec 让 dsh 进程直接取代 shell，便于精确终止
        process.arguments = ["-c", "exec \(full)"]

        var env = ProcessInfo.processInfo.environment
        // 保证 `#!/usr/bin/env node` 能找到 node / dsh
        let binDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existing = env["PATH"] ?? ""
        env["PATH"] = binDirs.joined(separator: ":") + ":" + existing
        if env["DSH_HOME"] == nil {
            env["DSH_HOME"] = "\(NSHomeDirectory())/.dsh"
        }
        process.environment = env

        // 把服务器输出转发到应用 stdout，便于排障
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        outputPipe = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            FileHandle.standardOutput.write(data)
        }

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }
                if self.serverProcess === proc {
                    self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                    self.outputPipe = nil
                    self.serverProcess = nil
                    if self.status != .starting {
                        self.status = .stopped
                    }
                }
            }
        }

        try process.run()
        serverProcess = process
        startedByUs = true
        Log.info("spawn: pid=\(process.processIdentifier)")
    }

    /// 把用户命令解析为一条**不依赖 PATH** 的绝对命令。
    /// 关键背景：双击 .app 启动时进程由 launchd 拉起，PATH 只有系统目录
    /// （没有 /opt/homebrew/bin，也没有 npx 缓存目录），所以不能指望
    /// 终端里能用的 `dsh` 在双击场景也可用。解析结果会缓存到
    /// UserDefaults，之后直接复用。
    private static func resolveCommand(_ command: String) async throws -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ServerError.emptyCommand }

        let tokens = trimmed.split(separator: " ").map(String.init)
        let first = tokens[0]

        // 0. 缓存命中：上一次成功解析的绝对命令（校验首 token 仍存在）
        if let cached = UserDefaults.standard.string(forKey: "resolvedServerCommand"),
           let cachedFirst = cached.split(separator: " ").first.map(String.init),
           cachedFirst.hasPrefix("/"),
           FileManager.default.fileExists(atPath: cachedFirst) {
            return cached
        }

        // 1. 用户直接给了绝对路径
        if first.hasPrefix("/") {
            cacheResolved(trimmed)
            return trimmed
        }

        // 2. 常见绝对位置
        let candidates = ["/opt/homebrew/bin/\(first)", "/usr/local/bin/\(first)", "/usr/bin/\(first)", "/bin/\(first)"]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                let resolved = trimmed.replacingOccurrences(of: first, with: candidate)
                cacheResolved(resolved)
                return resolved
            }
        }

        // 3. 登录 shell 的 PATH 解析（shellResolve 已注入常见 bin 目录）
        if let resolved = await shellResolve(first) {
            let full = trimmed.replacingOccurrences(of: first, with: resolved)
            cacheResolved(full)
            return full
        }

        // 4. dsh 特化：绝对 node 直跑 npx 缓存里的 dsh 入口（完全离线、无 PATH 依赖）
        if first == "dsh" {
            if let direct = resolveNpxCachedDsh() {
                let rest = tokens.dropFirst().joined(separator: " ")
                let full = "\(direct) \(rest)".trimmingCharacters(in: .whitespaces)
                cacheResolved(full)
                return full
            }

            // 5. 绝对 npx 兜底（spawn 时的 PATH 已含 /opt/homebrew/bin，npx 能找到 node）
            for npx in ["/opt/homebrew/bin/npx", "/usr/local/bin/npx", "/usr/bin/npx"] {
                if FileManager.default.isExecutableFile(atPath: npx) {
                    let rest = tokens.dropFirst().joined(separator: " ")
                    let full = "\(npx) --yes @deepseek-ai/dsh \(rest)".trimmingCharacters(in: .whitespaces)
                    cacheResolved(full)
                    return full
                }
            }
        }

        throw ServerError.unresolvedCommand(trimmed)
    }

    /// 在 ~/.npm/_npx/<hash>/node_modules/@deepseek-ai/dsh/lib/bin.js 中
    /// 定位 dsh 的真实入口（取最新的），返回 "绝对node 绝对bin.js"。
    private static func resolveNpxCachedDsh() -> String? {
        let npxRoot = "\(NSHomeDirectory())/.npm/_npx"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: npxRoot) else { return nil }
        var best: (Date, String)?
        for entry in entries {
            let binPath = "\(npxRoot)/\(entry)/node_modules/@deepseek-ai/dsh/lib/bin.js"
            guard FileManager.default.fileExists(atPath: binPath) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: binPath)
            let mtime = attrs?[.modificationDate] as? Date ?? .distantPast
            if best == nil || mtime > best!.0 {
                best = (mtime, binPath)
            }
        }
        guard let (_, binPath) = best else { return nil }
        let nodeCandidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node", "/bin/node"]
        guard let node = nodeCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        return "\(node) \(binPath)"
    }

    private static func cacheResolved(_ command: String) {
        UserDefaults.standard.set(command, forKey: "resolvedServerCommand")
        Log.info("resolve: 已缓存启动命令 -> \(command)")
    }

    private static func shellResolve(_ name: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(name) 2>/dev/null || true"]
        // launchd 环境下 PATH 极简（登录 shell 也未必有 Homebrew），先注入常见目录
        var env = ProcessInfo.processInfo.environment
        let binDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existing = env["PATH"] ?? ""
        env["PATH"] = binDirs.joined(separator: ":") + ":" + existing
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let out = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }

    // MARK: - 健康监控

    private func startPolling() {
        pollTask?.cancel()
        let url = appState.url
        pollTask = Task { [weak self] in
            guard let self else { return }
            var consecutiveFailures = 0
            while !Task.isCancelled {
                let ok = await self.isHealthy(url)
                if ok {
                    consecutiveFailures = 0
                    if self.status != .running {
                        let ready = Date()
                        if let spawnAt = self.spawnAt {
                            Log.info("poll: 服务器就绪 → running（spawn 后 \(String(format: "%.2f", ready.timeIntervalSince(spawnAt)))s）")
                        } else {
                            Log.info("poll: 服务器就绪 → running")
                        }
                        self.status = .running
                    }
                    try? await Task.sleep(for: .seconds(5))
                } else {
                    consecutiveFailures += 1
                    if self.status == .running && consecutiveFailures >= 2 {
                        Log.info("poll: 连续失败 \(consecutiveFailures) 次 → 连接中断")
                        self.status = .error("与服务器的连接中断")
                    }
                    // 启动阶段加密轮询（0.5s），尽快发现服务器就绪
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }

    func isHealthy(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
        } catch {
            // 未连接
        }
        return false
    }
}

enum ServerError: LocalizedError {
    case emptyCommand
    case unresolvedCommand(String)

    var errorDescription: String? {
        switch self {
        case .emptyCommand:
            return "启动命令为空"
        case .unresolvedCommand(let command):
            return "找不到命令：\(command)（请在设置中配置正确的启动命令）"
        }
    }
}
