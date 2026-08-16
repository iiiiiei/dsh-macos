import SwiftUI
import ServiceManagement

/// 设置窗口
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var server: ServerManager

    @State private var launchAtLogin = false
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("服务器") {
                TextField("端口", value: $appState.port, format: .number)
                TextField("启动命令", text: $appState.serverCommand)
                    .font(.system(.body, design: .monospaced))
                Text("例如：dsh --profile web。命令会被解析为绝对路径后执行，端口自动追加。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("启动应用时自动启动服务器", isOn: $appState.autoStartServer)
                Toggle("退出应用时保持服务器运行", isOn: $appState.keepServerOnQuit)
            }

            Section("外观（Appearance）") {
                Picker("皮肤", selection: $appState.appearanceId) {
                    ForEach(AppearanceCatalog.available, id: \.id) { m in
                        Text(m.name).tag(m.id)
                    }
                    // 预留扩展点（本任务不实现皮肤，仅展示规划）
                    Text("Glass（规划中）").tag("glass")
                    Text("Compact（规划中）").tag("compact")
                }
                .pickerStyle(.menu)
                Text("Official 为默认外观（零覆盖）；皮肤类外观基于 Official 叠加 Overlay。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("沉浸式标题栏（红绿灯悬浮、内容顶到顶）", isOn: $appState.immersiveTitlebar)
                Toggle("中文通俗说明（翻译固定 UI，聊天内容不受影响）", isOn: $appState.zhOverlay)
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
                LabeledContent("DSH Desktop", value: "v1.0.0")
                LabeledContent("DSH 版本", value: "rc.6")
                LabeledContent("最低系统", value: "macOS 13+")
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
