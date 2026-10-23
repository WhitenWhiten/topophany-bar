import Foundation
import ImageIO
import TopophanySections

/// Small decoded frames shared by the settings preview and the native layer.
///
/// An icon can show the status itself: a status pack plays its own frames
/// for each status it has, and White Night draws its moon over the sky.
/// For any other status it plays its own frames, with the badge beside it;
/// a pack's are its clear frames, without their color, so they don't say
/// all is well.
public struct MenuBarIconAnimation: Sendable {
    public let id: String
    public let frames: [CGImage]
    public let durations: [Double]
    /// A status pack's frames for each status it shows, by mark: where they
    /// are among `frames`. A pack always has clear's.
    public var statuses: [Mark: Range<Int>] = [:]
    /// Drawn still over every frame, for each status the icon shows that
    /// way: White Night's moon.
    public var overlays: [Mark: Overlay] = [:]

    public struct Overlay: Sendable {
        public var color: CGImage
        /// Without color, for a quiet alert or with status colors off: its
        /// shape still says which status it is.
        public var ink: CGImage
    }

    public var duration: Double { durations.reduce(0, +) }
    public var aspectRatio: Double { Double(frames[0].width) / Double(frames[0].height) }
    public var keyTimes: [NSNumber] {
        var elapsed = 0.0
        return durations.map { delay in
            defer { elapsed += delay }
            return NSNumber(value: elapsed / duration)
        } + [1]
    }

    public func frame(at time: Double) -> CGImage {
        var remainder = max(0, time).truncatingRemainder(dividingBy: duration)
        for (index, delay) in durations.enumerated() {
            if remainder < delay { return frames[index] }
            remainder -= delay
        }
        return frames[0]
    }

    public func size(height: Double) -> CGSize {
        // Reserve the full panorama width, including the one-point inset on each side.
        // Extreme panoramas still fit proportionally inside a six-to-one slot.
        let width = (height - 2) * min(6, max(0.75, aspectRatio)) + 2
        return CGSize(width: width.rounded(.up), height: height)
    }

    /// Whether it shows any status itself.
    public var showsStatuses: Bool { !statuses.isEmpty || !overlays.isEmpty }

    /// What it shows for `mark`; `tinted` is false while the alert is quiet
    /// or status colors are off.
    public func scene(_ mark: Mark, tinted: Bool) -> MenuBarIconScene {
        if let overlay = overlays[mark] {
            return MenuBarIconScene(animation: base, overlay: tinted ? overlay.color : overlay.ink, showsStatus: true)
        }
        if let range = statuses[mark] {
            // A pack's art carries its own colors: an alert's loses them
            // as the badge would.
            return MenuBarIconScene(animation: part(range, mark), showsStatus: true,
                                    grayscale: !tinted && (mark == .degraded || mark == .down))
        }
        return MenuBarIconScene(animation: base, grayscale: !statuses.isEmpty)
    }

    /// What plays for a status it doesn't show: a pack's clear frames, or
    /// else all its own.
    var base: MenuBarIconAnimation {
        statuses[.up].map { part($0, .up) } ?? MenuBarIconAnimation(id: id, frames: frames, durations: durations)
    }

    private func part(_ range: Range<Int>, _ mark: Mark) -> MenuBarIconAnimation {
        MenuBarIconAnimation(id: id + "#" + mark.rawValue, frames: Array(frames[range]), durations: Array(durations[range]))
    }

    public static let deepseek: MenuBarIconAnimation? = {
        guard let open = Bundle.module.url(forResource: "deepseek-menu", withExtension: "png"),
              let blink = Bundle.module.url(forResource: "deepseek-blink", withExtension: "png"),
              let animation = try? MenuBarIconLibrary.decode([open, blink], frameRate: 12) else { return nil }
        return MenuBarIconAnimation(id: "deepseek", frames: animation.frames,
                                   durations: [4.66, 0.14])
    }()
}

/// What a menu bar icon shows for one status: the frames it plays, and
/// what it draws over them.
public struct MenuBarIconScene: Sendable {
    public var animation: MenuBarIconAnimation
    /// Drawn still over every frame.
    public var overlay: CGImage?
    /// The icon shows the status itself, so no badge is drawn beside it.
    public var showsStatus: Bool
    /// Its frames drawn without color: an alert quieted, or status colors
    /// off.
    public var grayscale: Bool

    public init(animation: MenuBarIconAnimation, overlay: CGImage? = nil, showsStatus: Bool = false, grayscale: Bool = false) {
        self.animation = animation
        self.overlay = overlay
        self.showsStatus = showsStatus
        self.grayscale = grayscale
    }
}

public struct MenuBarIconAsset: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public let durations: [Double]
    /// A status pack's frames for each status it shows, by mark: the index
    /// of the first and how many.
    public var statuses: [String: [Int]]?

    public var isAnimated: Bool {
        guard let ranges = ranges, !ranges.isEmpty else { return durations.count > 1 }
        return ranges.values.contains { $0.count > 1 }
    }

    /// The statuses it shows itself, in their order.
    public var shows: [Mark] { Mark.allCases.filter { ranges?[$0] != nil } }

    /// Its statuses' frames by mark, each among its frames; `nil` when one
    /// isn't, or a pack has no clear frames. A mark this app doesn't know
    /// is left out.
    var ranges: [Mark: Range<Int>]? {
        var out: [Mark: Range<Int>] = [:]
        for (key, span) in statuses ?? [:] {
            guard let mark = Mark(rawValue: key) else { continue }
            guard span.count == 2, span[0] >= 0, span[1] > 0, span[0] + span[1] <= durations.count else { return nil }
            out[mark] = span[0]..<span[0] + span[1]
        }
        return out.isEmpty || out[.up] != nil ? out : nil
    }
}

public enum MenuBarIconError: Error, LocalizedError {
    case unsupported, tooLarge, tooManyFrames, mismatchedSizes, empty, missing, invalidName, unnamedStatus, noClearStatus
    public var errorDescription: String? {
        switch self {
        case .unsupported: "Choose a PNG, JPEG, GIF, APNG, or a sequence of PNG frames."
        case .tooLarge: "Use images up to 4096 × 4096 pixels and 32 MB in total."
        case .tooManyFrames: "An icon can contain up to 180 frames."
        case .mismatchedSizes: "All PNG frames must have the same dimensions."
        case .empty: "The image is empty or could not be decoded."
        case .missing: "This custom icon is unavailable. The default icon is shown instead."
        case .invalidName: "Enter a name of up to 80 characters."
        case .unnamedStatus: "Name every file or folder of a status icon for its status: clear, warning, error, unknown or offline."
        case .noClearStatus: "A status icon needs frames named clear, for when all is well."
        }
    }
}

/// An app-owned library beside the settings file. Each immutable import is
/// a UUID directory of normalized PNG frames and a small manifest. The
/// user's originals are never modified and are no longer needed afterward.
///
/// Files or folders named for a status ("clear.gif", "error/") make a
/// status pack: its frames for each status show the status themselves.
public struct MenuBarIconLibrary: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    private func folder(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw MenuBarIconError.missing }
        return directory.appending(path: id, directoryHint: .isDirectory)
    }

    private func manifest(_ id: String) throws -> MenuBarIconAsset {
        let url = try folder(id).appending(path: "icon.json")
        guard let data = try? Data(contentsOf: url), data.count < 64_000,
              let asset = try? JSONDecoder().decode(MenuBarIconAsset.self, from: data),
              asset.id == id, !asset.durations.isEmpty, asset.durations.count <= 180,
              asset.durations.allSatisfy({ $0.isFinite && $0 >= 0.02 && $0 <= 10 }), asset.ranges != nil else {
            throw MenuBarIconError.missing
        }
        return asset
    }

    public func list() -> [MenuBarIconAsset] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { try? manifest($0.lastPathComponent) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func load(_ id: String) throws -> MenuBarIconAnimation {
        let asset = try manifest(id)
        let root = try folder(id)
        let frames = try asset.durations.indices.map { index -> CGImage in
            let url = root.appending(path: "frame-\(index).png")
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = Self.thumbnail(source, index: 0) else { throw MenuBarIconError.missing }
            return image
        }
        return MenuBarIconAnimation(id: id, frames: frames, durations: asset.durations, statuses: asset.ranges ?? [:])
    }

    @discardableResult
    public func importFiles(_ urls: [URL], frameRate: Double = 12) throws -> MenuBarIconAsset {
        guard !urls.isEmpty else { throw MenuBarIconError.empty }
        let chosen = Self.files(urls)
        let named = chosen.filter { $0.status != nil }
        let decoded: MenuBarIconAnimation
        let name: String
        if named.isEmpty {
            let sorted = chosen.map(\.url).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            guard let first = sorted.first else { throw MenuBarIconError.empty }
            decoded = try Self.decode(sorted, frameRate: frameRate)
            name = urls.count == 1 && Self.isFolder(urls[0]) ? urls[0].lastPathComponent : first.deletingPathExtension().lastPathComponent
        } else {
            guard named.count == chosen.count else { throw MenuBarIconError.unnamedStatus }
            decoded = try Self.decodePack(Dictionary(grouping: named.map { ($0.status!, $0.url) }, by: \.0).mapValues { $0.map(\.1) },
                                          frameRate: frameRate)
            name = Self.packName(urls)
        }
        let id = UUID().uuidString
        let statuses = decoded.statuses.isEmpty ? nil
            : Dictionary(uniqueKeysWithValues: decoded.statuses.map { ($0.key.rawValue, [$0.value.lowerBound, $0.value.count]) })
        let asset = MenuBarIconAsset(id: id, name: String(name.prefix(80)), durations: decoded.durations, statuses: statuses)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appending(path: ".import-\(id)", directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        for (index, frame) in decoded.frames.enumerated() {
            let url = staging.appending(path: "frame-\(index).png")
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
                throw MenuBarIconError.empty
            }
            CGImageDestinationAddImage(dest, frame, nil)
            guard CGImageDestinationFinalize(dest) else { throw MenuBarIconError.empty }
        }
        try JSONEncoder().encode(asset).write(to: staging.appending(path: "icon.json"), options: .atomic)
        try fm.moveItem(at: staging, to: folder(id))
        return asset
    }

    public func rename(_ id: String, to name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { throw MenuBarIconError.invalidName }
        var asset = try manifest(id)
        asset.name = name
        try JSONEncoder().encode(asset).write(to: folder(id).appending(path: "icon.json"), options: .atomic)
    }

    public func remove(_ id: String) throws { try FileManager.default.removeItem(at: folder(id)) }

    // MARK: status packs

    /// The words a file or folder can be named for each status by, in the
    /// app's three languages.
    static let statusNames: [(Mark, [String])] = [
        (.up, ["clear", "up", "ok", "normal", "healthy", "正常"]),
        (.degraded, ["warning", "warnings", "warn", "degraded", "警告", "注意"]),
        (.down, ["error", "errors", "down", "incident", "incidents", "critical", "fail", "failure", "故障", "错误", "エラー", "障害"]),
        (.unknown, ["unknown", "incomplete", "未知", "不明"]),
        (.offline, ["offline", "离线", "オフライン"]),
    ]

    /// The status a name begins with, as a word of its own: "clear",
    /// "warning-02", "error_3"; `nil` for "frame1" or "cleared".
    static func status(named name: String) -> Mark? {
        let word = String(name.lowercased().prefix { $0.isLetter })
        return statusNames.first { $0.1.contains(word) }?.0
    }

    static let imageExtensions: Set<String> = ["png", "apng", "gif", "jpg", "jpeg"]

    static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    /// Each file chosen, with the status its name or its folder's is for. A
    /// folder is read one level down: its images, and the images in its
    /// folders named for a status.
    static func files(_ urls: [URL]) -> [(url: URL, status: Mark?)] {
        func items(_ folder: URL) -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                           options: [.skipsHiddenFiles])) ?? [])
        }
        func images(_ folder: URL) -> [URL] {
            items(folder).filter { !isFolder($0) && imageExtensions.contains($0.pathExtension.lowercased()) }
        }
        var out: [(url: URL, status: Mark?)] = []
        for url in urls {
            guard isFolder(url) else {
                out.append((url, status(named: url.deletingPathExtension().lastPathComponent)))
                continue
            }
            if let named = status(named: url.lastPathComponent) {
                out += images(url).map { ($0, named) }
                continue
            }
            for item in items(url) {
                if isFolder(item) {
                    if let named = status(named: item.lastPathComponent) { out += images(item).map { ($0, named) } }
                } else if imageExtensions.contains(item.pathExtension.lowercased()) {
                    out.append((item, status(named: item.deletingPathExtension().lastPathComponent)))
                }
            }
        }
        return out
    }

    /// A pack is named for the folder that holds it.
    static func packName(_ urls: [URL]) -> String {
        var folder = urls.count == 1 && isFolder(urls[0]) ? urls[0] : urls[0].deletingLastPathComponent()
        if status(named: folder.lastPathComponent) != nil { folder.deleteLastPathComponent() }
        let name = folder.lastPathComponent
        return name.isEmpty || name == "/" ? "Status icon" : name
    }

    /// Each status's files, in natural filename order, as frames of one
    /// size that share one boundary, so the icon holds still as its status
    /// changes.
    static func decodePack(_ groups: [Mark: [URL]], frameRate: Double) throws -> MenuBarIconAnimation {
        guard groups[.up] != nil else { throw MenuBarIconError.noClearStatus }
        var reader = FrameReader()
        var frames: [CGImage] = [], durations: [Double] = [], statuses: [Mark: Range<Int>] = [:]
        for mark in Mark.allCases {
            guard let urls = groups[mark] else { continue }
            let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let read = try reader.read(sorted, frameRate: frameRate)
            statuses[mark] = frames.count..<frames.count + read.frames.count
            frames += read.frames
            durations += read.durations
        }
        return MenuBarIconAnimation(id: "decoded", frames: try cropped(frames), durations: durations, statuses: statuses)
    }

    // MARK: decoding

    static func thumbnail(_ source: CGImageSource, index: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 384,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary)
    }

    static func decode(_ urls: [URL], frameRate: Double) throws -> MenuBarIconAnimation {
        var reader = FrameReader()
        let read = try reader.read(urls, frameRate: frameRate)
        return MenuBarIconAnimation(id: "decoded", frames: try cropped(read.frames), durations: read.durations)
    }

    /// Reads frames within an import's limits, which a pack's statuses
    /// share: 32 MB and 180 frames in all, each frame the same size.
    struct FrameReader {
        var bytes = 0
        var count = 0
        var dimensions: CGSize?

        mutating func read(_ urls: [URL], frameRate: Double) throws -> (frames: [CGImage], durations: [Double]) {
            guard !urls.isEmpty else { throw MenuBarIconError.empty }
            guard count + urls.count <= 180 else { throw MenuBarIconError.tooManyFrames }
            var frames: [CGImage] = [], durations: [Double] = []
            for url in urls {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                bytes += size
                guard bytes <= 32 * 1024 * 1024 else { throw MenuBarIconError.tooLarge }
                guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let type = CGImageSourceGetType(source) as String?,
                      ["public.png", "public.jpeg", "com.compuserve.gif"].contains(type) else { throw MenuBarIconError.unsupported }
                let n = CGImageSourceGetCount(source)
                guard n > 0 else { throw MenuBarIconError.empty }
                guard count + n <= 180 else { throw MenuBarIconError.tooManyFrames }
                if urls.count > 1 && (type != "public.png" || n != 1) { throw MenuBarIconError.unsupported }
                for index in 0..<n {
                    guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                          let width = props[kCGImagePropertyPixelWidth] as? Int,
                          let height = props[kCGImagePropertyPixelHeight] as? Int else { throw MenuBarIconError.empty }
                    guard width > 0, height > 0, width <= 4096, height <= 4096 else { throw MenuBarIconError.tooLarge }
                    let next = CGSize(width: width, height: height)
                    if let dimensions, dimensions != next { throw MenuBarIconError.mismatchedSizes }
                    dimensions = next
                    guard let image = MenuBarIconLibrary.thumbnail(source, index: index) else { throw MenuBarIconError.empty }
                    frames.append(image)
                    count += 1
                    let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
                    let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] ?? [:]
                    let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] ?? gif[kCGImagePropertyGIFDelayTime]
                        ?? png[kCGImagePropertyAPNGUnclampedDelayTime] ?? png[kCGImagePropertyAPNGDelayTime]) as? Double
                    let fallback = urls.count > 1 ? 1 / min(30, max(1, frameRate.isFinite ? frameRate : 12)) : 0.1
                    let duration = delay.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? fallback
                    durations.append(min(10, max(0.02, duration)))
                }
            }
            return (frames, durations)
        }
    }

    /// Every frame cropped to one common alpha boundary, which avoids
    /// jitter between frames.
    static func cropped(_ frames: [CGImage]) throws -> [CGImage] {
        let bounds = try frames.reduce(CGRect.null) { try $0.union(alphaBounds($1)) }
        guard !bounds.isNull else { throw MenuBarIconError.empty }
        return try frames.map { image in
            guard let crop = image.cropping(to: bounds) else { throw MenuBarIconError.empty }
            return crop
        }
    }

    private static func alphaBounds(_ image: CGImage) throws -> CGRect {
        let w = image.width, h = image.height
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data?.assumingMemoryBound(to: UInt8.self) else { throw MenuBarIconError.empty }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var x0 = w, y0 = h, x1 = -1, y1 = -1
        for y in 0..<h { for x in 0..<w where data[(y * w + x) * 4 + 3] > 8 {
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        } }
        guard x1 >= x0, y1 >= y0 else { return .null }
        return CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
    }
}
