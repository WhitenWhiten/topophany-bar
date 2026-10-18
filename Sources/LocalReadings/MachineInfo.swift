import Foundation
#if canImport(IOKit)
import IOKit
#endif

/// What this Mac is: its marketing name and chip.
public struct MachineInfo: Sendable, Hashable {
    /// The marketing name without its year and size, such as "MacBook Pro".
    public var model: String
    /// Such as "Apple M4 Pro".
    public var chip: String
    public var hasBattery: Bool

    public init(model: String, chip: String, hasBattery: Bool) {
        self.model = model
        self.chip = chip
        self.hasBattery = hasBattery
    }

    public static func current() -> MachineInfo {
        let model = productName().map(trimmed) ?? SysctlValue.string("hw.model").map(familyName) ?? "Mac"
        let chip = SysctlValue.string("machdep.cpu.brand_string") ?? ""
        return MachineInfo(model: model, chip: chip, hasBattery: BatterySampler.present)
    }

    /// "MacBook Pro (14-inch, Nov 2024)" reads as "MacBook Pro".
    static func trimmed(_ name: String) -> String {
        let base = name.split(separator: "(", maxSplits: 1).first.map(String.init) ?? name
        let t = base.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? name : t
    }

    /// A family name from a model identifier, such as `MacBookPro18,3`.
    static func familyName(_ id: String) -> String {
        let families: [(String, String)] = [
            ("MacBookPro", "MacBook Pro"), ("MacBookAir", "MacBook Air"), ("MacBook", "MacBook"),
            ("Macmini", "Mac mini"), ("MacPro", "Mac Pro"), ("iMacPro", "iMac Pro"), ("iMac", "iMac"),
        ]
        for (prefix, name) in families where id.hasPrefix(prefix) { return name }
        return "Mac"
    }

    static func productName() -> String? {
        #if canImport(IOKit)
        for (path, key) in [("IODeviceTree:/product", "product-name"), ("IOService:/", "model")] {
            let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
            guard entry != 0 else { continue }
            defer { IOObjectRelease(entry) }
            guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
            else { continue }
            var name: String?
            if let data = value as? Data {
                name = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
            } else if let s = value as? String {
                name = s
            }
            // A model identifier such as "Mac16,7" is no marketing name.
            if let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty, !n.contains(",") { return n }
        }
        #endif
        return nil
    }
}
