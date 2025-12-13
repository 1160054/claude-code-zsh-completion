# claude-code-zsh-completion

🚀 Zsh completion script for Claude Code CLI - intelligent auto-completion for all claude commands, options, and arguments

## Features

- ✨ Complete command completion for all `claude` commands
- 🔧 Intelligent option and flag suggestions
- 📦 MCP server management completions
- 🔌 Plugin marketplace operation completions
- 🎯 Context-aware argument completion
- 📝 Helpful descriptions for all commands and options

## Requirements

- Zsh 5.0 or later
- Claude Code CLI installed

## Installation
```bash
# Download and install
mkdir -p ~/.zsh/completions && curl -o ~/.zsh/completions/_claude \
  https://raw.githubusercontent.com/1160054/claude-code-zsh-completion/main/_claude
```

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

## Usage

Once installed, simply type `claude` and press `TAB` to see available completions:
```bash
claude <TAB>              # Shows all available commands
claude mcp <TAB>          # Shows MCP subcommands
claude --<TAB>            # Shows all available options
claude plugin <TAB>       # Shows plugin subcommands
```

### Examples
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

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License—see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Based on the official Claude Code CLI documentation
- Inspired by the Zsh completion system

## Links

- [Claude Code Documentation](https://docs.claude.com/)
- [Zsh Completion Guide](http://zsh.sourceforge.net/Doc/Release/Completion-System.html)

---

Made with ❤️ for the Claude Code community