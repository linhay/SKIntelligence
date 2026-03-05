class Ski < Formula
  desc "SKIntelligence CLI"
  homepage "https://github.com/linhay/SKIntelligence"
  version "2.0.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/linhay/SKIntelligence/releases/download/2.0.0/ski-macos-arm64.tar.gz"
      sha256 "f823707b838b3c761fb90cb197a5411b78c0d33ab4fe62ba97207a5fb9521e68"
    end
    on_intel do
      url "https://github.com/linhay/SKIntelligence/releases/download/2.0.0/ski-macos-x86_64.tar.gz"
      sha256 "e22f5c6c6dce0faf6112c71f5ca6a5dc9528241c16af529ee557012b155798b7"
    end
  end

  def install
    bin.install "ski"
  end

  test do
    assert_match "SKIntelligence CLI", shell_output("#{bin}/ski --help")
  end
end
