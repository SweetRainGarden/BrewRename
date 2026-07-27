class Raname < Formula
  desc "Rename files and directories, replacing text in both names and content"
  homepage "https://github.com/SweetRainGarden/homebrew-raname"
  url "https://github.com/SweetRainGarden/homebrew-raname/archive/refs/tags/v1.2.1.0.tar.gz"
  version "1.2.1.0"
  sha256 "" # filled in automatically by the release workflow when a tag is pushed
  license "MIT"

  def install
    bin.install "bin/raname.sh" => "raname"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/raname --version")
  end
end
