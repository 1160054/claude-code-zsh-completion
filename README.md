[![Test Completion](https://github.com/1160054/claude-code-zsh-completion/actions/workflows/test.yml/badge.svg)](https://github.com/1160054/claude-code-zsh-completion/actions/workflows/test.yml)
[![GitHub release](https://img.shields.io/github/v/release/1160054/claude-code-zsh-completion)](https://github.com/1160054/claude-code-zsh-completion/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Languages](https://img.shields.io/badge/languages-120+-blue.svg)](https://github.com/1160054/claude-code-zsh-completion/tree/main/completions)

# claude-code-zsh-completion

🚀 Zsh completion script for Claude Code CLI - intelligent auto-completion for all claude commands, options, and arguments

## Features

- ✨ Complete command completion for all `claude` commands
- 🔧 Intelligent option and flag suggestions
- 📦 MCP server management completions
- 🔌 Plugin marketplace operation completions
- 🎯 Context-aware argument completion
- 📝 Helpful descriptions for all commands and options
- 🌍 **Multi-language support (120+ languages)**
- ⚡ Dynamic completion for MCP servers, plugins, and sessions

## Requirements

- Zsh 5.0 or later
- Claude Code CLI installed

## Installation

### Quick Install

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
<summary>📋 See all 120+ supported languages</summary>

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

Once installed, simply type `claude` and press `TAB` to see available completions:
```bash
claude <TAB>              # Shows all available commands
claude mcp <TAB>          # Shows MCP subcommands
claude --<TAB>            # Shows all available options
claude plugin <TAB>       # Shows plugin subcommands
```

### Basic Examples
```bash
# Autocomplete main commands
claude m<TAB>  →  claude mcp

# Autocomplete MCP subcommands
claude mcp a<TAB>  →  claude mcp add

# Autocomplete options
claude --mod<TAB>  →  claude --model

# Autocomplete with descriptions
claude mcp <TAB>
serve                    -- Start Claude Code MCP server
add                      -- Add an MCP server to Claude Code
remove                   -- Remove an MCP server
list                     -- List configured MCP servers
...
```

### Dynamic Completion Examples
```bash
# MCP server completion (shows your configured servers)
claude mcp remove <TAB>   # Shows: server1, server2, myserver, etc.
claude mcp get <TAB>      # Shows: server1, server2, myserver, etc.

# Plugin completion (shows your installed plugins)
claude plugin uninstall <TAB>   # Shows your installed plugins
claude plugin enable <TAB>      # Shows your installed plugins

# Session ID completion (shows your available sessions)
claude --resume <TAB>     # Shows: 12345678-abcd-..., 87654321-dcba-..., etc.
```

## Supported Commands

- Main commands: `mcp`, `plugin`, `migrate-installer`, `setup-token`, `doctor`, `update`, `install`
- MCP commands: `serve`, `add`, `remove`, `list`, `get`, `add-json`, `add-from-claude-desktop`, `reset-project-choices`
- Plugin commands: `validate`, `marketplace`, `install`, `uninstall`, `enable`, `disable`
- Plugin marketplace: `add`, `list`, `remove`, `update`

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

### Permission issues

Make sure the completion file has the correct permissions:
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

---

Made with ❤️ for the Claude Code community
