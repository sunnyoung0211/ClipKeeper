import SwiftUI

/// 浮动历史面板的界面：搜索框 + 历史列表 + 底部快捷键提示。
///
/// 圆角玻璃背景、阴影、拖边缩放都由外层的 PanelContainerView（AppKit）负责，
/// 这里只关心内容，并且会自动适应窗口的大小。
struct HistoryPanelView: View {
    @Bindable var model: PanelViewModel

    var body: some View {
        // 先算一次结果，避免在 body 里重复过滤
        let results = model.results

        VStack(spacing: 0) {
            searchBar(count: results.count)
                .padding(10)
                .background(WindowDragArea())   // 搜索框四周的空白处可以拖动窗口

            if results.isEmpty {
                emptyView
            } else {
                historyList(results)
            }

            Divider()
                .opacity(0.6)
            footer
                .background(WindowDragArea())   // 底部提示栏也可以拖动窗口
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 注意：打开面板时搜索框故意不获得焦点，用户点了它才在里面输入。
        // 没点搜索框就直接打字的话，PanelController 会关掉面板，把按键交还给原来的应用。
    }

    // MARK: - 搜索框

    private func searchBar(count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索剪贴板", text: $model.query)
                .textFieldStyle(.plain)
            if model.query.isEmpty {
                Text("\(count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.tertiary)
            } else {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .frame(height: 34)
        // 在玻璃上做出一个淡淡的"凹槽"当作输入框，有层次感又不会显得厚重
        .background(.primary.opacity(0.06), in: Capsule())
    }

    // MARK: - 列表

    private func historyList(_ results: [ClipItem]) -> some View {
        // ScrollViewReader 可以让我们用代码把某一行滚动到可见位置
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        ClipRowView(
                            item: item,
                            index: index,
                            isSelected: item.id == model.selectedID,
                            store: model.store
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.click(item)
                        }
                        .contextMenu {
                            contextMenu(for: item)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selectedID) { _, newID in
                if let newID {
                    proxy.scrollTo(newID)
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
        Button("粘贴") { model.onSelect?(item) }
        Button("仅复制到剪贴板") { model.onCopyOnly?(item) }
        Button("预览") { model.preview(item) }
            .keyboardShortcut("y", modifiers: .command)   // 在菜单里显示快捷键 ⌘Y，提示用户
        Divider()
        Button(item.isPinned ? "取消置顶" : "置顶") { model.store.togglePin(item) }
        Button("删除", role: .destructive) { model.store.delete(item) }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "还没有记录，复制点什么试试吧" : "没有找到相关内容")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部快捷键提示

    private var footer: some View {
        // ViewThatFits 会依次尝试，用第一个放得下的：面板窄的时候少显示几个提示
        ViewThatFits(in: .horizontal) {
            footerHints(showPin: true, showDelete: true)
            footerHints(showPin: true, showDelete: false)
            footerHints(showPin: false, showDelete: false)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 30)
    }

    private func footerHints(showPin: Bool, showDelete: Bool) -> some View {
        HStack(spacing: 12) {
            hint("↩", model.settings.autoPaste ? "粘贴" : "复制")
            // 有搜索词时空格要用来打字，所以提示换成 ⌘Y
            hint(model.query.isEmpty ? "空格" : "⌘Y", "预览")
            if showPin { hint("⌘P", "置顶") }
            if showDelete { hint("⌘⌫", "删除") }
            Spacer(minLength: 0)
            hint("esc", "关闭")
        }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .fontWeight(.medium)
            Text(label)
                .foregroundStyle(.tertiary)
        }
    }
}
