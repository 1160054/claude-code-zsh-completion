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
Type "mkdir -p $PROJ && cp $DEMO_ROOT/fixtures/sessions/*.jsonl $PROJ && touch $PROJ/d41e7b02-*.jsonl"
Enter
Type "export PROMPT='%F{green}%B>%b%f '"
Enter
Type "unfunction _claude 2>/dev/null; fpath=($DEMO_ROOT/../completions $fpath)"
Enter
Type "autoload -Uz compinit && compinit -u -d ${TMPDIR:-/tmp}/claude-demo-zcompdump"
Enter
Type "zstyle ':completion:*' menu yes select"
Enter
# Nothing on camera should run the real claude: Enter is only ever meant to pick
# a candidate, and a stray one would start claude against the fixture HOME
Type "claude() { : }"
Enter
Type "zmodload zsh/complist"
Enter
# Recording only: flash a <TAB> marker after the cursor so the viewer sees the
# key being pressed, then complete as usual
Type `tab-flash() { POSTDISPLAY="  <TAB> "; region_highlight=("$(( $#BUFFER + 2 )) $(( $#BUFFER + 7 )) fg=black,bg=yellow,bold"); zle -R; sleep 0.45; POSTDISPLAY=""; region_highlight=(); zle tab-complete }`
Enter
# A completion widget has to be called through zle -C: a plain widget calling
# menu-select completes nothing
Type "zle -C tab-complete menu-select _main_complete; zle -N tab-flash; bindkey '^I' tab-flash"
Enter
# Warm the completion up off camera: the first TAB on a freshly autoloaded
# _claude only loads it, so a cold first scene would list without selecting
Type "claude "
Tab@300ms 3
Sleep 1s
Ctrl+C
Ctrl+C
Type "clear"
Enter
Sleep 500ms
Show

# 1. Every command, with what it does - including the ones you did not know about
Type "claude "
Sleep 500ms
Tab
Sleep 1.8s
Down@170ms 9
Sleep 700ms
Enter
Sleep 500ms

# 2. ...and on down: add an MCP server without opening --help
Tab
Sleep 1.2s
Enter
Sleep 400ms
Type "--"
Tab
Sleep 1.2s
Down@170ms 7
Sleep 500ms
Enter
Tab
Sleep 900ms
Enter
Sleep 300ms
Type "github https://api.githubcopilot.com/mcp/"
Sleep 1.5s

Hide
Ctrl+C
Ctrl+C
Sleep 200ms
Type "clear"
Enter
Sleep 600ms
Show

# 3. Hand it a job in the background, options and their values by TAB
Type "claude --bg --mod"
Tab
Sleep 500ms
Tab
Sleep 1.1s
Down@200ms 3
Sleep 500ms
Enter
Type " --permission-mode "
Tab
Sleep 1.1s
Down@170ms 5
Sleep 500ms
Enter
Type ` --name "triage open issues" "triage this week's issues"`
Sleep 1.8s

Hide
Ctrl+C
Ctrl+C
Sleep 200ms
Type "clear"
Enter
Sleep 600ms
Show

# 4. See how it is doing - by the name you gave it
Type "claude attach "
Tab
Sleep 2.2s

Hide
Ctrl+C
Ctrl+C
Sleep 200ms
Type "clear"
Enter
Sleep 600ms
Show

# 5. Next day, pick the conversation back up by the same name
Type "claude --resume "
Tab
Sleep 1.3s
Down@250ms 3
Sleep 2s
