[![Test Completion](https://github.com/1160054/claude-code-zsh-completion/actions/workflows/test.yml/badge.svg)](https://github.com/1160054/claude-code-zsh-completion/actions/workflows/test.yml)
[![GitHub release](https://img.shields.io/github/v/release/1160054/claude-code-zsh-completion)](https://github.com/1160054/claude-code-zsh-completion/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Languages](https://img.shields.io/badge/languages-120+-blue.svg)](https://github.com/1160054/claude-code-zsh-completion/tree/main/completions)

# claude-code-zsh-completion

Zsh completion for the Claude Code CLI. It reads your own configuration, so
`claude --resume <TAB>` lists the sessions you can actually resume — each one
labelled with what you asked in it — instead of leaving you to remember a UUID.

![Demo](demo.gif)

## Features

- Sessions, MCP servers, agents, models and plugins completed from your own configuration, not from a fixed list
- Completion for every `claude` command, subcommand and option
- Descriptions alongside each candidate, so you can pick without leaving the prompt
- Values completed for options that have a fixed set (`--permission-mode`, `--output-format`, …)
- Localized into 120+ languages

## Requirements

- Zsh 5.0 or later
- Claude Code CLI installed

## Installation

### [Homebrew](https://brew.sh/)

```bash
brew tap 1160054/claude https://github.com/1160054/claude-code-zsh-completion
brew trust 1160054/claude
brew install claude-code-zsh-completion
```

Homebrew 6 refuses to load formulae from a third-party tap until you trust it,
hence the middle step.

No `~/.zshrc` changes are needed — Homebrew's `site-functions` directory is
already on your `fpath`. `brew upgrade` keeps the completion current.

Every localized completion is installed alongside the English one. To switch:

```bash
ln -sf "$(brew --prefix)/share/claude-code-zsh-completion/completions/_claude.ja" \
  "$(brew --prefix)/share/zsh/site-functions/_claude"
```

### Manual Install

```bash
# Download and install (English example)
mkdir -p ~/.zsh/completions && curl -o ~/.zsh/completions/_claude \
  https://raw.githubusercontent.com/1160054/claude-code-zsh-completion/main/completions/_claude
```

For other languages, replace `_claude` with your preferred language file. See [Available Languages](#available-languages) below.

Add the following to your `~/.zshrc` (if not already present):
```bash
# Add completions directory to fpath
fpath=(~/.zsh/completions $fpath)

# Initialize completion system
autoload -Uz compinit
compinit
```

Reload your shell:
```bash
source ~/.zshrc
```

### Plugin Managers

#### [zinit](https://github.com/zdharma-continuum/zinit)

```bash
zinit light 1160054/claude-code-zsh-completion
```

#### [antigen](https://github.com/zsh-users/antigen)

```bash
antigen bundle 1160054/claude-code-zsh-completion
```

#### [sheldon](https://github.com/rossmacarthur/sheldon)

Add to `~/.config/sheldon/plugins.toml`:
```toml
[plugins.claude-code-zsh-completion]
github = "1160054/claude-code-zsh-completion"
```

#### [Oh My Zsh](https://ohmyz.sh/)

```bash
git clone https://github.com/1160054/claude-code-zsh-completion ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/claude-code
```

Add `claude-code` to your plugins in `~/.zshrc`:
```bash
plugins=(... claude-code)
```

## Available Languages

**120+ languages supported!** All completion files are located in the [`completions/`](completions/) directory.

### Popular Languages

- English (`_claude`), Japanese (`_claude.ja`), Chinese Simplified (`_claude.zh-CN`), Spanish (`_claude.es`), French (`_claude.fr`), German (`_claude.de`), Korean (`_claude.ko`), Russian (`_claude.ru`), Portuguese (`_claude.pt`), Italian (`_claude.it`), Arabic (`_claude.ar`), Hindi (`_claude.hi`), Turkish (`_claude.tr`), Polish (`_claude.pl`), Dutch (`_claude.nl`), Vietnamese (`_claude.vi`), Thai (`_claude.th`), Indonesian (`_claude.id`)

<details>
<summary>See all 120+ supported languages</summary>

Browse all language files in the [`completions/`](https://github.com/1160054/claude-code-zsh-completion/tree/main/completions) directory.

**Included:**
- **European**: Slavic (Bulgarian, Czech, Slovak, Croatian, Serbian, Ukrainian, Belarusian, etc.), Germanic (Swedish, Danish, Norwegian, Icelandic, Afrikaans), Romance (Portuguese, Romanian, Catalan, Galician), Baltic (Lithuanian, Latvian, Estonian), Celtic (Welsh, Scottish Gaelic), and more
- **Asian**: Chinese (Traditional, Cantonese, Hong Kong), Mongolian, Khmer, Lao, Bengali, Punjabi, Marathi, Tamil, Telugu, Kannada, Malayalam, Odia, Urdu, Nepali, Malay, Tagalog
- **Middle Eastern**: Persian, Hebrew, Azerbaijani, Kazakh, Uzbek, Uyghur, Tatar, Georgian
- **African**: Swahili, Wolof, Southern Sotho
- **Regional variants**: English (10 variants), Spanish (13 variants), German (4 variants), French (4 variants), Swedish (3 variants)
- **Others**: Esperanto, Basque, and many more

</details>

For any language, replace `_claude` with your preferred language file (e.g., `_claude.ja` for Japanese).

## Usage

### Completion from your own configuration

These read your configuration rather than a fixed list, so the candidates are
the ones you actually have. Resumable sessions are the clearest case — each is
labelled with the first thing you asked in it:

```bash
claude --resume <TAB>
3f6b1c20-8d4a-4e91-b7c2-1a5e9d0f3b84  -- add a health check endpoint
7c2a94e1-5b60-4d3f-9a18-e4c7b2650df3  -- why is the nightly build red?
a3f8e2b1-9c4d-4e7a-b5f3-2d8c9a1e4f6b  -- port auth to the new router
```

Sessions come from the project you are standing in, newest first. The rest work
the same way:

```bash
# MCP servers from your Claude Code configuration
claude mcp get <TAB>
claude mcp remove <TAB>

# Agents defined in ~/.claude/agents or the project's .claude/agents
claude --agent <TAB>

# Model aliases, plus full model names found in your settings
claude --model <TAB>

# Plugins you have installed
claude plugin uninstall <TAB>
```

`CLAUDE_CONFIG_DIR` is honoured, so this still works if your configuration does
not live in `~/.claude`.

### Commands and options

Type `claude` and press `TAB`:

```bash
claude <TAB>
agents        -- Manage background agents
auth          -- Manage authentication
mcp           -- Configure and manage MCP servers
plugin        -- Manage Claude Code plugins
project       -- Manage Claude Code project state
ultrareview   -- Run a cloud-hosted multi-agent code review and print the findings
...
```

Partial input narrows the candidates, and options that take a fixed set of
values complete those too:

```bash
claude --allow<TAB>
--allow-dangerously-skip-permissions  -- Enable option to bypass permission checks without enabling by default
--allowed-tools                       -- Comma or space-separated list of allowed tool names
--allowedTools                        -- Comma or space-separated list of allowed tool names (camelCase format)

claude --permission-mode <TAB>
acceptEdits  auto  bypassPermissions  manual  dontAsk  plan
```

## Supported Commands

Everything `claude --help` reports, including the `mcp`, `plugin`, `agents`,
`auth`, `auto-mode`, `gateway`, `project` and `ultrareview` command groups and
their subcommands.

The list that matters is [`completions/_claude`](completions/_claude) itself, so
it is not duplicated here — a scheduled workflow compares it against the
installed CLI every week and files an issue when the two drift apart.

## Troubleshooting

### Completions not working

1. Make sure the completion file is in your `fpath`:
```bash
echo $fpath
```

2. Verify the completion system is initialized in your `~/.zshrc`:
```bash
autoload -Uz compinit
compinit
```

3. Clear and rebuild completion cache:
```bash
rm -f ~/.zcompdump
compinit
```

4. Check if the completion file is loaded:
```bash
which _claude
```

Installed with Homebrew? The active file is
`$(brew --prefix)/share/zsh/site-functions/_claude`, and that directory is put
on your `fpath` by `brew shellenv` — check that your `~/.zshrc` runs it.

### Permission issues

Make sure the completion file has the correct permissions (manual install):
```bash
chmod 644 ~/.zsh/completions/_claude
```

### Still not working?

- Ensure Claude Code CLI is installed and accessible in your PATH
- Try restarting your terminal completely
- Check for conflicts with other completion scripts

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## License

This project is licensed under the MIT License—see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Based on the official Claude Code CLI documentation
- Inspired by the Zsh completion system
- Community translations from contributors worldwide

## Links

- [Claude Code Documentation](https://docs.claude.com/)
- [Zsh Completion Guide](http://zsh.sourceforge.net/Doc/Release/Completion-System.html)
