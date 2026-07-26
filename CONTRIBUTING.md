# Contributing

Thank you for your interest in contributing to claude-code-zsh-completion!

## How to Contribute

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Run tests: `zsh .github/workflows/test.zsh`
5. Commit your changes
6. Push to your fork
7. Submit a Pull Request

## Adding New Language Support

1. Copy `_claude` to `_claude.{locale}` (e.g., `_claude.ru` for Russian)
2. Translate all description strings in the `_arguments` section
3. Test the completion in your shell
4. Update `CHANGELOG.md` with your changes
5. Submit a Pull Request

## Demo GIF

`demo.gif` records the **English** completion only, so language PRs never need to
touch it. Please leave it alone unless your change affects what the demo shows -
new top-level commands, renamed subcommands, or changed option values - since
every re-recording adds another copy of the binary to the repository history.

When it does need updating, see [demo/README.md](demo/README.md).

## Reporting Bugs

Please use the GitHub issue tracker to report bugs. Include:
- Your OS and zsh version
- Steps to reproduce
- Expected vs actual behavior

## Feature Requests

We welcome feature requests! Please open an issue describing:
- The feature you'd like to see
- Why it would be useful
- Any implementation ideas

## Code Style

- Follow existing code formatting
- Use consistent indentation (2 spaces)
- Add comments for complex logic
- Keep language files in sync structurally

## Testing

Before submitting a PR, ensure:
- All tests pass: `zsh .github/workflows/test.zsh`
- Completion works in your shell
- No syntax errors in zsh completion files

## Questions?

Feel free to open an issue for any questions about contributing.
