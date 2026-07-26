# Demo GIF Generation

Scripts for generating the demo GIF shown in the main README.

## Requirements

```bash
brew install charmbracelet/tap/vhs ttyd ffmpeg gifsicle
```

## Generate Demo GIF

```bash
cd demo && vhs demo.tape && gifsicle -O3 --lossy=30 -o ../demo.gif ../demo.gif
```

This will generate `demo.gif` in the project root.

The `gifsicle` pass is part of the procedure, not an optional extra: VHS writes
every frame at the full framerate, and since the demo is mostly a static screen
waiting for the next keystroke, collapsing the identical frames takes the file
from ~400 KB to ~310 KB with no visible quality loss (the duration and every
scene stay exactly the same). Please run it before committing a new recording -
the GIF is loaded by everyone who opens the README.

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
