import SwiftUI

/// 历史列表中的一行
struct ClipRowView: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let store: ClipboardStore

    @State private var isHovered = false
    /// 图片的预览图（在后台生成，生成好之前显示占位图）
    @State private var preview: NSImage?
    /// 预览图生成失败（比如文件已损坏），改为显示普通图标
    @State private var previewFailed = false

    /// 预览图区域的大小。所有图片行都用同样大小的区域，文字才能对齐
    private static let previewSize = CGSize(width: 76, height: 52)

    init(item: ClipItem, index: Int, isSelected: Bool, store: ClipboardStore) {
        self.item = item
        self.index = index
        self.isSelected = isSelected
        self.store = store
        // 已经生成过的预览图直接拿来用，避免列表刷新时闪一下占位图
        _preview = State(initialValue: store.cachedThumbnail(for: item))
    }

    var body: some View {
        HStack(spacing: 10) {
            if item.hasImagePreview && !previewFailed {
                previewImage
            } else {
                icon
                    .frame(width: 28, height: 28)
            }

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
        .task(id: item.id) {
            guard item.hasImagePreview, preview == nil else { return }
            preview = await store.loadThumbnail(for: item)
            previewFailed = preview == nil
        }
    }

    /// 选中时用系统强调色填充（和 macOS 菜单的高亮风格一致），悬停时淡淡地高亮
    private var background: Color {
        if isSelected { return .accentColor }
        if isHovered { return .primary.opacity(0.07) }
        return .clear
    }

    /// 图片预览：完整显示整张图（不裁剪），按比例缩放到预览区域里
    private var previewImage: some View {
        ZStack {
            if let preview {
                Image(nsImage: preview)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay {
                        // 细描边：让浅色、透明背景的图片也能看清边界
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(isSelected ? AnyShapeStyle(.white.opacity(0.35)) : AnyShapeStyle(.primary.opacity(0.12)),
                                          lineWidth: 0.5)
                    }
            } else {
                // 预览图还没生成好时的占位
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(.primary.opacity(0.06)))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
                    }
            }
        }
        .frame(width: Self.previewSize.width, height: Self.previewSize.height)
    }

    /// 左侧图标：文件显示文件图标，文本显示一个文字符号（图片显示上面的预览图）
    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .image:
            symbol("photo")
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
