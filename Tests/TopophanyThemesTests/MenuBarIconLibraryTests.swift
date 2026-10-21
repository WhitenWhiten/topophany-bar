import Foundation
import ImageIO
import Testing
@testable import TopophanyThemes

struct MenuBarIconLibraryTests {
    func withLibrary(_ body: (URL, MenuBarIconLibrary) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root, MenuBarIconLibrary(directory: root.appending(path: "library")))
    }

    func picture(blue: Bool, size: Int = 32, transparent: Bool = false) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        if !transparent {
            context.setFillColor(CGColor(red: blue ? 0 : 1, green: 0, blue: blue ? 1 : 0, alpha: 1))
            context.fill(CGRect(x: size / 4, y: size / 8, width: size / 2, height: size / 2))
        }
        return try #require(context.makeImage())
    }

    func write(_ url: URL, type: String = "public.png", frames: [CGImage], delays: [Double] = []) throws {
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, frames.count, nil))
        for (index, frame) in frames.enumerated() {
            var properties: [CFString: Any] = [:]
            if !delays.isEmpty {
                if type == "com.compuserve.gif" {
                    properties[kCGImagePropertyGIFDictionary] = [kCGImagePropertyGIFDelayTime: delays[index]]
                } else {
                    properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyAPNGDelayTime: delays[index]]
                }
            }
            CGImageDestinationAddImage(dest, frame, properties as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(dest))
    }

    func rgba(_ image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: data, count: 4))
    }

    @Test func importsSurviveOriginalRemovalAndCanBeManaged() throws {
        try withLibrary { root, library in
            let url = root.appending(path: "My mascot.png")
            try write(url, frames: [picture(blue: true)])
            let asset = try library.importFiles([url])
            try FileManager.default.removeItem(at: url)
            let animation = try library.load(asset.id)
            #expect(animation.frames.count == 1)
            #expect(try rgba(animation.frames[0])[3] > 240) // padding trimmed, including the off-center top margin
            #expect(try rgba(animation.frames[0])[2] > 240)
            try library.rename(asset.id, to: "  My blue icon  ")
            #expect(library.list().first?.name == "My blue icon")
            try library.remove(asset.id)
            #expect(library.list().isEmpty)
            #expect(throws: (any Error).self) { try library.load(asset.id) }
            #expect(throws: (any Error).self) { try library.remove("../") }
        }
    }

    @Test func sequencesUseNaturalFilenameOrderAndFrameRate() throws {
        try withLibrary { root, library in
            let red = root.appending(path: "frame2.png"), blue = root.appending(path: "frame10.png")
            try write(red, frames: [picture(blue: false)])
            try write(blue, frames: [picture(blue: true)])
            let asset = try library.importFiles([blue, red], frameRate: 10)
            let animation = try library.load(asset.id)
            #expect(animation.durations == [0.1, 0.1])
            #expect(try rgba(animation.frame(at: 0.05))[0] > 240)
            #expect(try rgba(animation.frame(at: 0.15))[2] > 240)
            #expect(try rgba(animation.frame(at: 0.25))[0] > 240)
        }
    }

    @Test func jpegCanBeImportedAsAStillImage() throws {
        try withLibrary { root, library in
            let url = root.appending(path: "photo.jpg")
            try write(url, type: "public.jpeg", frames: [picture(blue: true)])
            let asset = try library.importFiles([url])
            let animation = try library.load(asset.id)
            #expect(animation.frames.count == 1)
            #expect(!asset.isAnimated)
        }
    }

    @Test func gifAndAPNGPreserveFrameDelays() throws {
        try withLibrary { root, library in
            for (type, ext) in [("com.compuserve.gif", "gif"), ("public.png", "apng")] {
                let url = root.appending(path: "animated.\(ext)")
                try write(url, type: type, frames: [picture(blue: false), picture(blue: true)], delays: [0.1, 0.3])
                let asset = try library.importFiles([url])
                let animation = try library.load(asset.id)
                #expect(animation.frames.count == 2)
                #expect(abs(animation.duration - 0.4) < 0.001)
                #expect(try rgba(animation.frame(at: 0.05))[0] > 240)
                #expect(try rgba(animation.frame(at: 0.2))[2] > 240)
            }
        }
    }

    @Test func badImportsLeaveNoPartialLibraryEntry() throws {
        try withLibrary { root, library in
            let invalid = root.appending(path: "invalid.png")
            try Data("not an image".utf8).write(to: invalid)
            #expect(throws: (any Error).self) { try library.importFiles([invalid]) }
            let empty = root.appending(path: "empty.png")
            try write(empty, frames: [picture(blue: true, transparent: true)])
            #expect(throws: (any Error).self) { try library.importFiles([empty]) }
            let small = root.appending(path: "small.png"), large = root.appending(path: "large.png")
            try write(small, frames: [picture(blue: true)])
            try write(large, frames: [picture(blue: true, size: 64)])
            #expect(throws: (any Error).self) { try library.importFiles([small, large]) }
            #expect(throws: (any Error).self) { try library.importFiles(Array(repeating: small, count: 181)) }
            #expect(library.list().isEmpty)
        }
    }

    @Test func builtInBlinkKeepsConsistentGeometry() throws {
        let animation = try #require(MenuBarIconAnimation.deepseek)
        #expect(animation.frames.count == 2)
        #expect(animation.frames[0].width == animation.frames[1].width)
        #expect(animation.frames[0].height == animation.frames[1].height)
        #expect(animation.frame(at: 0) === animation.frames[0])
        #expect(animation.frame(at: 4.7) === animation.frames[1])
        #expect(animation.frame(at: 4.81) === animation.frames[0])
    }

    @Test func wideImportsKeepTheirResolutionAndLayoutAfterReload() throws {
        try withLibrary { root, library in
            let context = try #require(CGContext(data: nil, width: 312, height: 96, bitsPerComponent: 8,
                                                bytesPerRow: 312 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 312, height: 96))
            let image = try #require(context.makeImage())
            let url = root.appending(path: "panorama.apng")
            try write(url, frames: [image, image], delays: [0.1, 0.2])
            let asset = try library.importFiles([url])
            let animation = try library.load(asset.id)
            #expect(animation.aspectRatio == 3.25)
            #expect(animation.frames[0].width >= 156)
            #expect(animation.frames[0].height >= 48)
            #expect(animation.size(height: 26) == CGSize(width: 80, height: 26))
            #expect(animation.durations.count == 2)
        }
    }

    @Test func skyIsAnimatedAndClosesWithoutAJump() throws {
        let animation = try #require(MenuBarIconAnimation.whiteNight)
        #expect(animation.frames.count == 180)
        #expect(abs(animation.duration - 24) < 0.001)
        let start = try #require(WhiteNightSky.frame(phase: 0)?.dataProvider?.data) as Data
        let end = try #require(WhiteNightSky.frame(phase: 1)?.dataProvider?.data) as Data
        let middle = try #require(WhiteNightSky.frame(phase: 0.5)?.dataProvider?.data) as Data
        #expect(start == end)
        #expect(start != middle)
        #expect(animation.size(height: 26).width == 80)
    }
}
