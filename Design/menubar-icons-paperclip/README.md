# 菜单栏常驻图标 · 回形针版（NSStatusItem）

与 App 图标同一枚回形针。`tilted/`（32° 倾斜，和 App 图标一致）和 `upright/`（直立）两套，各含：

| 文件 | 说明 |
|---|---|
| `MenuBarIcon.imageset/` | 正常状态。拖进 `Assets.xcassets` 即可，Contents.json 已设为 **Template Image** |
| `MenuBarIconPaused.imageset/` | 已暂停状态（右下角双竖线，带 1pt 留白切口） |
| `svg/` | 矢量源文件，18×18 pt 画布 |

规格：18×18 pt 画布，图形约 16pt 高，PNG 为 @1x 18px / @2x 36px，黑色 + Alpha 模板图，系统自动按深浅色着色。
两个状态的图宽度相同，切换时菜单栏不会跳动。

```swift
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.image = NSImage(named: "MenuBarIcon")

func setPaused(_ paused: Bool) {
    statusItem.button?.image = NSImage(named: paused ? "MenuBarIconPaused" : "MenuBarIcon")
}
```

直接加载 PNG 文件（不走 Asset Catalog）时需手动 `image.isTemplate = true`。
