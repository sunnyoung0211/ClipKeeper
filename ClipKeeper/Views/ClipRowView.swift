import SwiftUI

/// 历史列表中的一行
struct ClipRowView: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let thumbnail: NSImage?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                subtitle
            }

            Spacer(minLength: 4)

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.orange))
            }
            // 前 9 条显示 ⌘1 ~ ⌘9 的快捷键提示
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovered = $0 }
        // 鼠标悬停时显示完整文字（最多 1000 字）
        .help(item.kind == .text ? String((item.text ?? "").prefix(1000)) : item.title)
    }

    /// 选中时用系统强调色填充（和 macOS 菜单的高亮风格一致），悬停时淡淡地高亮
    private var background: Color {
        if isSelected { return .accentColor }
        if isHovered { return .primary.opacity(0.07) }
        return .clear
    }

    /// 左侧图标：图片显示缩略图，文件显示文件图标，文本显示一个文字符号
    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                symbol("photo")
            }
        case .file:
            if let path = item.filePaths?.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
            } else {
                symbol("doc")
            }
        case .text:
            symbol("text.alignleft")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(width: 28, height: 28)
            .background(
                isSelected ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(.primary.opacity(0.06)),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }

    /// 副标题：来源应用 · 多久之前
    private var subtitle: some View {
        HStack(spacing: 3) {
            if let app = item.sourceAppName {
                Text(app)
                Text("·")
            }
            Text(item.createdAt, format: .relative(presentation: .named))
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
    }
}
