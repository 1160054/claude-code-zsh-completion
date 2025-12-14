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
