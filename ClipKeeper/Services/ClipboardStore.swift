import AppKit
import SwiftData

/// 管理所有剪贴板历史：增加、删除、置顶、搜索，以及保存到数据库。
///
/// 界面只读取 `items`，所有修改都通过这个类的方法完成，
/// 这样数据的变化都集中在一个地方，便于理解和排查问题。
@Observable
final class ClipboardStore {
    /// 当前所有历史记录：置顶的排在前面，其余按时间从新到旧排列
    private(set) var items: [ClipItem] = []

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var context: ModelContext { container.mainContext }
    /// 图片缩略图缓存，避免每次刷新界面都重新解码图片
    @ObservationIgnored private let thumbnailCache = NSCache<NSString, NSImage>()

    /// 数据保存的文件夹：~/Library/Application Support/ClipKeeper
    static var dataFolderURL: URL {
        URL.applicationSupportDirectory.appending(path: "ClipKeeper", directoryHint: .isDirectory)
    }

    /// - Parameter inMemory: true 时数据只放在内存里、不写磁盘（演示模式用）
    init(settings: AppSettings, inMemory: Bool = false) {
        self.settings = settings
        self.container = inMemory ? Self.makeInMemoryContainer() : Self.makeContainer()
        reload()
    }

    // MARK: - 修改数据

    /// 添加一条新记录。如果相同内容已经存在，就把旧的那条移到最前面。
    func add(_ newItem: ClipItem) {
        let hash = newItem.contentHash
        let descriptor = FetchDescriptor<ClipItem>(predicate: #Predicate { $0.contentHash == hash })

        if let existing = try? context.fetch(descriptor).first {
            existing.createdAt = .now
            existing.sourceAppName = newItem.sourceAppName
            existing.sourceBundleID = newItem.sourceBundleID
        } else {
            context.insert(newItem)
        }
        trimToLimit()
        saveAndReload()
    }

    /// 把某条记录"刷新"成最新（用户重新使用它时调用）
    func bump(_ item: ClipItem) {
        item.createdAt = .now
        saveAndReload()
    }

    func togglePin(_ item: ClipItem) {
        item.isPinned.toggle()
        saveAndReload()
    }

    func delete(_ item: ClipItem) {
        thumbnailCache.removeObject(forKey: item.id.uuidString as NSString)
        context.delete(item)
        saveAndReload()
    }

    /// 清空历史，但保留置顶的
    func clearUnpinned() {
        try? context.delete(model: ClipItem.self, where: #Predicate { !$0.isPinned })
        thumbnailCache.removeAllObjects()
        saveAndReload()
    }

    /// 清空全部历史（包括置顶的）
    func clearAll() {
        try? context.delete(model: ClipItem.self)
        thumbnailCache.removeAllObjects()
        saveAndReload()
    }

    /// 设置里修改了"最多保存条数"后调用
    func applyHistoryLimit() {
        trimToLimit()
        saveAndReload()
    }

    // MARK: - 读取数据

    /// 按关键字搜索。关键字为空时返回全部。
    func filtered(by query: String) -> [ClipItem] {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return items }
        return items.filter { item in
            (item.text ?? "").localizedCaseInsensitiveContains(keyword)
                || (item.sourceAppName ?? "").localizedCaseInsensitiveContains(keyword)
        }
    }

    /// 获取图片记录的缩略图
    func thumbnail(for item: ClipItem) -> NSImage? {
        guard item.kind == .image else { return nil }
        let key = item.id.uuidString as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let data = item.imageData, let image = NSImage(data: data) else { return nil }
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    // MARK: - 内部工具

    /// 超出最大条数时，删除最旧的未置顶记录
    private func trimToLimit() {
        let descriptor = FetchDescriptor<ClipItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let unpinned = try? context.fetch(descriptor) else { return }
        // 注意：这里没有用 FetchDescriptor 的 fetchOffset 来"跳过前 N 条"，
        // 因为 SwiftData 对还没保存的新记录会忽略 fetchOffset，导致新记录被误删。
        for item in unpinned.dropFirst(settings.maxHistory) {
            thumbnailCache.removeObject(forKey: item.id.uuidString as NSString)
            context.delete(item)
        }
    }

    /// 保存到数据库，并重新读取列表让界面刷新
    private func saveAndReload() {
        do {
            try context.save()
        } catch {
            print("保存失败：\(error)")
        }
        reload()
    }

    private func reload() {
        let descriptor = FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let all = (try? context.fetch(descriptor)) ?? []
        // 置顶的排前面，两部分内部都保持时间倒序
        items = all.filter(\.isPinned) + all.filter { !$0.isPinned }
    }

    /// 创建 SwiftData 数据库容器
    private static func makeInMemoryContainer() -> ModelContainer {
        try! ModelContainer(for: ClipItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private static func makeContainer() -> ModelContainer {
        // 注意：我们的应用没有开启沙盒，如果用默认位置，数据库会放在公共的
        // Application Support 目录下，可能和别的应用冲突，所以单独指定一个文件夹。
        let folder = dataFolderURL
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config = ModelConfiguration(url: folder.appending(path: "History.store"))
        do {
            return try ModelContainer(for: ClipItem.self, configurations: config)
        } catch {
            // 数据库打不开时（比如文件损坏），退而使用内存数据库，保证应用还能用
            print("无法打开数据库，改用临时内存存储：\(error)")
            let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: ClipItem.self, configurations: memoryConfig)
        }
    }
}
