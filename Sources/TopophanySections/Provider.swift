import Foundation

/// A provider the app knows: a company that runs servers, or an edge or a
/// platform that services run on. `topo` sends a node's provider as the
/// topology writes it, in the provider's own spelling where `topo` knows it;
/// the app knows a provider by any of its usual names, and spells it the
/// provider's way. Who a provider is never says how it is doing.
public struct Provider: Sendable, Hashable, Identifiable {
    /// The logo's name, and the provider's in `design/assets/providers.js`.
    public var key: String
    /// As the provider spells it: "DigitalOcean", "Fly.io".
    public var name: String
    /// Every name a topology may give it, normalized.
    public var names: [String]
    /// 0xRRGGBB, or nil for none.
    public var color: UInt32?
    /// The few letters `topo` stands in for its name with, or "".
    public var mark: String
    public var hasLogo: Bool
    /// A place rather than a company, such as home or an office: its logo
    /// is a glyph of the app's own, and its name is the topology's.
    public var isGeneric: Bool

    public var id: String { key }

    init(key: String, name: String, names: [String], color: UInt32?, mark: String, hasLogo: Bool, isGeneric: Bool = false) {
        self.key = key
        self.name = name
        self.names = names
        self.color = color
        self.mark = mark
        self.hasLogo = hasLogo
        self.isGeneric = isGeneric
    }

    /// The provider a topology names, by any of its names, or nil.
    public static func known(_ name: String) -> Provider? {
        let n = normalized(name)
        return n.isEmpty ? nil : index[n]
    }

    /// A provider as the app writes it: in its own spelling where the app
    /// knows it, otherwise (and for a place, such as "homelab") as the
    /// topology wrote it.
    public static func name(_ raw: String) -> String {
        guard let p = known(raw), !p.isGeneric else { return raw }
        return p.name
    }

    /// A name in lowercase, with everything but letters and digits removed:
    /// "Fly.io" and "fly-io" are both "flyio".
    public static func normalized(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    public static var all: [Provider] { table }

    static let index: [String: Provider] = {
        var out: [String: Provider] = [:]
        for p in table {
            for n in p.names where out[n] == nil { out[n] = p }
        }
        return out
    }()
}
