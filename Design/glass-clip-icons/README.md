# 可直接使用的图标文件

| 文件 | 用途 |
|---|---|
| `AppIcon.appiconset/` | 拖进 Xcode 的 `Assets.xcassets` 替换现有 AppIcon（16–512pt 的 @1x/@2x 共 10 张，Contents.json 已写好） |
| `AppIcon.icns` | 不走 Asset Catalog 时放进 `.app/Contents/Resources/`，Info.plist 里设 `CFBundleIconFile = AppIcon` |
| `icon-1024.png` | 1024×1024 主图（App Store Connect / 单尺寸 AppIcon） |
| `icon.svg` | 矢量源文件（1024 画布，824pt 圆角方形 + 系统风格投影） |
| `IconComposer/` | macOS 26 Liquid Glass 用的 background / foreground 两层（1024 满幅，SVG + PNG），导入 Apple Icon Composer 生成 `.icon` |

所有尺寸均按尺寸独立矢量渲染；形状为 Apple 的 824pt 连续圆角方形，macOS 26 会自动加玻璃边缘，不会出现灰色外框。
