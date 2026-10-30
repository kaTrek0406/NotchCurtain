# typed: strict
# frozen_string_literal: true

cask "notch-curtain" do
  version "0.1.0"
  sha256 "252d9683910fa78a932ebb7c200056f67daedc82413170b1c8d4e25522215a37"

  url "https://github.com/kaTrek0406/NotchCurtain/releases/download/v#{version}/NotchCurtain-#{version}-macos.zip"
  name "NotchCurtain"
  desc "Panel for developer agent sessions, music, and usage limits"
  homepage "https://github.com/kaTrek0406/NotchCurtain"

  depends_on macos: :sonoma

  app "NotchCurtain.app"

  zap trash: [
    "~/Library/Application Support/NotchCurtain",
    "~/Library/Logs/NotchCurtain.log",
  ]

  caveats <<~EOS
    This build is ad-hoc signed. If macOS blocks it, remove quarantine with:
      xattr -dr com.apple.quarantine /Applications/NotchCurtain.app
  EOS
end
