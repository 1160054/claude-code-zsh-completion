# VHS Demo Script for claude-code-zsh-completion
#
#   cd demo && vhs demo.tape
#
# The recording uses demo/fixtures/home as $HOME and records from
# demo/fixtures/project, so the configuration-driven completions (sessions,
# background sessions, MCP servers, plugins) always show the same fixture data
# instead of whatever happens to be configured on the machine doing the
# recording. CLAUDE_CONFIG_DIR is cleared for the same reason - left set, it
# would point the completion at the recorder's real configuration.

Output ../demo.gif

Set Shell zsh
Set FontSize 20
Set Width 1100
Set Height 620
Set Theme "Dracula"
Set Padding 20
Set TypingSpeed 30ms
Set Framerate 24
# Trims the pauses a little without retuning every Sleep below
Set PlaybackSpeed 1.1

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
# Warm the completion up off camera: the first TAB on a freshly autoloaded
# _claude only loads it, so a cold first scene would list without selecting
Type "claude "
Tab@300ms 3
Sleep 500ms
Ctrl+C
Ctrl+C
Type "clear"
Enter
Sleep 500ms
Show

# One command line, built only with TAB, the arrow keys and Enter: every step
# lists what comes next, with a description, so --help is never needed.

# 1. The commands
Type "claude "
Sleep 500ms
Tab@300ms 2
Sleep 1.5s
Down@180ms 9
Sleep 700ms
Enter
Sleep 600ms

# 2. The subcommands of mcp
Tab@300ms 2
Sleep 1.3s
Enter
Sleep 600ms

# 3. The options of mcp add
Type "--"
Sleep 300ms
Tab@300ms 2
Sleep 1.3s
Down@200ms 7
Sleep 700ms
Enter
Sleep 600ms

# 4. The values --transport takes
Tab@300ms 2
Sleep 1s
Enter
Sleep 500ms
Type "my-server https://example.com/mcp"
Sleep 2.5s
