import Foundation
import ImageIO
import Testing
import TopophanySections
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
        let animation = try #require(MenuBarIconAnimation.whiteNight())
        #expect(animation.frames.count == 180)
        #expect(abs(animation.duration - 24) < 0.001)
        let start = try #require(WhiteNightSky.frame(phase: 0)?.dataProvider?.data) as Data
        let end = try #require(WhiteNightSky.frame(phase: 1)?.dataProvider?.data) as Data
        let middle = try #require(WhiteNightSky.frame(phase: 0.5)?.dataProvider?.data) as Data
        #expect(start == end)
        #expect(start != middle)
        #expect(animation.size(height: 26).width == 80)
    }

    /// Each size keeps one dot to a pixel, in the same panorama.
    @Test func skyIsDrawnToEveryHeightsPixels() throws {
        for (height, width) in [(32, 104), (40, 130), (48, 156), (24, 78)] {
            let animation = try #require(MenuBarIconAnimation.whiteNight(pixelHeight: height))
            #expect(animation.frames[0].height == height)
            #expect(animation.frames[0].width == width)
            #expect(animation.overlays[.down]?.color.width == width)
        }
        #expect(try #require(MenuBarIconAnimation.whiteNight(pixelHeight: 48)).size(height: 26).width == 80)
        #expect(try #require(MenuBarIconAnimation.whiteNight(pixelHeight: 32)).size(height: 18).width == 54)
    }

    /// The moon shows every status itself, each its own shape: in color, and
    /// in ink for a quiet alert. The sky plays on beneath it.
    @Test func skyShowsEveryStatusWithItsMoon() throws {
        let animation = try #require(MenuBarIconAnimation.whiteNight())
        #expect(animation.showsStatuses)
        var moons: [Data] = []
        for mark in Mark.allCases {
            let scene = animation.scene(mark, tinted: true)
            #expect(scene.showsStatus)
            #expect(!scene.grayscale)
            #expect(scene.animation.frames.first === animation.frames.first)
            let color = try #require(scene.overlay?.dataProvider?.data) as Data
            let ink = try #require(animation.scene(mark, tinted: false).overlay?.dataProvider?.data) as Data
            #expect((color == ink) == (mark != .degraded && mark != .down))
            moons.append(color)
        }
        #expect(Set(moons).count == Mark.allCases.count)
        // A blood moon is red; quieted, it's the same disk in ink.
        func reds(_ image: CGImage?) throws -> Int {
            let pixels = try #require(WhiteNightSky.pixels(image, 156, 48))
            return stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0 + 3] == 255 && pixels[$0] > 150 && pixels[$0 + 1] < 80 }.count
        }
        #expect(try reds(animation.scene(.down, tinted: true).overlay) > 100)
        #expect(try reds(animation.scene(.down, tinted: false).overlay) == 0)
        #expect(try reds(animation.scene(.up, tinted: true).overlay) == 0)
    }

    /// A change dissolves the moon through its own dither: each step turns
    /// over more pixels, ending on the new moon itself.
    @Test func moonDissolvesThroughTheDither() throws {
        let animation = try #require(MenuBarIconAnimation.whiteNight())
        let up = try #require(animation.overlays[.up]?.color), down = try #require(animation.overlays[.down]?.color)
        let steps = MenuBarIconAnimation.dissolve(from: up, to: down)
        #expect(steps.count == 8)
        #expect(steps.last === down)
        let from = try #require(WhiteNightSky.pixels(up, 156, 48)), to = try #require(WhiteNightSky.pixels(down, 156, 48))
        var turned: [Int] = []
        for step in steps.dropLast() {
            let pixels = try #require(WhiteNightSky.pixels(step, 156, 48))
            let changed = stride(from: 0, to: pixels.count, by: 4).filter { from[$0..<$0 + 4] != to[$0..<$0 + 4] }
            #expect(changed.allSatisfy { pixels[$0..<$0 + 4] == from[$0..<$0 + 4] || pixels[$0..<$0 + 4] == to[$0..<$0 + 4] })
            turned.append(changed.filter { pixels[$0..<$0 + 4] == to[$0..<$0 + 4] }.count)
        }
        #expect(turned == turned.sorted())
        #expect(turned.first! < turned.last!)
        #expect(MenuBarIconAnimation.dissolve(from: nil, to: down).last === down)
        #expect(MenuBarIconAnimation.dissolve(from: up, to: nil).count == 7)
    }

    /// Files named for a status make a pack: each status plays its own
    /// frames and shows itself; one the pack lacks plays clear's frames
    /// beside the badge.
    @Test func statusPacksShowTheirStatuses() throws {
        try withLibrary { root, library in
            let pack = root.appending(path: "Cat pack")
            try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
            try write(pack.appending(path: "clear.png"), frames: [picture(blue: true)])
            try write(pack.appending(path: "Warning-2.png"), frames: [picture(blue: false)])
            try write(pack.appending(path: "warning-1.png"), frames: [picture(blue: true)])
            try write(pack.appending(path: "error.gif"), type: "com.compuserve.gif",
                      frames: [picture(blue: false), picture(blue: true)], delays: [0.2, 0.3])
            let asset = try library.importFiles(["error.gif", "clear.png", "warning-1.png", "Warning-2.png"].map { pack.appending(path: $0) })
            #expect(asset.name == "Cat pack")
            #expect(asset.shows == [.up, .degraded, .down])
            #expect(asset.isAnimated)
            let animation = try library.load(asset.id)
            #expect(animation.frames.count == 5)
            #expect(animation.showsStatuses)

            let clear = animation.scene(.up, tinted: true)
            #expect(clear.showsStatus)
            #expect(clear.animation.frames.count == 1)
            #expect(try rgba(clear.animation.frames[0])[2] > 240)
            let warning = animation.scene(.degraded, tinted: true)
            #expect(warning.animation.frames.count == 2)
            // Natural filename order: warning-1, then Warning-2.
            #expect(try rgba(warning.animation.frame(at: 0.05))[2] > 240)
            #expect(try rgba(warning.animation.frame(at: 0.12))[0] > 240)
            let error = animation.scene(.down, tinted: true)
            #expect(abs(error.animation.duration - 0.5) < 0.001)
            #expect(error.animation.id == asset.id + "#down")
            #expect(!error.grayscale)
            #expect(animation.scene(.down, tinted: false).grayscale)
            #expect(!animation.scene(.up, tinted: false).grayscale)

            // Unknown, which it lacks: clear's frames without their color,
            // beside the badge.
            let unknown = animation.scene(.unknown, tinted: true)
            #expect(!unknown.showsStatus)
            #expect(unknown.grayscale)
            #expect(unknown.animation.id == clear.animation.id)
        }
    }

    /// A folder holding folders named for each status is a pack, named for
    /// the folder; one of plain frames is a sequence.
    @Test func foldersImportAsPacksOrSequences() throws {
        try withLibrary { root, library in
            let pack = root.appending(path: "Moon")
            for (status, blue) in [("正常", true), ("error", false)] {
                let folder = pack.appending(path: status)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try write(folder.appending(path: "a.png"), frames: [picture(blue: blue)])
                try write(folder.appending(path: "b.png"), frames: [picture(blue: blue)])
            }
            try Data("notes".utf8).write(to: pack.appending(path: "README.txt"))
            let asset = try library.importFiles([pack])
            #expect(asset.name == "Moon")
            #expect(asset.shows == [.up, .down])
            let animation = try library.load(asset.id)
            #expect(try rgba(animation.scene(.down, tinted: true).animation.frames[1])[0] > 240)

            let frames = root.appending(path: "Frames")
            try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
            try write(frames.appending(path: "frame10.png"), frames: [picture(blue: true)])
            try write(frames.appending(path: "frame2.png"), frames: [picture(blue: false)])
            let sequence = try library.importFiles([frames])
            #expect(sequence.name == "Frames")
            #expect(sequence.statuses == nil)
            let played = try library.load(sequence.id)
            #expect(!played.showsStatuses)
            #expect(try rgba(played.frames[0])[0] > 240)
            #expect(!played.scene(.down, tinted: true).showsStatus)
        }
    }

    @Test func statusNamesAreWholeWords() {
        #expect(MenuBarIconLibrary.status(named: "clear") == .up)
        #expect(MenuBarIconLibrary.status(named: "Warning_03") == .degraded)
        #expect(MenuBarIconLibrary.status(named: "error-frame") == .down)
        #expect(MenuBarIconLibrary.status(named: "オフライン2") == .offline)
        #expect(MenuBarIconLibrary.status(named: "cleared") == nil)
        #expect(MenuBarIconLibrary.status(named: "frame-error") == nil)
        #expect(MenuBarIconLibrary.status(named: "01-clear") == nil)
    }

    /// Every file of a pack must say its status, and a pack's statuses
    /// share one size and the frame limit.
    @Test func packsRefuseUnnamedFilesAndMixedSizes() throws {
        try withLibrary { root, library in
            let clear = root.appending(path: "clear.png"), mascot = root.appending(path: "mascot.png")
            try write(clear, frames: [picture(blue: true)])
            try write(mascot, frames: [picture(blue: false)])
            #expect(throws: MenuBarIconError.unnamedStatus) { try library.importFiles([clear, mascot]) }
            let error = root.appending(path: "error.png")
            try write(error, frames: [picture(blue: false, size: 64)])
            #expect(throws: MenuBarIconError.mismatchedSizes) { try library.importFiles([clear, error]) }
            #expect(throws: MenuBarIconError.noClearStatus) { try library.importFiles([error]) }
            #expect(library.list().isEmpty)
        }
    }

    /// A manifest whose statuses reach past its frames is unavailable, not
    /// played from the wrong frames.
    @Test func damagedPackManifestsAreUnavailable() throws {
        try withLibrary { root, library in
            let clear = root.appending(path: "clear.png"), error = root.appending(path: "error.png")
            try write(clear, frames: [picture(blue: true)])
            try write(error, frames: [picture(blue: false)])
            let asset = try library.importFiles([clear, error])
            let manifest = library.directory.appending(path: asset.id).appending(path: "icon.json")
            var damaged = asset
            damaged.statuses = ["up": [0, 1], "down": [1, 4]]
            try JSONEncoder().encode(damaged).write(to: manifest)
            #expect(throws: (any Error).self) { try library.load(asset.id) }
            #expect(library.list().isEmpty)
            damaged.statuses = ["down": [1, 1]]
            try JSONEncoder().encode(damaged).write(to: manifest)
            #expect(throws: (any Error).self) { try library.load(asset.id) }
            damaged.statuses = ["up": [0, 1], "down": [1, 1], "eclipse": [0, 9]]
            try JSONEncoder().encode(damaged).write(to: manifest)
            #expect(try library.load(asset.id).statuses.count == 2)
        }
    }
}
