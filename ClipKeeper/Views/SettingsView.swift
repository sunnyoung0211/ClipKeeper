import Combine
import ServiceManagement
import SwiftUI

/// 设置窗口
struct SettingsView: View {
    let app: AppModel

    /// 开机自启的开关状态，从系统读取
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// 是否已获得辅助功能权限
    @State private var isTrusted = PasteService.isAccessibilityTrusted
    @State private var errorMessage: String?
    @State private var showClearConfirm = false

    /// 每秒检查一次权限状态（用户去系统设置授权后，这里能自动更新）
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let historyLimits = [50, 100, 200, 500, 1000]

    /// 设置窗口的高度。演示模式下可以用启动参数 `-DemoSettingsHeight` 调整，方便截图
    private static var windowHeight: CGFloat {
        #if DEBUG
        let demoHeight = UserDefaults.standard.double(forKey: "DemoSettingsHeight")
        if demoHeight > 0 { return demoHeight }
        #endif
        return 720
    }

    var body: some View {
        // @Bindable 让我们可以用 $settings.xxx 把设置项绑定到开关、选择器上
        @Bindable var settings = app.settings

        // ScrollViewReader 用来在需要时滚动到"更新"分组
        ScrollViewReader { proxy in
            Form {
                Section("通用") {
                    Toggle("开机时自动启动", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            setLaunchAtLogin(enabled)
                        }
                    LabeledContent("呼出快捷键") {
                        HotkeyRecorderView(app: app)
                    }
                    Picker("最多保存", selection: $settings.maxHistory) {
                        ForEach(historyLimits, id: \.self) { limit in
                            Text("\(limit) 条").tag(limit)
                        }
                    }
                    .onChange(of: settings.maxHistory) {
                        app.store.applyHistoryLimit()
                    }
                    Toggle("暂停记录", isOn: $settings.isPaused)
                }

                Section {
                    Picker("面板出现在", selection: $settings.panelPlacement) {
                        ForEach(PanelPlacement.allCases) { placement in
                            Text(placement.display).tag(placement)
                        }
                    }
                    LabeledContent("面板大小和位置") {
                        Button("恢复默认") {
                            app.panelController.resetSizeAndPosition()
                        }
                    }
                } header: {
                    Text("面板")
                } footer: {
                    Text("拖动面板的顶部或底部空白处可以移动它，拖动边缘或四个角可以调整大小。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("选中后自动粘贴到当前应用", isOn: $settings.autoPaste)
                    LabeledContent("辅助功能权限") {
                        if isTrusted {
                            Label("已授权", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("去授权…") {
                                PasteService.requestAccessibility()
                                PasteService.openAccessibilitySettings()
                            }
                        }
                    }
                } header: {
                    Text("粘贴")
                } footer: {
                    Text("自动粘贴需要模拟按下 ⌘V，所以要在「系统设置 → 隐私与安全性 → 辅助功能」中允许 ClipKeeper。未授权时，选中的内容只会被复制到剪贴板。\n\n如果开关已打开但这里仍显示未授权：请在列表中选中 ClipKeeper 点「−」删除，重新打开 ClipKeeper 后再授权一次。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(settings.ignoredBundleIDs, id: \.self) { bundleID in
                        HStack {
                            appIcon(for: bundleID)
                            Text(appName(for: bundleID))
                            Spacer()
                            Button {
                                settings.ignoredBundleIDs.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Menu("添加正在运行的应用…") {
                        ForEach(addableApps(), id: \.processIdentifier) { runningApp in
                            Button(runningApp.localizedName ?? runningApp.bundleIdentifier ?? "未知应用") {
                                if let id = runningApp.bundleIdentifier {
                                    settings.ignoredBundleIDs.append(id)
                                }
                            }
                        }
                    }
                } header: {
                    Text("隐私：不记录以下应用中复制的内容")
                } footer: {
                    Text("1Password 等密码管理器复制的密码会被自动忽略。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("数据") {
                    LabeledContent("已保存", value: "\(app.store.items.count) 条")
                    Button("在访达中打开数据文件夹") {
                        OpenHelper.openInFinder(ClipboardStore.dataFolderURL)
                    }
                    Button("清空全部历史…", role: .destructive) {
                        showClearConfirm = true
                    }
                }

                UpdateSection(updater: app.updater, settings: settings)
            }
            .formStyle(.grouped)
            .onChange(of: app.updater.wantsReveal, initial: true) { _, wantsReveal in
                guard wantsReveal else { return }
                app.updater.wantsReveal = false
                // 等窗口和列表布局好再滚动
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo(UpdateSection.scrollID, anchor: .bottom) }
                }
            }
        }
        .frame(width: 480, height: Self.windowHeight)
        .onReceive(timer) { _ in
            isTrusted = PasteService.isAccessibilityTrusted
        }
        .confirmationDialog("确定要清空历史吗？", isPresented: $showClearConfirm) {
            Button("清空全部（包括置顶）", role: .destructive) { app.store.clearAll() }
            Button("只清空未置顶的") { app.store.clearUnpinned() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销。")
        }
        .alert("出错了", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 开机自启

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "设置开机启动失败：\(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - 应用信息

    /// 可以添加到忽略列表的应用：正在运行、有界面、且还没被忽略
    private func addableApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { runningApp in
                guard runningApp.activationPolicy == .regular,
                      let id = runningApp.bundleIdentifier else { return false }
                return id != Bundle.main.bundleIdentifier && !app.settings.ignoredBundleIDs.contains(id)
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private func appIcon(for bundleID: String) -> some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
            }
        }
        .frame(width: 20, height: 20)
    }
}
