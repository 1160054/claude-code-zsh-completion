# VHS Demo Script for claude-code-zsh-completion

Output ../demo.gif

Set Shell zsh
Set FontSize 20
Set Width 900
Set Height 300
Set Theme "Dracula"
Set Padding 20
Set TypingSpeed 30ms

# Setup before recording
Hide
Type "export PROMPT='$ '"
Enter
Type "fpath=(../completions $fpath); autoload -Uz compinit; compinit -u"
Enter
Type "clear"
Enter
Sleep 500ms
Type "claude "
Tab@300ms 2
Sleep 300ms
Show

# 1. Show all main commands (already displayed)
Sleep 2s

Ctrl+C
Sleep 300ms

# 2. Show MCP subcommands
Type "claude mcp "
Sleep 400ms
Tab@300ms 2
Sleep 2s

Ctrl+C
Sleep 300ms

# 3. Show MCP get with dynamic server completion
Type "claude mcp get "
Sleep 400ms
Tab@300ms 2
Sleep 2s

Ctrl+C
Sleep 300ms

# 4. Show options with filtering and completion
Type "claude --all"
Sleep 400ms
Tab
Sleep 800ms
Tab
Sleep 1.5s
Tab
Sleep 1.5s

Ctrl+C
Sleep 300ms

# 5. Show dynamic session completion (highlight feature)
Type "claude --resume "
Sleep 400ms
Tab@300ms 2
Sleep 2s

Sleep 1s
