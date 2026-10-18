import AppKit
import CryptoKit
import Security

/// 检查更新、下载并安装新版本。
///
/// 新版本发布在 GitHub 的 Releases 页面上。检查更新时向 GitHub 查询"最新的正式版本"，
/// 版本号比当前的新，就提示用户。用户点"下载并安装"后：
/// 1. 下载 DMG 安装包，并核对文件的 SHA-256 校验值，确保下载完整、没被篡改
/// 2. 在后台挂载 DMG，把里面的 ClipKeeper.app 复制出来，然后卸载 DMG
/// 3. 检查复制出来的应用：Bundle ID 必须和当前一致、版本号要对得上、代码签名完好；
///    如果当前版本用的是"固定签名"，新版本也必须是同一张证书签的
/// 4. 用新应用替换掉正在运行的这个（运行中的程序已经加载进内存，替换磁盘上的文件不影响它）
/// 5. 打开新版本；新版本启动时会让旧版本退出（见 AppDelegate.terminateOtherInstances）
///
/// 小知识：用 URLSession 下载的文件不会被加上"隔离"标记，所以装好的新版本打开时
/// 不会再弹"无法验证开发者"的提示。
@Observable
final class UpdateService {
    /// GitHub 上的仓库（"用户名/仓库名"）。如果你 fork 了这个项目，改成你自己的仓库
    static let repository = "sunnyoung0211/ClipKeeper"
    /// 所有版本的发布页面
    static let releasesPageURL = URL(string: "https://github.com/\(repository)/releases")!

    enum State: Equatable {
        case idle                   // 还没检查
        case checking               // 正在检查
        case upToDate               // 已是最新版本
        case available(Release)     // 发现新版本
        case downloading(Double)    // 正在下载，进度 0 ~ 1
        case installing             // 正在安装
        case failed(String)         // 出错了，附带原因
    }

    /// GitHub 上的一个版本
    struct Release: Equatable {
        let version: String         // 比如 "0.1.2"（去掉了标签前面的 "v"）
        let pageURL: URL            // 这个版本的发布页面（更新说明）
        let dmgURL: URL?            // DMG 安装包的下载地址
        let dmgSize: Int
        let dmgSHA256: String?      // GitHub 提供的安装包校验值
    }

    private(set) var state: State = .idle
    /// 最近一次查到的新版本（安装失败后可以重试，也可以打开它的发布页面）
    private(set) var latestRelease: Release?
    /// 上次成功检查更新的时间
    private(set) var lastCheckDate = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    /// 设置窗口打开时，要不要自动滚动到"更新"分组（点了菜单里的"发现新版本"时）
    var wantsReveal = false

    /// 自动检查的间隔：一天
    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "lastUpdateCheck"

    @ObservationIgnored private var installTask: Task<Void, Never>?
    @ObservationIgnored private var automaticCheckTimer: Timer?
    @ObservationIgnored private var isAutomaticCheckEnabled: () -> Bool = { false }

    /// 当前运行的版本号
    var currentVersion: String {
        #if DEBUG
        // 调试用：启动参数 `-UpdateFakeVersion 0.1.0` 可以假装自己是旧版本，用来测试更新流程
        if let fake = UserDefaults.standard.string(forKey: "UpdateFakeVersion") { return fake }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 正在检查、下载或安装时，不能再开始新的操作
    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    // MARK: - 检查更新

    /// 检查更新。
    /// - Parameter userInitiated: 是不是用户点了"检查更新"。后台自动检查失败时（比如没联网）不显示错误，
    ///   保持原来的状态，过一会儿再试
    func checkForUpdates(userInitiated: Bool = true) async {
        guard !isBusy else { return }
        let previousState = state
        let previousRelease = latestRelease
        state = .checking
        latestRelease = nil
        do {
            let release = try await fetchLatestRelease()
            lastCheckDate = .now
            if !AppModel.isDemoMode {   // 演示模式不改动真实的设置
                UserDefaults.standard.set(lastCheckDate, forKey: Self.lastCheckKey)
            }
            if Self.isVersion(release.version, newerThan: currentVersion) {
                latestRelease = release
                state = .available(release)
            } else {
                state = .upToDate
            }
        } catch {
            if userInitiated {
                state = .failed(Self.describe(error, while: "检查更新"))
            } else {
                state = previousState
                latestRelease = previousRelease
            }
        }
    }

    // MARK: - 自动检查

    /// 开始定时自动检查：启动 1 分钟后看一次，之后每小时看一次，距离上次检查满一天就在后台检查。
    /// - Parameter isEnabled: 当前是否开启了自动检查（读取设置）
    func startAutomaticChecks(isEnabled: @escaping () -> Bool) {
        isAutomaticCheckEnabled = isEnabled
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.checkIfDue()
        }
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        automaticCheckTimer = timer
    }

    /// 开启了自动检查、并且距离上次检查已经满一天时，在后台检查一次
    func checkIfDue() {
        guard isAutomaticCheckEnabled(), !isBusy else { return }
        if let lastCheckDate, Date.now.timeIntervalSince(lastCheckDate) < Self.automaticCheckInterval { return }
        Task { await checkForUpdates(userInitiated: false) }
    }

    /// 向 GitHub 查询最新的正式版本（不包括草稿和预览版）
    private func fetchLatestRelease() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200:      break
        case 404:      throw UpdateError.noRelease
        case 403, 429: throw UpdateError.rateLimited   // 没登录时每小时最多查询 60 次
        default:       throw UpdateError.badResponse
        }

        let info = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let dmg = info.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        let version = info.tagName.hasPrefix("v") ? String(info.tagName.dropFirst()) : info.tagName
        var sha256: String?
        if let digest = dmg?.digest, digest.hasPrefix("sha256:") {
            sha256 = String(digest.dropFirst("sha256:".count))
        }
        return Release(version: version, pageURL: info.htmlURL, dmgURL: dmg?.downloadURL,
                       dmgSize: dmg?.size ?? 0, dmgSHA256: sha256)
    }

    /// 比较版本号，比如 "0.1.10" 比 "0.1.9" 新，"1.0" 和 "1.0.0" 一样
    static func isVersion(_ version: String, newerThan other: String) -> Bool {
        let a = version.split(separator: ".").map { Int($0) ?? 0 }
        let b = other.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - 下载并安装

    /// 下载并安装最近查到的新版本
    func installUpdate() {
        guard let release = latestRelease, !isBusy else { return }
        installTask = Task { await install(release) }
    }

    /// 取消下载
    func cancel() {
        installTask?.cancel()
    }

    /// 出错后点"重试"：查到过新版本就重新安装，否则重新检查
    func retry() {
        if latestRelease != nil {
            installUpdate()
        } else {
            Task { await checkForUpdates() }
        }
    }

    private func install(_ release: Release) async {
        guard let dmgURL = release.dmgURL else {
            state = .failed("这个版本没有提供安装包，请前往发布页面手动下载")
            return
        }
        let appURL = Bundle.main.bundleURL
        if let problem = Self.installLocationProblem(appURL) {
            state = .failed(problem)
            return
        }
        let workFolder = FileManager.default.temporaryDirectory
            .appending(path: "ClipKeeperUpdate-\(UUID().uuidString)", directoryHint: .isDirectory)

        do {
            try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)

            state = .downloading(0)
            let dmg = try await download(dmgURL, expectedSize: release.dmgSize,
                                         to: workFolder.appending(path: "ClipKeeper.dmg"))
            try Task.checkCancellation()

            // 解压、检查这些步骤要运行命令行工具、读写文件，放到后台线程去做
            state = .installing
            let bundleID = Bundle.main.bundleIdentifier ?? ""
            let requiredSignature = Self.pinnedSignatureRequirement()
            let newApp = try await Task.detached(priority: .userInitiated) {
                try prepareNewApp(from: dmg, expectedSHA256: release.dmgSHA256, expectedVersion: release.version,
                                  bundleID: bundleID, requiredSignature: requiredSignature, replacing: appURL)
            }.value

            // 替换：把新版本"换"到当前应用的位置上
            _ = try FileManager.default.replaceItemAt(appURL, withItemAt: newApp)
            try? FileManager.default.removeItem(at: newApp.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: workFolder)

            // 打开新版本。必须要求"新开一个"，否则系统会以为我们要打开的就是正在运行的这个
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            do {
                _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            } catch {
                state = .failed("新版本已经安装好了，但没能自动打开。请退出 ClipKeeper 后重新打开。")
                return
            }
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: workFolder)
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                state = .available(release)      // 用户取消了下载，回到"发现新版本"
            } else {
                state = .failed(Self.describe(error, while: "安装更新"))
            }
        }
    }

    /// 下载文件，同时刷新进度条
    private func download(_ url: URL, expectedSize: Int, to destination: URL) async throws -> URL {
        let tracker = DownloadTracker()
        // 每 0.1 秒读一次下载进度
        let progressTask = Task { [weak self] in
            while !Task.isCancelled {
                if case .downloading = self?.state {
                    self?.state = .downloading(tracker.fractionCompleted(expectedSize: expectedSize))
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        defer { progressTask.cancel() }

        let (tempURL, response) = try await URLSession.shared.download(from: url, delegate: tracker)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.badResponse }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    /// 检查当前位置能不能直接替换成新版本。不能时返回原因
    private static func installLocationProblem(_ appURL: URL) -> String? {
        // 从"下载"文件夹直接打开、没拖进"应用程序"的应用，系统会把它放到一个只读的临时位置运行
        if appURL.path.contains("/AppTranslocation/") {
            return "ClipKeeper 正在从临时位置运行，请先把它拖到「应用程序」文件夹，重新打开后再更新"
        }
        let folder = appURL.deletingLastPathComponent().path
        if !FileManager.default.isWritableFile(atPath: folder) || !FileManager.default.isWritableFile(atPath: appURL.path) {
            return "没有权限替换「\(folder)」里的 ClipKeeper，请前往发布页面手动下载安装"
        }
        return nil
    }

    /// 当前应用用的是"固定签名"（自签名证书）时，返回它的"签名要求"，新版本必须满足同样的要求。
    /// 用临时签名或开发证书签名时返回 nil：这两种情况下新版本的签名本来就会不一样，没法做这个检查。
    private static func pinnedSignatureRequirement() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return nil }
        // 自签名证书的签名要求是"认准这一张证书"，形如：identifier "…" and certificate leaf = H"证书指纹"
        let string = text as String
        return string.contains("certificate leaf = H\"") ? string : nil
    }

    /// 把错误转成用户看得懂的说明
    private static func describe(_ error: Error, while action: String) -> String {
        if let error = error as? UpdateError { return error.message }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "网络没有连接，请检查网络后重试"
            case .timedOut, .cannotConnectToHost, .cannotFindHost:
                return "连接 GitHub 失败，请稍后重试"
            default:
                break
            }
        }
        return "\(action)失败：\(error.localizedDescription)"
    }
}

// MARK: - 错误

nonisolated private enum UpdateError: Error {
    case noRelease
    case rateLimited
    case badResponse
    case checksumMismatch
    case signatureMismatch
    case invalidPackage(String)
    case commandFailed(String)

    var message: String {
        switch self {
        case .noRelease:               return "GitHub 上还没有发布任何版本"
        case .rateLimited:             return "检查得太频繁了，GitHub 暂时拒绝了请求，请过一会儿再试"
        case .badResponse:             return "GitHub 返回的数据不对，请稍后重试"
        case .checksumMismatch:        return "下载的安装包不完整或已被篡改（校验值不一致），请重试"
        case .signatureMismatch:       return "新版本的签名和当前版本不一致，为了安全没有安装。请前往发布页面确认后手动下载"
        case .invalidPackage(let why): return "安装包有问题：\(why)"
        case .commandFailed(let tool): return "安装时运行 \(tool) 失败，请重试，或前往发布页面手动下载"
        }
    }
}

// MARK: - GitHub 返回的数据格式

/// GitHub「获取最新版本」接口返回的 JSON（只取用得到的字段）
nonisolated private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let size: Int
        let downloadURL: URL
        let digest: String?         // 比如 "sha256:5a194d…"

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case downloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

// MARK: - 下载进度

/// 下载时记下 URLSession 创建的任务，用来读取已经下载了多少。
/// URLSession 会在后台线程调用它，所以标记为 nonisolated，并用锁保护数据。
nonisolated private final class DownloadTracker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.withLock { self.task = task }
    }

    func fractionCompleted(expectedSize: Int) -> Double {
        guard let task = lock.withLock({ self.task }) else { return 0 }
        let total = task.countOfBytesExpectedToReceive > 0 ? task.countOfBytesExpectedToReceive : Int64(expectedSize)
        guard total > 0 else { return 0 }
        return min(Double(task.countOfBytesReceived) / Double(total), 1)
    }
}

// MARK: - 解压并检查新版本（在后台线程运行）

/// 从下载好的 DMG 里取出新版本的应用，检查无误后返回它的位置
nonisolated private func prepareNewApp(from dmg: URL, expectedSHA256: String?, expectedVersion: String,
                                       bundleID: String, requiredSignature: String?,
                                       replacing target: URL) throws -> URL {
    let fileManager = FileManager.default

    // 1. 核对校验值
    if let expectedSHA256 {
        let data = try Data(contentsOf: dmg, options: .mappedIfSafe)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expectedSHA256.lowercased() else { throw UpdateError.checksumMismatch }
    }

    // 2. 挂载 DMG（-nobrowse：不在访达和桌面上显示这个磁盘）
    let mountPoint = dmg.deletingLastPathComponent().appending(path: "mount", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
    try runTool("/usr/bin/hdiutil", ["attach", dmg.path, "-mountpoint", mountPoint.path,
                                     "-nobrowse", "-readonly", "-noautoopen"])
    defer { try? runTool("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }

    // 3. 找到里面的应用，复制到和当前应用同一个磁盘上的临时文件夹（这样替换时能"瞬间换过去"）
    let contents = try fileManager.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
    guard let appInDMG = contents.first(where: { $0.pathExtension == "app" }) else {
        throw UpdateError.invalidPackage("里面没有找到应用")
    }
    let stagingFolder = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                            appropriateFor: target, create: true)
    let newApp = stagingFolder.appending(path: target.lastPathComponent, directoryHint: .isDirectory)
    try runTool("/usr/bin/ditto", [appInDMG.path, newApp.path])

    // 4. 检查：是不是 ClipKeeper、版本号对不对、代码签名是否完好（文件有没有被改动过）
    let infoPlist = newApp.appending(path: "Contents/Info.plist")
    let info = NSDictionary(contentsOf: infoPlist) as? [String: Any] ?? [:]
    guard info["CFBundleIdentifier"] as? String == bundleID else {
        throw UpdateError.invalidPackage("里面的应用不是 ClipKeeper")
    }
    guard info["CFBundleShortVersionString"] as? String == expectedVersion else {
        throw UpdateError.invalidPackage("版本号和发布的版本不一致")
    }
    try runTool("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
    if let requiredSignature {
        // -R：除了签名完好，还要满足当前版本的签名要求（也就是同一张证书签的）
        do {
            try runTool("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", "=" + requiredSignature, newApp.path])
        } catch {
            throw UpdateError.signatureMismatch
        }
    }

    // 5. 保险起见去掉"隔离"标记，免得打开时又被系统拦下
    try? runTool("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
    return newApp
}

/// 运行一个命令行工具并等它结束，失败时抛出错误
nonisolated private func runTool(_ path: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        print("\(path) 运行失败：\(output)")
        throw UpdateError.commandFailed((path as NSString).lastPathComponent)
    }
}
