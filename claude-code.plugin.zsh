# claude-code.plugin.zsh - Oh My Zsh plugin for Claude Code CLI completion

# Add completions directory to fpath
fpath=(${0:A:h}/completions $fpath)

# Oh My Zsh runs compinit *before* it sources plugin files, so the fpath entry
# above is added too late to be picked up by the initial completion scan. As a
# result the completion does not work in a freshly started shell (only after a
# manual `compinit` re-run). Register it explicitly here so it works on the
# first shell, with no extra steps.
if (( $+functions[compdef] )); then
  autoload -Uz _claude
  compdef _claude claude
fi
