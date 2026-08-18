import SwiftUI
import ServiceManagement

/// 设置窗口
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var server: ServerManager

    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var updateMessage: String?
    @State private var isUpdatingDSH = false
    @State private var isCheckingApp = false
    @State private var pendingLatest: String?
    @State private var showUpdateConfirm = false

    var body: some View {
        Form {
            Section("服务器") {
                // 端口由 DSH 后端固定监听，只读展示，避免误改导致连不上后端
                LabeledContent("端口", value: "\(AppState.defaultPort)")
                TextField("启动命令", text: $appState.serverCommand)
                    .font(.system(.body, design: .monospaced))
                Text("例如：dsh --profile web。命令会被解析为绝对路径后执行，端口自动追加。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("启动应用时自动启动服务器", isOn: $appState.autoStartServer)
                Toggle("退出应用时保持服务器运行", isOn: $appState.keepServerOnQuit)
            }

            Section("桌面集成") {
                Toggle("开机自动启动 DSH Desktop", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { value in
                        setLaunchAtLogin(value)
                    }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("需要把应用放在 /Applications 目录下才能生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("状态") {
                LabeledContent("服务器状态", value: server.status.label)
                LabeledContent("连接地址", value: appState.url.absoluteString)
                LabeledContent("桥接插件（dsh-desktop-bridge）", value: appState.bridgeConnected ? "已连接" : "未检测到")
                if appState.bridgeConnected, !appState.bridgeInfo.isEmpty {
                    LabeledContent("桥接信息", value: appState.bridgeInfo)
                }
            }

            Section("关于") {
                LabeledContent("DSH Desktop", value: appVersion)
                LabeledContent("DSH 版本", value: server.currentDSHVersion ?? "待服务器启动后显示")
                LabeledContent("最低系统", value: "macOS 13+")
                if let updateMessage {
                    Text(updateMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(isUpdatingDSH ? "更新中…" : "检查 DSH 更新（联网拉最新版）") {
                    guard !isUpdatingDSH else { return }
                    isUpdatingDSH = true
                    updateMessage = "正在联网检查最新 dsh…"
                    // 先查询并对比版本：无新版直接结束，绝不停服
                    server.checkDSHUpdate { result in
                        switch result {
                        case .success(let latest):
                            if let latest {
                                isUpdatingDSH = false
                                pendingLatest = latest
                                updateMessage = "发现新版本 \(latest)（当前 \(server.currentDSHVersion ?? "未解析")）。确认后才会更新重启。"
                                showUpdateConfirm = true
                            } else {
                                isUpdatingDSH = false
                                updateMessage = "DSH 已是最新版本"
                            }
                        case .failure(let e):
                            isUpdatingDSH = false
                            updateMessage = "检查失败：\(e.localizedDescription)"
                        }
                    }
                }
                .disabled(isUpdatingDSH)
                .alert("发现新版本", isPresented: $showUpdateConfirm, presenting: pendingLatest) { latest in
                    Button("现在更新并重启") {
                        isUpdatingDSH = true
                        updateMessage = "正在更新到 \(latest)…"
                        server.applyDSHUpdate { r in
                            isUpdatingDSH = false
                            switch r {
                            case .success(let v):
                                updateMessage = "DSH 已更新到 \(v)，正在自动启动新的后端…"
                            case .failure(let e):
                                updateMessage = "更新失败：\(e.localizedDescription)"
                            }
                        }
                    }
                    Button("取消", role: .cancel) {}
                } message: { latest in
                    Text("是否下载 dsh \(latest) 并自动重启后端？")
                }
                Button(isCheckingApp ? "检查中…" : "检查应用更新") {
                    guard !isCheckingApp else { return }
                    isCheckingApp = true
                    updateMessage = "正在检查 GitHub 最新版本…"
                    checkAppUpdate { newest in
                        isCheckingApp = false
                        updateMessage = newest
                    }
                }
                .disabled(isCheckingApp)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear {
            launchAtLogin = isLaunchAtLoginEnabled()
        }
        .onDisappear {
            appState.saveSettings()
        }
    }

    // MARK: - 开机自启（SMAppService，macOS 13+）

    private func isLaunchAtLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchError = "设置开机自启失败：\(error.localizedDescription)"
            launchAtLogin = isLaunchAtLoginEnabled()
        }
    }
}


// 应用版本：从 Info.plist 读取 CFBundleShortVersionString
var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
}

// 检查 GitHub 最新 release 版本并比较
func checkAppUpdate(_ completion: @escaping (String) -> Void) {
    let url = URL(string: "https://api.github.com/repos/iiiiiei/dsh-macos/releases/latest")!
    URLSession.shared.dataTask(with: url) { data, _, error in
        DispatchQueue.main.async {
            guard error == nil, let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion("无法检查应用更新（请求失败）")
                return
            }
            let newest = obj["tag_name"] as? String ?? "?"
            if newest == appVersion || newest.hasSuffix(appVersion) {
                completion("已是最新版本：\(appVersion)")
            } else {
                completion("发现新版本：\(newest)（当前 \(appVersion)）。请前往 GitHub 下载。")
            }
        }
    }.resume()
}
