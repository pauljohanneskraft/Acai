class Acai < Formula
  desc "Parse a codebase and draw UML class diagrams, call graphs, and more"
  homepage "https://github.com/pauljohanneskraft/Acai"
  license "MIT"
  version "0.0.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/pauljohanneskraft/Acai/releases/download/v0.0.0/acai-macos-arm64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    else
      url "https://github.com/pauljohanneskraft/Acai/releases/download/v0.0.0/acai-macos-x86_64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/pauljohanneskraft/Acai/releases/download/v0.0.0/acai-linux-arm64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    else
      url "https://github.com/pauljohanneskraft/Acai/releases/download/v0.0.0/acai-linux-x86_64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
  end

  def install
    bin.install "acai"
    bin.install "acai-mcp"
  end

  test do
    system bin/"acai", "--help"
  end
end
