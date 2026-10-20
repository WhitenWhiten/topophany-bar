import AppKit
import TopophanySections

/// About Topophany: the standard panel, its credits in the language the
/// user chose. They say what the app is for, which `topo` it reads from
/// while one runs, and where its source, license and acknowledgements are.
@MainActor
enum About {
    static func show(topo version: String?) {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits(topo: version)])
    }

    static func credits(topo version: String?) -> NSAttributedString {
        let bundle = L10n.bundle(for: .main)
        var lines = [AttributedString(localized: "The menu bar item and desktop widgets for [Topophany](https://github.com/WhitenWhiten/topophany).", bundle: bundle)]
        if let version {
            lines.append(AttributedString(localized: "Reading from topo \(version).", bundle: bundle))
        }
        lines.append(AttributedString())
        lines.append(AttributedString(localized: "[Source](https://github.com/WhitenWhiten/topophany-bar) under the [PolyForm Noncommercial License 1.0.0](https://github.com/WhitenWhiten/topophany-bar/blob/main/LICENSE).", bundle: bundle))
        lines.append(AttributedString(localized: "Provider logos are their owners’ trademarks. [Acknowledgements](https://github.com/WhitenWhiten/topophany-bar/blob/main/THIRD-PARTY-NOTICES.md)", bundle: bundle))
        let text = NSMutableAttributedString(attributedString: lines.map { NSAttributedString($0) }.joined(separator: "\n"))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 2
        text.addAttributes([.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                            .foregroundColor: NSColor.secondaryLabelColor,
                            .paragraphStyle: paragraph],
                           range: NSRange(location: 0, length: text.length))
        return text
    }
}

private extension [NSAttributedString] {
    func joined(separator: String) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for (i, line) in enumerated() {
            if i > 0 { text.append(NSAttributedString(string: separator)) }
            text.append(line)
        }
        return text
    }
}
