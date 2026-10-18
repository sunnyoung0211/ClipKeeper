import Foundation
import Observation

/// 历史面板的状态：搜索词、当前选中哪一条，以及键盘操作的处理逻辑。
/// 把逻辑放在这里而不是直接写在界面里，界面代码会更简洁。
@Observable
final class PanelViewModel {
    var query = "" {
        // 搜索词变了，就重新选中第一条结果（只是被重新赋了同样的值时不算）
        didSet {
            if query != oldValue { selectFirst() }
        }
    }
    var selectedID: UUID? {
        didSet {
            if selectedID != oldValue { onSelectionChanged?() }
        }
    }

    @ObservationIgnored let store: ClipboardStore
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored var onSelect: ((ClipItem) -> Void)?
    @ObservationIgnored var onCopyOnly: ((ClipItem) -> Void)?
    /// 选中了另一条（用来让预览窗口跟着切换）
    @ObservationIgnored var onSelectionChanged: (() -> Void)?
    /// 打开某条记录的预览（右键菜单里的"预览"）
    @ObservationIgnored var onPreview: ((ClipItem) -> Void)?

    init(store: ClipboardStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    /// 当前显示的结果（根据搜索词过滤）
    var results: [ClipItem] {
        store.filtered(by: query)
    }

    /// 每次打开面板时调用：清空搜索、选中第一条
    func reset() {
        query = ""
        selectFirst()
    }

    func selectFirst() {
        selectedID = results.first?.id
    }

    /// 上下移动选中项。delta = -1 向上，+1 向下
    func moveSelection(by delta: Int) {
        let list = results
        guard !list.isEmpty else { return }
        let currentIndex = list.firstIndex { $0.id == selectedID } ?? 0
        let newIndex = min(max(currentIndex + delta, 0), list.count - 1)
        selectedID = list[newIndex].id
    }

    /// 用鼠标点了某一条：没选中的先选中它，点的是已经选中的那条才粘贴。
    /// 这样连点两下（双击）就是"选中并粘贴"
    func click(_ item: ClipItem) {
        if item.id == selectedID {
            onSelect?(item)
        } else {
            selectedID = item.id
        }
    }

    /// 选中某一条并打开它的预览
    func preview(_ item: ClipItem) {
        selectedID = item.id
        onPreview?(item)
    }

    /// 确认选中项（回车）
    func confirmSelection() {
        if let item = selectedItem {
            onSelect?(item)
        }
    }

    /// ⌘1 ~ ⌘9 快速选择第 n 条
    func quickSelect(index: Int) {
        let list = results
        guard list.indices.contains(index) else { return }
        onSelect?(list[index])
    }

    func togglePinSelected() {
        if let item = selectedItem {
            store.togglePin(item)
        }
    }

    /// 删除选中项，并把选中位置移到相邻的一条
    func deleteSelected() {
        let list = results
        guard let index = list.firstIndex(where: { $0.id == selectedID }) else { return }
        let item = list[index]
        let next = list.indices.contains(index + 1) ? list[index + 1] : (index > 0 ? list[index - 1] : nil)
        store.delete(item)
        selectedID = next?.id
    }

    /// 当前选中的记录
    var selectedItem: ClipItem? {
        results.first { $0.id == selectedID }
    }
}
