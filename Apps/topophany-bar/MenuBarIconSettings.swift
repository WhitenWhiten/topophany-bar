import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TopophanyKit
import TopophanyThemes

struct MenuBarIconSettings: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var error: String?
    @State private var renaming = false
    @State private var deleting = false
    @State private var name = ""

    private var selection: String {
        let bar = model.settings.appearance.menuBar
        return bar.icon == .custom ? bar.customIconID ?? "globe" : bar.icon.rawValue
    }

    private var selectedAsset: MenuBarIconAsset? { model.customIcons.first { $0.id == selection } }

    private var iconPicker: some View {
        Picker(selection: Binding<String>(get: { selection }, set: { model.selectIcon($0) })) {
            Text("Default").tag("globe")
            Text("DeepSeek Girl").tag("deepseek")
            ForEach(model.customIcons) { asset in Text(verbatim: asset.name).tag(asset.id) }
            if model.settings.appearance.menuBar.icon == .custom, selectedAsset == nil {
                Text("Unavailable custom icon").tag(selection)
            }
        } label: {
            RowLabel("Menu bar icon")
        }
    }

    var body: some View {
        controls
        .disabled(importing)
        .alert("Rename icon", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                do { try model.iconLibrary.rename(selection, to: name); model.reloadIcons() }
                catch { self.error = tr(.init(stringLiteral: error.localizedDescription)) }
            }
        }
        .confirmationDialog("Delete this custom icon?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                do { try model.removeIcon(selection) }
                catch { self.error = tr(.init(stringLiteral: error.localizedDescription)) }
            }
        } message: { Text("The original files will be kept.") }
        .alert("Could not update icon", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(verbatim: error ?? "") }
    }

    @ViewBuilder private var controls: some View {
        Group {
            iconPicker
            LabeledContent {
                HStack(spacing: 8) {
                    if importing { ProgressView().controlSize(.small) }
                    Button("Import…", action: chooseFiles)
                    if let asset = selectedAsset {
                        Button("Rename…") { name = asset.name; renaming = true }
                        Button("Delete…", role: .destructive) { deleting = true }
                    }
                }
            } label: {
                RowLabel("Custom icons", "PNG, JPEG, GIF or APNG; select multiple PNGs for a 12 fps sequence")
            }
            if model.settings.appearance.menuBar.icon != .globe {
                Picker(selection: model.binding(\.appearance.menuBar.iconSize)) {
                    Text("Small").tag(18)
                    Text("Medium").tag(22)
                    Text("Large").tag(26)
                } label: { RowLabel("Icon size") }
                if selection == "deepseek" || selectedAsset?.isAnimated == true {
                    Picker(selection: model.binding(\.appearance.menuBar.iconSpeed)) {
                        Text(verbatim: "0.5×").tag(0.5)
                        Text(verbatim: "1×").tag(1.0)
                        Text(verbatim: "1.5×").tag(1.5)
                        Text(verbatim: "2×").tag(2.0)
                    } label: { RowLabel("Animation speed") }
                }
            }
            if let error = model.iconError {
                Text(verbatim: error).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = tr("Import menu bar icon")
        panel.message = tr("Select one image or animation, or multiple PNG frames. Frames play in filename order.")
        panel.allowedContentTypes = [.png, .jpeg, .gif, UTType(filenameExtension: "apng") ?? .png]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            importing = true
            Task { @MainActor in
                defer { importing = false }
                let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
                defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
                do {
                    let library = model.iconLibrary
                    let asset = try await Task.detached(priority: .userInitiated) { try library.importFiles(urls) }.value
                    model.reloadIcons()
                    model.selectIcon(asset.id)
                } catch { self.error = tr(.init(stringLiteral: error.localizedDescription)) }
            }
        }
    }
}
