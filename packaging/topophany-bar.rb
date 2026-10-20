# A Homebrew cask for topophany-bar. Prepared, not submitted: fill in the
# version and sha256 (scripts/release.sh prints it).
cask "topophany-bar" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256"

  url "https://github.com/WhitenWhiten/topophany-bar/releases/download/v#{version}/topophany-bar-#{version}.zip"
  name "Topophany Bar"
  desc "Menu bar item and desktop widgets for topo"
  homepage "https://github.com/WhitenWhiten/topophany-bar"

  depends_on macos: ">= :tahoe"

  app "topophany-bar.app"

  zap trash: [
    "~/Library/Application Support/topophany-bar",
    "~/Library/Preferences/io.github.whitenwhiten.topophany-bar.plist",
  ]

  caveats <<~EOS
    topophany-bar reads frames from `topo monitor stream`. Install topo and
    run `topo login` first; the app finds topo on your PATH.
  EOS
end
