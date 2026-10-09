class Ask < Formula
  desc "AI terminal assistant for plain-English shell commands and chat"
  homepage "https://github.com/zmsp/ask"
  url "https://github.com/zmsp/ask/archive/refs/tags/v2.1.1.tar.gz"
  sha256 "cd8a3433b870be23167bab168a6bdc96c4466dcdc3edab9dc257f87fd6d3c3d3"
  license "MIT"

  depends_on "jq"

  def install
    bin.install "ask.sh" => "ask"
  end

  test do
    assert_match "ask v2.1.1", shell_output("#{bin}/ask --version")
  end
end
