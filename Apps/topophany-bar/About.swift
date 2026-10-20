import AppKit
import TopophanySections

/// About Topophany: the standard panel, its credits in the language the
/// user chose. They say what the app is for, which `topo` it reads from
/// while one runs, and where its source, license and acknowledgements are.
/// Below them, the author's name in the copyright links to their homepage.
@MainActor
enum About {
    private static let author = "Whiten"
    private static let homepage = URL(string: "https://whiten.dev")!

    static func show(topo version: String?) {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits(topo: version)])
        linkAuthor()
    }

    /// The panel draws the copyright as plain text, so the author's name
    /// is linked in place once the panel is up. Should the panel be built
    /// some other way, the line stays as it was.
    private static func linkAuthor() {
        guard let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String else { return }
        for window in NSApp.windows where window.isVisible {
            guard let field = window.contentView?.textField(showing: copyright) else { continue }
            let text = NSMutableAttributedString(attributedString: field.attributedStringValue)
            let name = (text.string as NSString).range(of: author)
            guard name.location != NSNotFound else { return }
            text.addAttributes([.link: homepage, .underlineStyle: NSUnderlineStyle.single.rawValue], range: name)
            field.allowsEditingTextAttributes = true
            field.isSelectable = true
            field.attributedStringValue = text
            return
        }
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

private extension NSView {
    func textField(showing string: String) -> NSTextField? {
        if let field = self as? NSTextField, field.stringValue == string { return field }
        for view in subviews {
            if let field = view.textField(showing: string) { return field }
        }
        return nil
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
