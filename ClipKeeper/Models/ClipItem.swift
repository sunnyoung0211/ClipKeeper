import Foundation
import SwiftData
import UniformTypeIdentifiers

/// 剪贴板内容的类型
enum ClipKind: String {
    case text   // 纯文本
    case image  // 图片
    case file   // 在 Finder 中复制的文件
}

/// 一条剪贴板历史记录。
///
/// 加上 @Model 之后，SwiftData 会自动把这个类的属性保存到数据库里，
/// 我们不需要自己写任何读写文件的代码。
@Model
final class ClipItem {
    var id: UUID
    /// 类型的原始字符串。SwiftData 存储简单类型最稳妥，所以这里存 String，
    /// 再通过下面的计算属性 `kind` 转成枚举使用。
    var kindRaw: String
    /// 文本内容。文件类型时保存文件名，方便搜索。
    var text: String?
    /// 图片数据（PNG 格式）。
    /// `.externalStorage` 表示数据较大时，SwiftData 会把它存成单独的文件，而不是塞进数据库。
    @Attribute(.externalStorage) var imageData: Data?
    var imageWidth: Int?
    var imageHeight: Int?
    /// 文件的完整路径（只有文件类型才有）
    var filePaths: [String]?
    /// 是从哪个应用复制的
    var sourceAppName: String?
    var sourceBundleID: String?
    var createdAt: Date
    var isPinned: Bool
    /// 内容"指纹"。两次复制的内容相同，指纹就相同，用来去重。
    var contentHash: String

    init(
        kind: ClipKind,
        text: String? = nil,
        imageData: Data? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        filePaths: [String]? = nil,
        sourceAppName: String? = nil,
        sourceBundleID: String? = nil,
        contentHash: String
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.text = text
        self.imageData = imageData
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.filePaths = filePaths
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.createdAt = .now
        self.isPinned = false
        self.contentHash = contentHash
    }

    /// 方便使用的枚举类型（计算属性不会被保存到数据库）
    var kind: ClipKind {
        ClipKind(rawValue: kindRaw) ?? .text
    }

    /// 在列表中显示的标题
    var title: String {
        switch kind {
        case .text:
            // 只取前 300 个字符，并把换行、连续空格压缩成一个空格
            let head = String((text ?? "").prefix(300))
            return head
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case .image:
            if let w = imageWidth, let h = imageHeight {
                return "图片  \(w) × \(h)"
            }
            return "图片"
        case .file:
            let names = (filePaths ?? []).map { ($0 as NSString).lastPathComponent }
            if names.count > 1 {
                return "\(names[0]) 等 \(names.count) 个文件"
            }
            return names.first ?? "文件"
        }
    }

    /// 能不能在列表里显示预览图：图片，或者复制的第一个文件是图片文件
    var hasImagePreview: Bool {
        switch kind {
        case .image: return true
        case .file:  return imageFilePath != nil
        case .text:  return false
        }
    }

    /// 复制的文件中，第一个是图片文件（并且还在原来的位置）时，返回它的路径
    var imageFilePath: String? {
        guard kind == .file, let path = filePaths?.first,
              let type = UTType(filenameExtension: (path as NSString).pathExtension),
              type.conforms(to: .image),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }
}
