# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] - 2026-07-21

### Added
- Completion for new top-level commands: `agents`, `auth`, `auto-mode`, `gateway`, `project`, `ultrareview`
  - Subcommands for `auth` (`login`, `logout`, `status`), `auto-mode` (`config`, `critique`, `defaults`, `reset`), and `project` (`purge`)
  - Options for `agents`, `gateway` (`--config`), and `ultrareview` (`--json`, `--timeout`)
- 22 new session options, including `--worktree`/`-w`, `--effort`, `--bg`/`--background`, `--name`/`-n`, `--from-pr`, `--remote-control`, `--chrome`/`--no-chrome`, `--plugin-url`, `--file`, `--tmux`, `--safe-mode`, `--bare`, `--brief`, `--debug-file`, `--prompt-suggestions`, `--forward-subagent-text`, `--include-hook-events`, `--exclude-dynamic-system-prompt-sections`, `--ax-screen-reader`
- `mcp login` / `mcp logout` completion
- `plugin` subcommands: `list`, `details`, `init`, `eval`, `prune`, `tag`
- Demo GIF in the README

### Fixed
- Oh My Zsh: register completion via `compdef` so it works on a freshly started shell without a manual `compinit` re-run
- Correct `--permission-mode` choices to match the current CLI (`acceptEdits`, `auto`, `bypassPermissions`, `manual`, `dontAsk`, `plan`)

### Changed
- Normalize command-alias parsing and widen locale consistency tolerances in the test suite so not-yet-translated language files stay green
- Add a CLI version check to the test suite
- Document plugin manager installation in the README

> Note: These completion additions apply to the English (`_claude`) file. Translations for the 120+ localized files will follow.

## [2.1.0] - 2025-12-14

### Added
- New CLI options: `--max-budget-usd`, `--no-session-persistence`, `--agent`, `--betas`, `--disable-slash-commands`
- `plugin update` command
- `--scope` option for plugin-related commands

### Changed
- Optimize MCP server completion parsing using grep/sed (no external dependencies)
- Simplify dynamic completion functions
- Remove deprecated `migrate-installer` command
- Enhance test suite for all completions

## [2.0.0] - 2025-12-13

### Added
- **120+ language support** - Expanded from 8 to 120+ languages
  - All major world languages
  - Regional variants (English: 10, Spanish: 13, German: 4, French: 4, Swedish: 3, etc.)
  - Minority and constructed languages (Esperanto, Celtic languages, etc.)
- **New directory structure** - All completion files moved to `completions/` directory
  - Better organization for large number of language files
  - Cleaner repository root directory

### Changed
- **BREAKING: Installation path updated** - Completion files now in `completions/` directory
  - Old: `https://raw.githubusercontent.com/.../main/_claude`
  - New: `https://raw.githubusercontent.com/.../main/completions/_claude`
  - Existing users need to update their installation path
- Updated README with comprehensive language list and new structure
- Updated installation instructions for new directory structure
- Updated `.gitattributes` to recognize new directory structure
- Updated GitHub Actions test paths

## [1.1.0] - 2025-12-13

### Added
- **Dynamic completion** for MCP servers, plugins, and session IDs
  - `claude --resume <TAB>` - Show available session IDs
  - `claude mcp remove <TAB>` - Show configured MCP servers
  - `claude mcp get <TAB>` - Show configured MCP servers
  - `claude plugin uninstall <TAB>` - Show installed plugins
  - `claude plugin enable/disable <TAB>` - Show installed plugins
- GitHub Actions workflow for automated testing
- `.gitattributes` for proper language detection

### Changed
- **Performance optimization** for dynamic completion
  - MCP servers: 24x faster (0.236s → <0.010s)
  - Direct config file reading instead of running `claude mcp list`
  - Optimized plugin and session detection using zsh globs
- Updated `compdef` registration method for better compatibility
- Improved README with multi-language support and dynamic completion documentation

### Fixed
- Completion registration to prevent conflicts with existing completions

## [1.0.0] - 2025-12-13

### Added
- Initial release with 8 language versions:
  - `_claude` - English
  - `_claude.ja` - Japanese (日本語)
  - `_claude.zh-CN` - Chinese Simplified (简体中文)
  - `_claude.es` - Spanish (Español)
  - `_claude.fr` - French (Français)
  - `_claude.de` - German (Deutsch)
  - `_claude.ko` - Korean (한국어)
  - `_claude.pt-BR` - Portuguese Brazilian (Português)
- Complete command and subcommand completion
- Option and flag completion with descriptions
- Context-aware argument completion
- Support for all `claude` commands:
  - Main commands: `mcp`, `plugin`, `migrate-installer`, `setup-token`, `doctor`, `update`, `install`
  - MCP commands: `serve`, `add`, `remove`, `list`, `get`, `add-json`, `add-from-claude-desktop`, `reset-project-choices`
  - Plugin commands: `validate`, `marketplace`, `install`, `uninstall`, `enable`, `disable`
