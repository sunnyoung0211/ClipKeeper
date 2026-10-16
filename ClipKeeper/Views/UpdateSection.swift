import SwiftUI

/// 设置窗口里的"更新"分组：显示当前版本、检查更新、下载并安装
struct UpdateSection: View {
    let updater: UpdateService

    var body: some View {
        Section {
            LabeledContent("当前版本", value: updater.currentVersion)
            statusRow
        } header: {
            Text("更新")
        } footer: {
            Text("新版本从 GitHub 下载，安装完成后 ClipKeeper 会自动重新打开。更新后如果自动粘贴不起作用，请按上面「粘贴」部分的说明重新授权辅助功能。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 根据当前状态显示不同的内容
    @ViewBuilder
    private var statusRow: some View {
        switch updater.state {
        case .idle:
            LabeledContent("检查新版本") {
                Button("检查更新") { check() }
            }

        case .checking:
            LabeledContent("检查新版本") {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("正在检查…").foregroundStyle(.secondary)
                }
            }

        case .upToDate:
            LabeledContent("检查新版本") {
                HStack(spacing: 10) {
                    Label("已是最新版本", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("再次检查") { check() }
                }
            }

        case .available(let release):
            LabeledContent {
                HStack(spacing: 8) {
                    Button("更新说明") { OpenHelper.openWebPage(release.pageURL) }
                    Button("下载并安装") { updater.installUpdate() }
                        .buttonStyle(.borderedProminent)
                }
            } label: {
                Label("发现新版本 \(release.version)", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
            }

        case .downloading(let fraction):
            LabeledContent("正在下载 \(updater.latestRelease?.version ?? "")") {
                HStack(spacing: 8) {
                    ProgressView(value: fraction)
                        .frame(width: 120)
                    Text("\(Int(fraction * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                    Button("取消") { updater.cancel() }
                }
            }

        case .installing:
            LabeledContent("正在安装") {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("完成后会自动重新打开").foregroundStyle(.secondary)
                }
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("前往下载页面") {
                        OpenHelper.openWebPage(updater.latestRelease?.pageURL ?? UpdateService.releasesPageURL)
                    }
                    Button("重试") { updater.retry() }
                }
            }
        }
    }

    private func check() {
        Task { await updater.checkForUpdates() }
    }
}
