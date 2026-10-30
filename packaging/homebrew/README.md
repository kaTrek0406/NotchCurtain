# Homebrew tap

Create a public repository named `homebrew-tap` under `kaTrek0406`, then place `notch-curtain.rb` at `Casks/notch-curtain.rb`. Users can install with `brew install --cask kaTrek0406/tap/notch-curtain`.

For each release, update `version` to the release version, download the matching macOS ZIP, and set `sha256` to `shasum -a 256 NotchCurtain-<version>-macos.zip`. Keep the release URL and cask version in sync.
