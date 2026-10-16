// 更新 App 图标（写入 ClipKeeper/Assets.xcassets/AppIcon.appiconset）。
//
// 用法（在项目根目录运行）：
//   swift scripts/make-icons.swift                 使用当前采用的图标方案（07b-glassclip-coral）
//   swift scripts/make-icons.swift 方案文件夹        换成另一个图标方案，例如 Design/glass-clip-icons/<方案文件夹>
//   swift scripts/make-icons.swift 某个图标.svg      用 SVG 渲染出全部尺寸
//   swift scripts/make-icons.swift 输入.svg 输出.png 像素尺寸    单独渲染一张，用来预览
//
// 图标方案文件夹里已经有设计时按尺寸单独渲染好的 PNG（AppIcon.appiconset），直接复制过来效果最好。
// 用 SVG 渲染时用的是 macOS 自带的 SVG 解析，它不支持一部分效果（比如 feDropShadow 投影、
// 对整组图形的模糊），复杂的图标可能和设计稿不一样，渲染完记得看一眼。
import AppKit

/// 把 SVG 渲染成指定像素大小的 PNG（macOS 自带 SVG 解析，不需要安装其他工具）
func render(svg: URL, to output: URL, pixels: Int) throws {
    guard let image = NSImage(contentsOf: svg) else {
        throw NSError(domain: "make-icons", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取 \(svg.path)"])
    }
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    try rep.representation(using: .png, properties: [:])!.write(to: output)
}

let args = CommandLine.arguments
if args.count == 4 {
    // 单个文件模式
    try render(svg: URL(fileURLWithPath: args[1]), to: URL(fileURLWithPath: args[2]), pixels: Int(args[3])!)
    print("✅ \(args[2])")
    exit(0)
}

let currentScheme = "Design/glass-clip-icons/07b-glassclip-coral"
let iconSet = URL(fileURLWithPath: "ClipKeeper/Assets.xcassets/AppIcon.appiconset")
let fileManager = FileManager.default
try fileManager.createDirectory(at: iconSet, withIntermediateDirectories: true)

let source = args.count == 2 ? args[1] : currentScheme
var isDirectory: ObjCBool = false
guard fileManager.fileExists(atPath: source, isDirectory: &isDirectory) else {
    print("❌ 找不到 \(source)")
    exit(1)
}

if isDirectory.boolValue {
    // 方案文件夹：直接复制里面已经渲染好的 PNG 和 Contents.json
    let schemeIconSet = URL(fileURLWithPath: source).appendingPathComponent("AppIcon.appiconset")
    let files = try fileManager.contentsOfDirectory(atPath: schemeIconSet.path)
        .filter { $0.hasSuffix(".png") || $0 == "Contents.json" }
    guard files.contains("Contents.json") else {
        print("❌ \(schemeIconSet.path) 里没有 Contents.json，不是一个图标集")
        exit(1)
    }
    for file in files {
        let target = iconSet.appendingPathComponent(file)
        try? fileManager.removeItem(at: target)
        try fileManager.copyItem(at: schemeIconSet.appendingPathComponent(file), to: target)
    }
    print("✅ 已从 \(source) 复制 \(files.count - 1) 张图标")
    exit(0)
}

// SVG 文件：渲染出全部尺寸
let svg = URL(fileURLWithPath: source)

// macOS 图标需要的规格：(点数, 倍率)
let specs: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]
var images: [[String: String]] = []
for spec in specs {
    let pixels = spec.points * spec.scale
    let name = "icon_\(spec.points)x\(spec.points)\(spec.scale == 2 ? "@2x" : "").png"
    try render(svg: svg, to: iconSet.appendingPathComponent(name), pixels: pixels)
    images.append([
        "filename": name, "idiom": "mac",
        "scale": "\(spec.scale)x", "size": "\(spec.points)x\(spec.points)",
    ])
}

// 写入 Xcode 用来描述图标集的 Contents.json
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: iconSet.appendingPathComponent("Contents.json"))
print("✅ 已从 SVG 生成 \(specs.count) 个尺寸的 App 图标，请检查渲染效果是否和设计稿一致")
