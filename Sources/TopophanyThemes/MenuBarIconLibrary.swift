import Foundation
import ImageIO

/// Small decoded frames shared by the settings preview and the native layer.
public struct MenuBarIconAnimation: Sendable {
    public let id: String
    public let frames: [CGImage]
    public let durations: [Double]
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
        let width = height * min(2, max(0.75, aspectRatio))
        return CGSize(width: width.rounded(.up), height: height)
    }

    public static let deepseek: MenuBarIconAnimation? = {
        guard let open = Bundle.module.url(forResource: "deepseek-menu", withExtension: "png"),
              let blink = Bundle.module.url(forResource: "deepseek-blink", withExtension: "png"),
              let animation = try? MenuBarIconLibrary.decode([open, blink], frameRate: 12) else { return nil }
        return MenuBarIconAnimation(id: "deepseek", frames: animation.frames,
                                   durations: [4.66, 0.14])
    }()
}

public struct MenuBarIconAsset: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public let durations: [Double]
    public var isAnimated: Bool { durations.count > 1 }
}

public enum MenuBarIconError: Error, LocalizedError {
    case unsupported, tooLarge, tooManyFrames, mismatchedSizes, empty, missing, invalidName
    public var errorDescription: String? {
        switch self {
        case .unsupported: "Choose a PNG, JPEG, GIF, APNG, or a sequence of PNG frames."
        case .tooLarge: "Use images up to 4096 × 4096 pixels and 32 MB in total."
        case .tooManyFrames: "An icon can contain up to 180 frames."
        case .mismatchedSizes: "All PNG frames must have the same dimensions."
        case .empty: "The image is empty or could not be decoded."
        case .missing: "This custom icon is unavailable. The default icon is shown instead."
        case .invalidName: "Enter a name of up to 80 characters."
        }
    }
}

/// An app-owned library beside the settings file. Each immutable import is
/// a UUID directory of normalized PNG frames and a small manifest. The
/// user's originals are never modified and are no longer needed afterward.
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
              asset.durations.allSatisfy({ $0.isFinite && $0 >= 0.02 && $0 <= 10 }) else {
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
        return MenuBarIconAnimation(id: id, frames: frames, durations: asset.durations)
    }

    @discardableResult
    public func importFiles(_ urls: [URL], frameRate: Double = 12) throws -> MenuBarIconAsset {
        let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let decoded = try Self.decode(sorted, frameRate: frameRate)
        let id = UUID().uuidString
        let asset = MenuBarIconAsset(id: id, name: String((sorted[0].deletingPathExtension().lastPathComponent).prefix(80)),
                                    durations: decoded.durations)
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

    static func thumbnail(_ source: CGImageSource, index: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary)
    }

    static func decode(_ urls: [URL], frameRate: Double) throws -> MenuBarIconAnimation {
        guard !urls.isEmpty else { throw MenuBarIconError.empty }
        guard urls.count <= 180 else { throw MenuBarIconError.tooManyFrames }
        var frames: [CGImage] = [], durations: [Double] = []
        var bytes = 0, dimensions: CGSize?
        for url in urls {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            bytes += size
            guard bytes <= 32 * 1024 * 1024 else { throw MenuBarIconError.tooLarge }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let type = CGImageSourceGetType(source) as String?,
                  ["public.png", "public.jpeg", "com.compuserve.gif"].contains(type) else { throw MenuBarIconError.unsupported }
            let count = CGImageSourceGetCount(source)
            guard count > 0 else { throw MenuBarIconError.empty }
            guard frames.count + count <= 180 else { throw MenuBarIconError.tooManyFrames }
            if urls.count > 1 && (type != "public.png" || count != 1) { throw MenuBarIconError.unsupported }
            for index in 0..<count {
                guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                      let width = props[kCGImagePropertyPixelWidth] as? Int,
                      let height = props[kCGImagePropertyPixelHeight] as? Int else { throw MenuBarIconError.empty }
                guard width > 0, height > 0, width <= 4096, height <= 4096 else { throw MenuBarIconError.tooLarge }
                let next = CGSize(width: width, height: height)
                if let dimensions, dimensions != next { throw MenuBarIconError.mismatchedSizes }
                dimensions = next
                guard let image = thumbnail(source, index: index) else { throw MenuBarIconError.empty }
                frames.append(image)
                let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
                let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] ?? [:]
                let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] ?? gif[kCGImagePropertyGIFDelayTime]
                    ?? png[kCGImagePropertyAPNGUnclampedDelayTime] ?? png[kCGImagePropertyAPNGDelayTime]) as? Double
                let fallback = urls.count > 1 ? 1 / min(30, max(1, frameRate.isFinite ? frameRate : 12)) : 0.1
                let duration = delay.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? fallback
                durations.append(min(10, max(0.02, duration)))
            }
        }
        // One common alpha boundary avoids jitter between animation frames.
        let bounds = try frames.reduce(CGRect.null) { try $0.union(alphaBounds($1)) }
        guard !bounds.isNull else { throw MenuBarIconError.empty }
        let cropped = try frames.map { image in
            guard let crop = image.cropping(to: bounds) else { throw MenuBarIconError.empty }
            return crop
        }
        return MenuBarIconAnimation(id: "decoded", frames: cropped, durations: durations)
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
