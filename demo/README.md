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

The Japanese demo (`demo.ja.gif`, shown under "Other languages") is the same
tape recorded with `_claude.ja` and Japanese session and job names:

```bash
demo/make-ja.sh
```

It copies `demo/` to a temporary directory and rewrites the copy's fixtures, so
the checked-in fixtures stay English. Re-record it whenever `demo.gif` changes.

The `gifsicle` pass is part of the procedure, not an optional extra: VHS writes
every frame at the full framerate, and since the demo is mostly a static screen
waiting for the next keystroke, collapsing the identical frames and a light lossy
pass keep the file around 800 KB with no visible quality loss (the duration and every
scene stay exactly the same). Please run it before committing a new recording -
the GIF is loaded by everyone who opens the README.

## Files

- `demo.tape` - VHS script defining the demo scenario
- `make-ja.sh` - records `demo.ja.gif` from the same tape
- `fixtures/home/` - fake `$HOME` used during recording
- `fixtures/sessions/` - session transcripts copied into place at recording time

## About the fixtures

The dynamic completions read the user's own configuration:

| Completion              | Source                                          |
| ----------------------- | ----------------------------------------------- |
| `claude mcp get <TAB>`  | `~/.claude.json`                                |
| `claude --resume <TAB>` | `~/.claude/projects/<cwd>/*.jsonl`              |
| `claude attach <TAB>`   | `~/.claude/jobs/<id>/state.json`                |
| `claude plugin … <TAB>` | `~/.claude/plugins/installed_plugins.json`      |

To keep the recording reproducible - and to avoid leaking the recorder's real
MCP servers and session IDs into the GIF - `demo.tape` points `$HOME` at
`fixtures/home` before running `compinit`. Edit the files under `fixtures/home`
if you want different demo data.

The session transcripts are the exception: their directory is named after the
project's own path, so `demo.tape` creates it at recording time from
`fixtures/sessions/`. The background sessions under `fixtures/home/.claude/jobs`
are static and checked in.
