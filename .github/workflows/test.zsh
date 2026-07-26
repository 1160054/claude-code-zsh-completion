#!/usr/bin/env zsh
# Automated test script for Claude Code zsh completion
# Tests all completion files in completions/ directory

SCRIPT_DIR="${0:A:h}/../.."
COMPLETIONS_DIR="$SCRIPT_DIR/completions"
ENGLISH_FILE="$COMPLETIONS_DIR/_claude"

setopt LOCAL_OPTIONS

# Test counters
typeset -i total_tests=0
typeset -i passed_tests=0
typeset -i failed_tests=0
typeset -a failed_files=()

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_pass() {
  echo "${GREEN}✓${NC} $1"
  ((passed_tests++))
  ((total_tests++))
}

log_fail() {
  echo "${RED}✗${NC} $1"
  ((failed_tests++))
  ((total_tests++))
}

log_section() {
  echo ""
  echo "${YELLOW}=== $1 ===${NC}"
}

# Get reference counts from English file
get_reference_counts() {
  local file="$ENGLISH_FILE"

  REF_MAIN_COMMANDS=$(grep -c "'[a-z-]*:" "$file" | head -1)
  REF_FUNCTIONS=$(grep -c "^_claude" "$file")

  # Count main_options entries
  REF_MAIN_OPTIONS=$(sed -n '/^[[:space:]]*main_options=(/,/^[[:space:]]*)$/p' "$file" | grep -c "'\(-\|--\)")

  # Count mcp_commands entries
  REF_MCP_COMMANDS=$(sed -n '/^[[:space:]]*mcp_commands=(/,/^[[:space:]]*)$/p' "$file" | grep -c "'[a-z-]*:")

  # Count plugin_commands entries
  REF_PLUGIN_COMMANDS=$(sed -n '/^[[:space:]]*plugin_commands=(/,/^[[:space:]]*)$/p' "$file" | grep -c "'[a-z-]*:")

  # Count marketplace_commands entries
  REF_MARKETPLACE_COMMANDS=$(sed -n '/^[[:space:]]*marketplace_commands=(/,/^[[:space:]]*)$/p' "$file" | grep -c "'[a-z-]*:")
}

# Test 1: Basic syntax check
test_syntax() {
  local file="$1"
  if zsh -n "$file" 2>&1; then
    return 0
  else
    return 1
  fi
}

# Test 2: Check #compdef declaration
test_compdef_declaration() {
  local file="$1"
  head -1 "$file" | grep -q "^#compdef claude"
}

# Test 3: UTF-8 encoding check
test_utf8_encoding() {
  local file="$1"
  file "$file" | grep -qE "(UTF-8|ASCII)"
}

# Test 4: Required functions exist
test_required_functions() {
  local file="$1"
  local -a required_funcs=(
    "_claude()"
    "_claude_mcp()"
    "_claude_plugin()"
    "_claude_plugin_marketplace()"
    "_claude_install()"
  )

  for func in $required_funcs; do
    if ! grep -q "$func" "$file"; then
      return 1
    fi
  done
  return 0
}

# Test 5: Dynamic completion functions exist
test_dynamic_functions() {
  local file="$1"
  local -a dynamic_funcs=(
    "_claude_mcp_servers()"
    "_claude_installed_plugins()"
    "_claude_sessions()"
  )

  for func in $dynamic_funcs; do
    if ! grep -q "$func" "$file"; then
      return 1
    fi
  done
  return 0
}

# Test 6: Required arrays exist
test_required_arrays() {
  local file="$1"
  local -a required_arrays=(
    "main_commands="
    "main_options="
    "mcp_commands="
    "plugin_commands="
    "marketplace_commands="
  )

  for arr in $required_arrays; do
    if ! grep -q "$arr" "$file"; then
      return 1
    fi
  done
  return 0
}

# Test 7: Required commands in main_commands
test_required_commands() {
  local file="$1"
  local -a required_cmds=(
    "'mcp:"
    "'plugin:"
    "'doctor:"
    "'update:"
    "'install:"
  )

  for cmd in $required_cmds; do
    if ! grep -q "$cmd" "$file"; then
      return 1
    fi
  done
  return 0
}

# Test 8: Required options exist
test_required_options() {
  local file="$1"
  local -a required_opts=(
    "{-h,--help}"
    "{-v,--version}"
    "'--model["
    "{-r,--resume}"
    "{-c,--continue}"
  )

  for opt in $required_opts; do
    if ! grep -qF -- "$opt" "$file"; then
      return 1
    fi
  done
  return 0
}

# Test 9: compdef registration
test_compdef_registration() {
  local file="$1"
  grep -q "compdef _claude claude" "$file"
}

# Test 10: Source file without error
test_source_file() {
  local file="$1"
  (
    autoload -U compinit
    compinit -u 2>/dev/null
    source "$file" 2>&1
  )
}

# Test 11: Structure consistency with English version
test_structure_consistency() {
  local file="$1"

  # Count main_options in target file
  local target_options=$(sed -n '/^[[:space:]]*main_options=(/,/^[[:space:]]*)$/p' "$file" | grep -c "'\(-\|--\)")

  # Count mcp_commands in target file
  local target_mcp=$(sed -n '/^[[:space:]]*mcp_commands=(/,/^[[:space:]]*)$/p' "$file" | grep -c "'[a-z-]*:")

  # Count plugin_commands in target file
  local target_plugin=$(sed -n '/^[[:space:]]*plugin_commands=(/,/^[[:space:]]*)$/p' "$file" | grep -c "'[a-z-]*:")

  # Count marketplace_commands in target file
  local target_marketplace=$(sed -n '/^[[:space:]]*marketplace_commands=(/,/^[[:space:]]*)$/p' "$file" | grep -c "'[a-z-]*:")

  # Allow variance for gradual updates across language files
  # The English file tracks the CLI closely, so it can gain a batch of new
  # options/commands well before the localized files are translated. These
  # tolerances bound how far a language file may lag before it's flagged.
  # Options: allow up to 25 fewer (for new options not yet translated)
  # Commands: allow up to 8 fewer (for new commands not yet translated)
  if [[ $target_options -lt $((REF_MAIN_OPTIONS - 25)) ]] || \
     [[ $target_mcp -lt $((REF_MCP_COMMANDS - 4)) ]] || \
     [[ $target_plugin -lt $((REF_PLUGIN_COMMANDS - 8)) ]] || \
     [[ $target_marketplace -lt $((REF_MARKETPLACE_COMMANDS - 4)) ]]; then
    return 1
  fi
  return 0
}

# Test 12: File naming convention
test_file_naming() {
  local file="$1"
  local basename="${file:t}"

  # Should be _claude or _claude.<locale>
  # Locale: 2-3 letter code, optionally with region
  # Region can be: 2-4 letters (e.g., CN, BR) or 3 digits (e.g., 419 for Latin America)
  if [[ "$basename" == "_claude" ]] || [[ "$basename" =~ ^_claude\.[a-zA-Z]{2,3}(-[a-zA-Z0-9]{2,4})?$ ]]; then
    return 0
  fi
  return 1
}

# Test 13: CLI version check (compare with actual Claude CLI)
test_cli_options_coverage() {
  local file="$1"

  # Skip if claude command not available
  if ! command -v claude &>/dev/null; then
    return 0
  fi

  local -a missing_options=()

  # Extract CLI options from claude --help
  local cli_options=$(claude --help 2>&1 | grep -oE '\-\-[a-zA-Z][-a-zA-Z]*' | sort -u)

  # Check each CLI option exists in completion file
  for opt in ${(f)cli_options}; do
    # Skip deprecated options
    [[ "$opt" == "--mcp-debug" ]] && continue

    # Match on a word boundary: a plain substring search reports --foo as
    # present when the file only declares --foo-bar.
    if ! grep -qE -- "$opt([^a-zA-Z0-9-]|\$)" "$file"; then
      missing_options+=("$opt")
    fi
  done

  if [[ ${#missing_options[@]} -gt 0 ]]; then
    echo "    Missing options: ${missing_options[*]}" >&2
    return 1
  fi
  return 0
}

# Test 14: CLI subcommands coverage
test_cli_commands_coverage() {
  local file="$1"

  # Skip if claude command not available
  if ! command -v claude &>/dev/null; then
    return 0
  fi

  local -a missing_commands=()

  # Check main commands
  local main_cmds=$(claude --help 2>&1 | sed -n '/Commands:/,/^$/p' | grep -E '^  [a-z]' | awk '{print $1}' | sed 's/|.*//')
  for cmd in ${(f)main_cmds}; do
    [[ -z "$cmd" ]] && continue
    if ! grep -q "'$cmd:" "$file"; then
      missing_commands+=("$cmd")
    fi
  done

  # Check mcp subcommands
  local mcp_cmds=$(claude mcp --help 2>&1 | sed -n '/Commands:/,/^$/p' | grep -E '^  [a-z]' | awk '{print $1}')
  for cmd in ${(f)mcp_cmds}; do
    [[ -z "$cmd" || "$cmd" == "help" ]] && continue
    if ! grep -q "'$cmd:" "$file"; then
      missing_commands+=("mcp $cmd")
    fi
  done

  # Check plugin subcommands
  local plugin_cmds=$(claude plugin --help 2>&1 | sed -n '/Commands:/,/^$/p' | grep -E '^  [a-z]' | awk '{print $1}' | sed 's/|.*//')
  for cmd in ${(f)plugin_cmds}; do
    [[ -z "$cmd" || "$cmd" == "help" ]] && continue
    if ! grep -q "'$cmd:" "$file"; then
      missing_commands+=("plugin $cmd")
    fi
  done

  if [[ ${#missing_commands[@]} -gt 0 ]]; then
    echo "    Missing commands: ${missing_commands[*]}" >&2
    return 1
  fi
  return 0
}

# Oh My Zsh plugin bootstrap (claude-code.plugin.zsh)
#
# These run in `zsh -f` subshells so the developer's own zshrc, fpath and
# already-registered completions cannot mask a broken bootstrap.
PLUGIN_FILE="$SCRIPT_DIR/claude-code.plugin.zsh"

test_plugin_syntax() {
  zsh -n "$PLUGIN_FILE" 2>&1
}

# Oh My Zsh sources plugin files *after* compinit has already run, so the
# plugin has to register the completion itself (see #9).
#
# Any directory that already provides a _claude would let compinit register the
# completion on its own and hide a broken bootstrap - an inherited FPATH or a
# previous manual install is enough - so those are dropped first.
test_plugin_registers_completion() {
  zsh -f -c "
    local -a clean
    local dir
    for dir in \$fpath; do
      [[ -e \$dir/_claude ]] || clean+=(\$dir)
    done
    fpath=(\$clean)

    autoload -Uz compinit
    compinit -u -d ${(q)PLUGIN_TEST_DUMP}
    (( \$+_comps[claude] )) && exit 1

    source ${(q)PLUGIN_FILE}
    (( \$+_comps[claude] )) || exit 1
    [[ \$_comps[claude] == _claude ]] || exit 1
  " 2>&1
}

# Other install methods source the plugin *before* compinit, where compdef does
# not exist yet. The registration block must be a no-op there, not an error.
test_plugin_without_compdef() {
  zsh -f -c "
    source ${(q)PLUGIN_FILE} || exit 1
    (( \$+functions[compdef] )) && exit 1
    exit 0
  " 2>&1
}

# Either way, the completions directory has to end up on fpath.
test_plugin_extends_fpath() {
  zsh -f -c "
    source ${(q)PLUGIN_FILE}
    local dir=\${fpath[(r)*/completions]}
    [[ -n \$dir && -f \$dir/_claude ]]
  " 2>&1
}

run_plugin_tests() {
  local plugin_passed=true

  echo ""
  echo "Testing: ${PLUGIN_FILE:t}"

  PLUGIN_TEST_DUMP="${TMPDIR:-/tmp}/claude-completion-test-zcompdump.$$"

  if test_plugin_syntax; then
    log_pass "Syntax check"
  else
    log_fail "Syntax check"
    plugin_passed=false
  fi

  if test_plugin_registers_completion; then
    log_pass "Registers completion when sourced after compinit"
  else
    log_fail "Registers completion when sourced after compinit"
    plugin_passed=false
  fi

  if test_plugin_without_compdef; then
    log_pass "No-op when compdef is not available yet"
  else
    log_fail "No-op when compdef is not available yet"
    plugin_passed=false
  fi

  if test_plugin_extends_fpath; then
    log_pass "Adds completions directory to fpath"
  else
    log_fail "Adds completions directory to fpath"
    plugin_passed=false
  fi

  rm -f "$PLUGIN_TEST_DUMP"

  [[ $plugin_passed == true ]] || failed_files+=("${PLUGIN_FILE:t}")
}

# Run all tests for a single file
run_tests_for_file() {
  local file="$1"
  local basename="${file:t}"
  local file_passed=true

  echo ""
  echo "Testing: $basename"

  # Test 1: Syntax
  if test_syntax "$file"; then
    log_pass "Syntax check"
  else
    log_fail "Syntax check"
    file_passed=false
  fi

  # Test 2: #compdef declaration
  if test_compdef_declaration "$file"; then
    log_pass "#compdef declaration"
  else
    log_fail "#compdef declaration"
    file_passed=false
  fi

  # Test 3: UTF-8 encoding
  if test_utf8_encoding "$file"; then
    log_pass "UTF-8 encoding"
  else
    log_fail "UTF-8 encoding"
    file_passed=false
  fi

  # Test 4: Required functions
  if test_required_functions "$file"; then
    log_pass "Required functions exist"
  else
    log_fail "Required functions exist"
    file_passed=false
  fi

  # Test 5: Dynamic functions
  if test_dynamic_functions "$file"; then
    log_pass "Dynamic completion functions"
  else
    log_fail "Dynamic completion functions"
    file_passed=false
  fi

  # Test 6: Required arrays
  if test_required_arrays "$file"; then
    log_pass "Required arrays exist"
  else
    log_fail "Required arrays exist"
    file_passed=false
  fi

  # Test 7: Required commands
  if test_required_commands "$file"; then
    log_pass "Required commands in main_commands"
  else
    log_fail "Required commands in main_commands"
    file_passed=false
  fi

  # Test 8: Required options
  if test_required_options "$file"; then
    log_pass "Required options exist"
  else
    log_fail "Required options exist"
    file_passed=false
  fi

  # Test 9: compdef registration
  if test_compdef_registration "$file"; then
    log_pass "compdef registration"
  else
    log_fail "compdef registration"
    file_passed=false
  fi

  # Test 10: Source file
  if test_source_file "$file"; then
    log_pass "Source file loads"
  else
    log_fail "Source file loads"
    file_passed=false
  fi

  # Test 11: Structure consistency (skip for English file)
  if [[ "$basename" != "_claude" ]]; then
    if test_structure_consistency "$file"; then
      log_pass "Structure consistency with English"
    else
      log_fail "Structure consistency with English"
      file_passed=false
    fi
  fi

  # Test 12: File naming
  if test_file_naming "$file"; then
    log_pass "File naming convention"
  else
    log_fail "File naming convention"
    file_passed=false
  fi

  # Test 13 & 14: CLI coverage (only for English file)
  if [[ "$basename" == "_claude" ]]; then
    if test_cli_options_coverage "$file"; then
      log_pass "CLI options coverage"
    else
      log_fail "CLI options coverage"
      file_passed=false
    fi

    if test_cli_commands_coverage "$file"; then
      log_pass "CLI commands coverage"
    else
      log_fail "CLI commands coverage"
      file_passed=false
    fi
  fi

  if [[ "$file_passed" == "false" ]]; then
    failed_files+=("$basename")
  fi
}

# Drift check: only compare the English completion against the installed CLI.
#
# The full suite runs this too (tests 13 and 14), but it only runs on push and
# pull requests - so a CLI release goes unnoticed until somebody happens to
# push. The scheduled workflow calls this mode instead, and turns a non-zero
# exit into an issue.
run_drift_check() {
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║     Completion Drift Check                                 ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""

  if ! command -v claude &>/dev/null; then
    echo "${RED}claude CLI not found${NC} - cannot check for drift" >&2
    exit 2
  fi

  echo "Claude CLI:  $(claude --version 2>&1)"
  echo "Completion:  ${ENGLISH_FILE:t}"
  echo ""

  local drifted=false

  if test_cli_options_coverage "$ENGLISH_FILE" 2>&1; then
    echo "${GREEN}✓${NC} Every option in \`claude --help\` is completed"
  else
    echo "${RED}✗${NC} Options are missing from the completion"
    drifted=true
  fi

  if test_cli_commands_coverage "$ENGLISH_FILE" 2>&1; then
    echo "${GREEN}✓${NC} Every command in \`claude --help\` is completed"
  else
    echo "${RED}✗${NC} Commands are missing from the completion"
    drifted=true
  fi

  echo ""
  if [[ $drifted == true ]]; then
    echo "${RED}Drift detected.${NC} Update completions/_claude, then propagate to the locale files."
    exit 1
  fi

  echo "${GREEN}No drift.${NC}"
  exit 0
}

# Main execution
main() {
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║     Claude Code Completion Test Suite                      ║"
  echo "╚════════════════════════════════════════════════════════════╝"

  # Get reference counts from English file
  log_section "Loading reference counts from English file"
  get_reference_counts
  echo "Reference main_options: $REF_MAIN_OPTIONS"
  echo "Reference mcp_commands: $REF_MCP_COMMANDS"
  echo "Reference plugin_commands: $REF_PLUGIN_COMMANDS"
  echo "Reference marketplace_commands: $REF_MARKETPLACE_COMMANDS"

  # Get all completion files
  local -a completion_files
  completion_files=($COMPLETIONS_DIR/_claude*)

  log_section "Running tests for ${#completion_files[@]} completion files"

  # Run tests for each file
  for file in $completion_files; do
    run_tests_for_file "$file"
  done

  log_section "Running tests for the Oh My Zsh plugin bootstrap"
  run_plugin_tests

  # Summary
  log_section "Test Summary"
  echo ""
  echo "Total tests:  $total_tests"
  echo "Passed:       ${GREEN}$passed_tests${NC}"
  echo "Failed:       ${RED}$failed_tests${NC}"
  echo ""

  if [[ ${#failed_files[@]} -gt 0 ]]; then
    echo "${RED}Failed files:${NC}"
    for f in $failed_files; do
      echo "  - $f"
    done
    echo ""
    exit 1
  else
    echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo "${GREEN}║     All tests passed!                                      ║${NC}"
    echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    exit 0
  fi
}

if [[ "$1" == "--drift-only" ]]; then
  run_drift_check
fi

main "$@"
