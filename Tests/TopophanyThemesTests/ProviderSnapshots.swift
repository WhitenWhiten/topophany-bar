import SwiftUI
import Testing
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

/// Every provider's logo, as each renderer draws it.
@MainActor
@Suite(.serialized) struct ProviderSnapshots {
    @Test func everyLogoParses() {
        for p in Provider.all where p.hasLogo {
            let o = ProviderLogo.outline(p.key)
            #expect(o != nil, "\(p.key)")
            if let o {
                #expect(max(o.size.width, o.size.height) == 1, "\(p.key) \(o.size)")
                let b = o.path.boundingRect
                #expect(b.width > 0.3 && b.height > 0.1 && b.minX > -0.01 && b.minY > -0.01 && b.maxX < 1.01 && b.maxY < 1.01,
                        "\(p.key) \(b)")
            }
        }
        #expect(ProviderLogo.outlines.keys.count { !$0.hasPrefix("glyph.") } == Provider.all.count { $0.hasLogo })
        for kind in ["host", "edge", "platform", "laptop"] {
            let key = ProviderLogo.glyph(kind: kind)
            let b = ProviderLogo.outline(key)?.path.boundingRect ?? .zero
            #expect(b.width > 0.5 && b.minX > 0 && b.maxX < 1 && b.minY > 0 && b.maxY < 1, "\(key) \(b)")
        }
    }

    /// A provider the app doesn't know takes its node's kind's glyph; a
    /// node naming none, its kind's symbol; a place keeps its own spelling.
    @Test func defaults() {
        #expect(ProviderLogo.key(provider: "BandwagonHost", kind: "host") == "glyph.server")
        #expect(ProviderLogo.key(provider: "Some Edge Co", kind: "edge") == "glyph.edge")
        #expect(ProviderLogo.key(provider: "", kind: "host") == nil)
        #expect(ProviderLogo.key(provider: "fly-io", kind: "platform") == "fly")
        #expect(ProviderLogo.key(provider: "Homelab", kind: "host") == "home")
        #expect(Provider.name("homelab") == "homelab")
        #expect(Provider.name("cloudcone") == "CloudCone")
        #expect(Provider.name("gitlab-pages") == "GitLab")
    }

    @Test func sheet() throws {
        for dark in [true, false] {
            let ctx = RenderContext(theme: ThemeStore.native, colorScheme: dark ? .dark : .light)
            let p = CardsPalette.resolve(ctx)
            let names = Provider.all.map(\.name) + ["my own rack"]
            let rows = VStack(alignment: .leading, spacing: 6) {
                ForEach(names, id: \.self) { name in
                    HStack(spacing: 12) {
                        Text(name).font(.system(size: 11)).foregroundStyle(p.l2).frame(width: 96, alignment: .leading)
                        if let key = ProviderLogo.key(provider: name, kind: "host") {
                            ForEach([12.0, 14, 16, 20], id: \.self) { s in
                                ProviderGlyph(key: key, color: p.l2).frame(width: s, height: s)
                                    .background(Rectangle().stroke(p.sep, lineWidth: 0.5))
                            }
                        } else {
                            Color.clear.frame(width: 104, height: 12)
                        }
                        NodeAvatar(provider: name, kind: "host", size: 28, p: p)
                        NodeAvatar(provider: "", kind: "host", size: 22, p: p)
                    }
                    .frame(height: 28)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(p.panel))
            try snapshot("providers-native-\(dark ? "dark" : "light")", OnDesktop(dark: dark) { rows }.environment(\.colorScheme, dark ? .dark : .light))
        }
        // Terminal: each logo before its name, in its brand's color.
        let tp = CellsPalette(ThemeStore.terminal)
        let m = CellMetrics.panel
        var w = CellWriter(metrics: m, palette: tp, width: 48 * m.cell + 14, frame: .init(x: 7, columns: 48))
        w.y = 6
        for p in Provider.all {
            w.line([.mark(.up, tp), .t(" ", tp.text)] + Seg.logo(p.name, tp) + [.t(p.name, tp.text, bold: true)], [.t(p.key, tp.faint)])
        }
        let scene = CellScene(size: CGSize(width: w.width, height: w.y + 6), metrics: m, items: w.items)
        try snapshot("providers-terminal", OnDesktop(dark: true) {
            CellCanvas(scene: scene).background(Color(tp.ink)).clipShape(RoundedRectangle(cornerRadius: 12))
        })
    }
}
