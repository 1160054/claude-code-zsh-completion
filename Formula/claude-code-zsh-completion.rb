class ClaudeCodeZshCompletion < Formula
  desc "Zsh completion for the Claude Code CLI, localized into 120+ languages"
  homepage "https://github.com/1160054/claude-code-zsh-completion"
  url "https://github.com/1160054/claude-code-zsh-completion/archive/refs/tags/v2.4.0.tar.gz"
  sha256 "db911b5f0c334bf5f37bc11a0030dff8c3fc76ffb2255ae523b16095bdabad78"
  license "MIT"
  head "https://github.com/1160054/claude-code-zsh-completion.git", branch: "main"

  def install
    # Keep every completion around so a locale can be swapped in later
    pkgshare.install "completions"

    # English is the one zsh picks up automatically
    zsh_completion.install_symlink pkgshare/"completions/_claude"
  end

  def caveats
    <<~EOS
      The English completion is active. To use a localized one instead, link it
      over the installed file, e.g. for Japanese:
        ln -sf #{opt_pkgshare}/completions/_claude.ja #{zsh_completion}/_claude

      Available locales:
        ls #{opt_pkgshare}/completions
    EOS
  end

  test do
    completion = zsh_completion/"_claude"

    assert_match "#compdef claude", completion.read
    assert_path_exists pkgshare/"completions/_claude.ja"

    system "zsh", "-n", completion
  end
end
