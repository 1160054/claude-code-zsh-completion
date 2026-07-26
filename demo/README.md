# Demo GIF Generation

Scripts for generating the demo GIF shown in the main README.

## Requirements

```bash
brew install charmbracelet/tap/vhs ttyd ffmpeg
```

## Generate Demo GIF

```bash
cd demo && vhs demo.tape
```

This will generate `demo.gif` in the project root.

## Files

- `demo.tape` - VHS script defining the demo scenario
- `fixtures/home/` - fake `$HOME` used during recording

## About the fixtures

The dynamic completions read the user's own configuration:

| Completion            | Source                       |
| --------------------- | ---------------------------- |
| `claude mcp get <TAB>` | `~/.claude.json`             |
| `claude --resume <TAB>` | `~/.claude/sessions/*`      |
| `claude plugin … <TAB>` | `~/.claude/plugins/*`       |

To keep the recording reproducible - and to avoid leaking the recorder's real
MCP servers and session IDs into the GIF - `demo.tape` points `$HOME` at
`fixtures/home` before running `compinit`. Edit the files under `fixtures/home`
if you want different demo data.
