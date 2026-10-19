import ImageIO
import SwiftUI

/// 预览窗口的尺寸规则。窗口大小（PreviewPanelController）和界面布局（ClipPreviewView）都按这里算，保证两边一致
enum PreviewLayout {
    /// 文本、文件预览的宽度
    static let width: CGFloat = 440
    static let headerHeight: CGFloat = 58
    static let padding: CGFloat = 14
    static let minHeight: CGFloat = 150
    static let maxHeight: CGFloat = 560
    /// 图片预览最大多大
    static let maxImageSize = CGSize(width: 480, height: 480)
    /// 文件预览里，图片文件的预览图最高多高
    static let fileImageMaxHeight: CGFloat = 280
    static let fileRowHeight: CGFloat = 34
    static let fileRowSpacing: CGFloat = 6
    /// 文本最多显示多少字（太长的文本全部排版会很慢，也没必要）
    static let maxTextLength = 20_000
    static let textFont = NSFont.systemFont(ofSize: 13)

    /// 预览窗口里玻璃部分的大小
    static func glassSize(for item: ClipItem) -> CGSize {
        let contentWidth = width - padding * 2
        let chrome = headerHeight + 1 + padding * 2   // 标题栏 + 分隔线 + 上下留白
        switch item.kind {
        case .text:
            let text = String((item.text ?? "").prefix(maxTextLength))
            let textHeight = NSAttributedString(string: text, attributes: [.font: textFont])
                .boundingRect(with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                              options: [.usesLineFragmentOrigin, .usesFontLeading])
                .height
            return CGSize(width: width, height: clamp(chrome + ceil(textHeight) + 4))

        case .image:
            guard let pixelSize = imagePixelSize(of: item) else {
                return CGSize(width: width, height: 320)
            }
            let image = fit(pixelSize, in: maxImageSize)
            return CGSize(width: max(image.width, 260) + padding * 2, height: chrome + image.height)

        case .file:
            let count = CGFloat(item.filePaths?.count ?? 1)
            var height = chrome + count * fileRowHeight + (count - 1) * fileRowSpacing
            if let pixelSize = imagePixelSize(of: item) {
                height += fileImageSize(pixelSize).height + 12
            }
            return CGSize(width: width, height: clamp(height))
        }
    }

    /// 文件预览里图片的显示大小
    static func fileImageSize(_ pixelSize: CGSize) -> CGSize {
        fit(pixelSize, in: CGSize(width: width - padding * 2, height: fileImageMaxHeight))
    }

    /// 图片的像素大小：图片记录直接用保存的尺寸，图片文件只读取文件头（很快，不用解码整张图）
    static func imagePixelSize(of item: ClipItem) -> CGSize? {
        if item.kind == .image, let w = item.imageWidth, let h = item.imageHeight, w > 0, h > 0 {
            return CGSize(width: w, height: h)
        }
        guard let path = item.imageFilePath,
              let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var w = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              var h = properties[kCGImagePropertyPixelHeight] as? CGFloat, w > 0, h > 0 else { return nil }
        // 照片可能带有"旋转"信息（方向值 5 ~ 8 表示要转 90 度），这时宽高要对调
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, orientation >= 5 {
            swap(&w, &h)
        }
        return CGSize(width: w, height: h)
    }

    /// 按比例缩小到能放进 box（小图不放大）
    static func fit(_ size: CGSize, in box: CGSize) -> CGSize {
        let scale = min(1, box.width / size.width, box.height / size.height)
        return CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
    }

    private static func clamp(_ height: CGFloat) -> CGFloat {
        min(max(height, minHeight), maxHeight)
    }
}

/// 预览窗口的内容：上面是标题栏（类型、来源、时间），下面是完整内容
struct ClipPreviewView: View {
    let item: ClipItem
    let store: ClipboardStore

    /// 大图（在后台生成）
    @State private var image: NSImage?

    init(item: ClipItem, store: ClipboardStore) {
        self.item = item
        self.store = store
        // 之前预览过的图片直接显示，切换回来时不用再转圈
        _image = State(initialValue: store.cachedLargeImage(for: item))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .opacity(0.6)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: item.id) {
            guard item.hasImagePreview, image == nil else { return }
            image = await store.loadLargeImage(for: item)
        }
    }

    // MARK: - 标题栏

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 3) {
                    if let app = item.sourceAppName {
                        Text(app)
                        Text("·")
                    }
                    Text(item.createdAt, format: .relative(presentation: .named))
                }
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, PreviewLayout.padding)
        .frame(height: PreviewLayout.headerHeight)
    }

    private var symbol: String {
        switch item.kind {
        case .text:  return "text.alignleft"
        case .image: return "photo"
        case .file:  return "doc"
        }
    }

    /// 标题：文本显示字数，图片显示尺寸，文件显示个数
    private var headline: String {
        switch item.kind {
        case .text:
            return "文本 · \((item.text ?? "").count) 个字"
        case .image:
            if let w = item.imageWidth, let h = item.imageHeight { return "图片 · \(w) × \(h)" }
            return "图片"
        case .file:
            let count = item.filePaths?.count ?? 0
            return count > 1 ? "\(count) 个文件" : "文件"
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:  textContent
        case .image: imageContent
        case .file:  fileContent
        }
    }

    private var textContent: some View {
        let text = item.text ?? ""
        let isTruncated = text.count > PreviewLayout.maxTextLength
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(isTruncated ? String(text.prefix(PreviewLayout.maxTextLength)) : text)
                    .font(Font(PreviewLayout.textFont))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isTruncated {
                    Text("内容太长，只显示了前 \(PreviewLayout.maxTextLength) 个字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(PreviewLayout.padding)
        }
    }

    private var imageContent: some View {
        largeImage
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(PreviewLayout.padding)
    }

    private var fileContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 第一个文件是图片时，在上面显示它的预览图
                if let pixelSize = PreviewLayout.imagePixelSize(of: item) {
                    let size = PreviewLayout.fileImageSize(pixelSize)
                    largeImage
                        .frame(width: size.width, height: size.height)
                        .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: PreviewLayout.fileRowSpacing) {
                    ForEach(item.filePaths ?? [], id: \.self) { path in
                        fileRow(path)
                    }
                }
            }
            .padding(PreviewLayout.padding)
        }
    }

    /// 文件的一行：图标、文件名、所在文件夹
    private func fileRow(_ path: String) -> some View {
        let exists = FileManager.default.fileExists(atPath: path)
        // 把 /Users/用户名 显示成 ~，既简短，也不会把用户名露出来
        let folder = ((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
        return HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 28, height: 28)
                .opacity(exists ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 1) {
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(exists ? folder : "文件已被移动或删除")
                    .font(.system(size: 11))
                    .foregroundStyle(exists ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(height: PreviewLayout.fileRowHeight)
    }

    /// 大图：生成好之前显示一个转圈
    @ViewBuilder
    private var largeImage: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                }
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
