[![GitHub release](https://img.shields.io/github/v/release/1160054/claude-code-zsh-completion)](https://github.com/1160054/claude-code-zsh-completion/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

# claude-code-zsh-completion

Zsh completion for the Claude Code CLI. It reads your own configuration, so
`claude --resume <TAB>` lists the sessions you can actually resume — each one
labelled with what you asked in it — instead of leaving you to remember a UUID.

![Demo](demo.gif)

The same goes for MCP servers, agents, models, plugins and background sessions.
Every command and option completes with a description, in 120 languages and regional variants.

## Install

```bash
brew tap 1160054/claude https://github.com/1160054/claude-code-zsh-completion
brew trust 1160054/claude
brew install claude-code-zsh-completion
```

No `~/.zshrc` changes needed.

<details>
<summary>Without Homebrew</summary>

```bash
mkdir -p ~/.zsh/completions
curl -o ~/.zsh/completions/_claude \
  https://raw.githubusercontent.com/1160054/claude-code-zsh-completion/main/completions/_claude
```

Then in `~/.zshrc`, before `compinit`:

```bash
fpath=(~/.zsh/completions $fpath)
```

Plugin managers load it as a plugin: `zinit light 1160054/claude-code-zsh-completion`,
`antigen bundle 1160054/claude-code-zsh-completion`, or for Oh My Zsh clone it into
`$ZSH_CUSTOM/plugins/claude-code` and add `claude-code` to `plugins=(...)`.

</details>

## Other languages

Every file in [`completions/`](completions/) is the same completion in another
language (`_claude.ja`, `_claude.de`, `_claude.zh-CN`, …). Use one in place of
`_claude`; with Homebrew:

```bash
ln -sf "$(brew --prefix)/share/claude-code-zsh-completion/completions/_claude.ja" \
  "$(brew --prefix)/share/zsh/site-functions/_claude"
```

Not completing after an install or a switch? Run `rm -f ~/.zcompdump && exec zsh`.

## License

MIT
