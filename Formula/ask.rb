class Ask < Formula
  desc "AI terminal assistant for plain-English shell commands and chat"
  homepage "https://github.com/zmsp/ask"
  url "https://github.com/zmsp/ask/archive/refs/tags/v2.1.0.tar.gz"
  sha256 "219c7f6e9fe8dc0e48faf596f488b5f69b4c2f7aefb9ba64b4c9d63b32980771"
  license "MIT"

  depends_on "jq"

  def install
    bin.install "ask.sh" => "ask"
  end

  test do
    assert_match "ask v2.1.0", shell_output("#{bin}/ask --version")
  end
end
