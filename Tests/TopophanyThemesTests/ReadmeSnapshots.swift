import SwiftUI
import Testing
import TopophanySections
@testable import TopophanyThemes

/// A compact documentation screenshot, rendered directly from the panel views.
/// Each theme continues in its next column, with cuts between whole cards.
@MainActor
@Suite(.serialized) struct ReadmeSnapshots {
    @Test func widgetGallery() throws {
        L10n.force("en")
        let panel = previewPanel(.clear, settings: previewSettings(mac: .off, servers: true, services: true))
        let status = WidgetModel(kind: .status, panel: panel)
        let server = WidgetModel(kind: .server(node: "oracle-ny", isMac: false), panel: panel)
        let service = WidgetModel(kind: .service(id: "vless-entry"), panel: panel)
        let zones = WidgetModel(kind: .zones, panel: panel)
        let map = MapSnapshots().widget(.clear)

        func tile(_ model: WidgetModel, _ size: WidgetSize, theme: Theme, dark: Bool = true) -> some View {
            let context = RenderContext(theme: theme, colorScheme: dark ? .dark : .light)
            let renderer = Renderers.renderer(for: theme)
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            return renderer.widget(model, size: size,
                                   bounds: CGSize(width: size.width, height: size.height), context: context)
                .background(renderer.widgetBackground(context: context))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(dark ? 0.18 : 0.7), lineWidth: 0.5))
                .compositingGroup()
                .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
        }

        try snapshot("readme-widgets", OnDesktop(dark: true, padding: 28) {
            VStack(spacing: 24) {
                HStack(alignment: .top, spacing: 24) {
                    tile(status, .large, theme: ThemeStore.native)
                    VStack(spacing: 24) {
                        tile(map, .medium, theme: ThemeStore.native)
                        HStack(spacing: 24) {
                            tile(status, .small, theme: ThemeStore.native)
                            tile(server, .small, theme: ThemeStore.native)
                        }
                    }
                    VStack(spacing: 24) {
                        tile(server, .medium, theme: ThemeStore.native)
                        tile(zones, .medium, theme: ThemeStore.native)
                    }
                }
                HStack(spacing: 24) {
                    tile(service, .medium, theme: ThemeStore.native)
                    tile(status, .medium, theme: ThemeStore.terminal)
                    HStack(spacing: 24) {
                        tile(service, .small, theme: ThemeStore.paper, dark: false)
                        tile(zones, .small, theme: ThemeStore.paper, dark: false)
                    }
                }
            }
        })
    }

    @Test func panelColumns() throws {
        L10n.force("en")
        // Two warnings out of 68 checks, no failing checks or open incidents.
        // Keep the standard fixtures intact; only documentation chooses this scenario.
        let model = previewPanel(.degraded)
        let native = ThemeStore.native
        let terminal = ThemeStore.terminal
        let height = 890.0

        func measure(_ view: some View) throws -> CGSize {
            let renderer = ImageRenderer(content: view.fixedSize())
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            return CGSize(width: Double(image.width) / 2, height: Double(image.height) / 2)
        }

        // Measure section boundaries instead of maintaining screenshot pixel offsets.
        // Pick the boundary nearest the middle, keeping every card in one column.
        func layout(_ theme: Theme) throws -> (size: CGSize, cut: Double) {
            let context = RenderContext(theme: theme, colorScheme: .dark)
            let renderer = Renderers.renderer(for: theme)
            let size = try measure(renderer.panel(model, context: context))
            var cuts: [Double] = []
            for count in 1..<model.sections.count {
                var prefix = model
                prefix.sections = Array(model.sections.prefix(count))
                if theme.renderer == .cards {
                    let palette = CardsPalette.resolve(context)
                    let footer = CardsFooter(chrome: model.chrome, p: palette,
                                             t: CardsType(scale: 1, theme: theme), leapUp: nil)
                        .frame(width: size.width - 16)
                        .environment(\.colorScheme, .dark)
                    let footerSize = try measure(footer)
                    let prefixSize = try measure(renderer.panel(prefix, context: context))
                    let gap = CardsPanel(model: prefix, ctx: context).gap
                    cuts.append(prefixSize.height - footerSize.height - 8 - gap / 2)
                } else {
                    let scene = CellsPanel.scene(prefix, ctx: context)
                    // Footer starts 9 pt after the final box. The next title
                    // starts 6 pt after it; split in the intervening gap.
                    cuts.append(try #require(scene.marks["footer"]) - 6)
                }
            }
            let cut = try #require(cuts.min { abs($0 - size.height / 2) < abs($1 - size.height / 2) })
            return (size, cut)
        }

        let nativeLayout = try layout(native)
        let terminalLayout = try layout(terminal)

        func column(_ title: String, theme: Theme, start: Double, end: Double,
                    width: Double) -> some View {
            let context = RenderContext(theme: theme, colorScheme: .dark)
            let scale = height / (end - start)
            return VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.leading, 12)
                Renderers.renderer(for: theme).panel(model, context: context)
                    .fixedSize()
                    .offset(y: -start)
                    .frame(width: width, height: end - start, alignment: .top)
                    .clipped()
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: width * scale, height: height, alignment: .topLeading)
                    .clipped()
            }
        }

        try snapshot("readme-panels", OnDesktop(dark: true, padding: 28) {
            HStack(alignment: .top, spacing: 24) {
                column("Native · Overview", theme: native, start: 0, end: nativeLayout.cut, width: nativeLayout.size.width)
                column("Native · Continued", theme: native, start: nativeLayout.cut, end: nativeLayout.size.height,
                       width: nativeLayout.size.width)
                column("Terminal · Overview", theme: terminal, start: 0, end: terminalLayout.cut, width: terminalLayout.size.width)
                column("Terminal · Continued", theme: terminal, start: terminalLayout.cut, end: terminalLayout.size.height,
                       width: terminalLayout.size.width)
            }
        })
    }
}
