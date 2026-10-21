# topophany-bar

A native macOS menu bar app and desktop widgets for [Topophany](https://github.com/WhitenWhiten/topophany). The status item shows, at a glance, what your collector concludes about your network. One click opens a panel with what needs attention, the vantage points that see it, a map of where your servers are, your applications, pinned services and servers, and this Mac. Widgets pin the same cards to the desktop.

It shows what `topo` concludes and never decides anything itself. Every state, count and health comes from `topo monitor stream`, which the app runs as a child process.

**Status:** v1, not yet released. macOS 26 or later.

In Settings › General › Keyboard shortcut, click Record shortcut to choose a global key that opens or closes the panel. Esc cancels and the clear button removes it. Conflicts with enabled system shortcuts, Topophany commands and registered global hotkeys are rejected. Other apps' internal shortcuts cannot all be checked.

Settings › Sections › When the panel scrolls › Lock Geo Map is on by default, so wheel and trackpad scrolling moves the panel without zooming or panning the map. Turn it off to restore map scrolling; pinch and keyboard zoom are available either way.

Like it? ★ [Star Topophany](https://github.com/WhitenWhiten/topophany), the project this bar is built on.

## Read first

| | |
|---|---|
| [`design/DESIGN.md`](design/DESIGN.md) | The design: surfaces, themes, widgets, architecture, phases |
| [`docs/PROTOCOL.md`](docs/PROTOCOL.md) | The contract with `topo monitor stream` (authoritative) |
| [`design/index.html`](design/index.html) | HTML previews of every surface, state and theme; open in a browser |

`design/shots/shot.sh PAGE OUT.png WIDTH HEIGHT [SCALE]` renders a preview page to PNG with a headless Chromium. For example: `design/shots/shot.sh "playground.html?scenario=incidents&theme=tui" /tmp/p.png 1440 1400 2`.

## Requirements

- macOS 26 or later.
- `topo` with `monitor stream` (`topo monitor stream --capabilities` must print `"protocol":1`). Without one, the app downloads it from [topophany's releases](https://github.com/WhitenWhiten/topophany/releases) when you click Download topo, and checks its SHA-256 first.
- A saved client profile (`topo login`, or Sign In in Settings, which runs it in your terminal). The app never reads or stores a token; `topo` does.

## Building

The packages build and test with SwiftPM; the app and the widget extension build with the Xcode project, which XcodeGen generates from `project.yml`.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
xcodegen generate
xcodebuild -project topophany-bar.xcodeproj -scheme topophany-bar -configuration Debug -derivedDataPath build/DerivedData build
```

Builds sign with the team in `project.yml` (`TOPOPHANY_TEAM`), with an App Group the app and the widgets share. Add `TOPOPHANY_SIGN=NO` to build ad hoc with no team or entitlements: the app runs, and macOS ignores the widgets. `scripts/release.sh` signs with Developer ID, notarizes, and packs the app into a disk image to drag to Applications. `scripts/make-dmg.sh APP OUT.dmg` packs any build the same way, for a look; `swift scripts/make-dmg-background.swift` redraws the image's window.

## Releasing on GitHub

The [release workflow](.github/workflows/release.yml) runs when you push a tag in
the form `vMAJOR.MINOR.PATCH`, for example `v0.1.0`. It tests the packages on
macOS 26, builds a universal app for Apple Silicon and Intel, signs with Developer
ID, notarizes and staples both the app and the DMG, and publishes the DMG and
`sha256.txt` as a GitHub Release. The tag selects the exact source commit and the
app's version; it does not build the current tip of the default branch.

Before the first release, enable GitHub Actions and add these **repository
secrets** under Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64 of a Developer ID Application `.p12` export, including its private key |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The nonempty password used to export the `.p12` |
| `APPLE_ID` | Apple Account email with access to the developer team |
| `APPLE_APP_SPECIFIC_PASSWORD` | An app-specific password for that account, used by `notarytool` |
| `APPLE_TEAM_ID` | The certificate's 10-character Apple Developer Team ID |

Export **Developer ID Application**, rather than Apple Development, from Keychain
Access with its private key. On macOS, copy the certificate's Base64 with:

```sh
base64 -i /path/to/DeveloperIDApplication.p12 | pbcopy
```

This requires Apple Developer Program membership. The workflow imports the key
into a temporary keychain and deletes it after the job. The Team ID overrides
the build's `TOPOPHANY_TEAM`; the certificate and the app/widget App Group must
belong to that team. See [GitHub's certificate setup guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).
GitHub supplies the release token automatically; no personal access token is
needed. Repository or organization policy must permit the workflow's
`contents: write` permission.

Commit and push the workflow and the code you want to release, then tag that
commit (assuming the GitHub remote is named `origin`):

```sh
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

Follow **Actions → Release DMG**. After it succeeds, **Releases → v0.1.0** contains
`topophany-bar-0.1.0.dmg` and `sha256.txt`. Use a new version tag for each release;
prerelease suffixes such as `-beta.1` are not supported by this workflow.
The workflow creates a release after signing and notarization succeed, and does
not overwrite an existing release. GitHub selects the Latest release
[automatically by date and version](https://cli.github.com/manual/gh_release_create).

## License

topophany-bar is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE): you may build it, run it and change it for any noncommercial purpose. Commercial use, including use at work for a company, needs a separate license; ask in an [issue](https://github.com/WhitenWhiten/topophany-bar/issues).

The provider logos and what came with them are under their own licenses: see [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md). [Topophany](https://github.com/WhitenWhiten/topophany) itself is under the MIT License.
