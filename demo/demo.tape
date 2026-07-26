# VHS Demo Script for claude-code-zsh-completion
#
#   cd demo && vhs demo.tape
#
# The recording uses demo/fixtures/home as $HOME and records from
# demo/fixtures/project, so the configuration-driven completions (sessions, MCP
# servers, plugins) always show the same fixture data instead of whatever
# happens to be configured on the machine doing the recording. CLAUDE_CONFIG_DIR
# is cleared for the same reason - left set, it would point the completion at
# the recorder's real configuration.

Output ../demo.gif

Set Shell zsh
Set FontSize 20
Set Width 1100
Set Height 440
Set Theme "Dracula"
Set Padding 20
Set TypingSpeed 30ms
Set Framerate 24

# Setup before recording
Hide
Type "export DEMO_ROOT=$PWD"
Enter
Type "export HOME=$DEMO_ROOT/fixtures/home"
Enter
Type "unset CLAUDE_CONFIG_DIR"
Enter
Type "cd $DEMO_ROOT/fixtures/project"
Enter
# Sessions live under a directory named after the project's own path
Type "export PROJ=$HOME/.claude/projects/${${PWD//\//-}//./-}"
Enter
Type "mkdir -p $PROJ && cp $DEMO_ROOT/fixtures/sessions/*.jsonl $PROJ"
Enter
Type "export PROMPT='%F{green}%B>%b%f '"
Enter
Type "unfunction _claude 2>/dev/null; fpath=($DEMO_ROOT/../completions $fpath)"
Enter
Type "autoload -Uz compinit && compinit -u -d ${TMPDIR:-/tmp}/claude-demo-zcompdump"
Enter
Type "zstyle ':completion:*' menu select"
Enter
Type "clear"
Enter
Sleep 500ms
Show

# 1. The one that sells it: resumable sessions, described by what you asked
Type "claude --resume "
Sleep 400ms
Tab@300ms 2
Sleep 1.2s
Down@250ms 2
Sleep 2s

Hide
Ctrl+C
Ctrl+C
Sleep 200ms
Type "clear"
Enter
Sleep 700ms
Show

# 2. All top-level commands, with descriptions
Type "claude "
Sleep 400ms
Tab@300ms 2
Sleep 2.5s

Hide
Ctrl+C
Ctrl+C
Sleep 200ms
Type "clear"
Enter
Sleep 700ms
Show

# 3. MCP servers read from your own configuration
Type "claude mcp get "
Sleep 400ms
Tab@300ms 2
Sleep 1.2s
Down@250ms 2
Sleep 1.5s

Hide
Ctrl+C
Ctrl+C
Sleep 200ms
Type "clear"
Enter
Sleep 700ms
Show

# 4. Subcommands of a command group
Type "claude mcp "
Sleep 400ms
Tab@300ms 2
Sleep 2s

Hide
Ctrl+C
Ctrl+C
Sleep 200ms
Type "clear"
Enter
Sleep 700ms
Show

# 5. Options are filtered by what you typed
Type "claude --allow"
Sleep 400ms
Tab@300ms 2
Sleep 2s

Hide
Ctrl+C
Ctrl+C
Sleep 200ms
Type "clear"
Enter
Sleep 700ms
Show

# 6. Options that know their own values
Type "claude --permission-mode "
Sleep 400ms
Tab@300ms 2
Sleep 2.5s
