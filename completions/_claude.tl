#compdef claude
# Mga dynamic na function ng completion
_claude_mcp_servers() {
  local config_file
  local -a server_list

  # Parse config files using grep/sed (no external dependencies)
  for config_file in ~/.claude.json ~/.claude/mcp.json ~/.config/claude/mcp.json; do
    [[ -f "$config_file" ]] || continue
    # Find entries with "command", "type", or "url" (MCP server signature)
    server_list+=(${(f)"$(grep -B 1 -E '"(command|type|url)"[[:space:]]*:' "$config_file" 2>/dev/null | \
      grep -E '"[^"]+": \{' | sed 's/.*"\([^"]*\)".*/\1/' | grep -v '/')"})
  done
  server_list=(${(u)server_list})

  # Fallback to claude mcp list
  if [[ ${#server_list[@]} -eq 0 ]]; then
    server_list=(${(f)"$(claude mcp list 2>/dev/null | sed -n 's/^\([^:]*\):.*/\1/p' | grep -v '^Checking')"})
  fi

  compadd -a server_list
}

_claude_installed_plugins() {
  local -a plugins
  local config_file plugin_dir
  # Check plugin directories directly
  for plugin_dir in ~/.claude/plugins ~/.config/claude/plugins; do
    [[ -d "$plugin_dir" ]] || continue
    plugins+=(${plugin_dir}/*(N:t))
  done
  # Remove duplicates
  plugins=(${(u)plugins})
  compadd -a plugins
}
_claude_sessions() {
  local -a sessions
  local session_dir
  # Check session directory
  for session_dir in ~/.claude/sessions ~/.config/claude/sessions; do
    [[ -d "$session_dir" ]] || continue
    # Extract UUIDs directly from filenames
    sessions+=(${session_dir}/*~*.zwc(N:t:r))
  done
  # Filter only valid UUIDs
  sessions=(${(M)sessions:#[0-9a-f](#c8)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c12)})
  compadd -a sessions
}
_claude() {
  local curcontext="$curcontext" state line
  typeset -A opt_args
  local -a main_commands
  main_commands=(
    'mcp:I-configure at pamahalaan ang mga MCP server'
    'plugin:Pamahalaan ang mga Claude Code plugin'
    'setup-token:I-set up ang pangmatagalang authentication token (kailangan ng Claude subscription)'
    'doctor:Health check para sa Claude Code auto-updater'
    'update:Suriin at i-install ang mga update'
    'install:I-install ang Claude Code native build'
  )
  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Paganahin ang debug mode na may opsyonal na pag-filter ng kategorya (hal.: "api,hooks" o "!statsig,!file")]:filter:'
    '--verbose[I-override ang verbose mode setting mula sa config file]'
    '(-p --print)'{-p,--print}'[I-print ang tugon at lumabas (para gamitin sa mga pipe). Tandaan: gamitin lang sa mga pinagkakatiwalaang direktoryo]'
    '--output-format[Format ng output (kasama ang --print): "text" (default), "json" (isang resulta), o "stream-json" (real-time streaming)]:format:(text json stream-json)'
    '--json-schema[JSON schema para sa structured output validation]:schema:'
    '--include-partial-messages[Isama ang mga partial message chunk habang dumarating (kasama ang --print at --output-format=stream-json)]'
    '--input-format[Format ng input (kasama ang --print): "text" (default) o "stream-json" (real-time streaming input)]:format:(text stream-json)'
    '--mcp-debug[\[Hindi na inirerekomenda. Gamitin ang --debug na lang\] Paganahin ang MCP debug mode (nagpapakita ng mga MCP server error)]'
    '--dangerously-skip-permissions[Laktawan ang lahat ng permission check. Inirerekomenda lang para sa mga sandbox na walang internet access]'
    '--allow-dangerously-skip-permissions[Paganahin ang opsyon na laktawan ang mga permission check nang hindi pinapagana by default]'
    '--replay-user-messages[Ipadala ulit ang mga mensahe ng user mula sa stdin sa stdout para sa kumpirmasyon]'
    '--allowed-tools[Listahan ng mga pinahihintulutang pangalan ng tool na pinaghihiwalay ng kuwit o espasyo (hal.: "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Listahan ng mga pinahihintulutang pangalan ng tool na pinaghihiwalay ng kuwit o espasyo (camelCase format)]:tools:'
    '--tools[Tukuyin ang listahan ng mga available na tool mula sa built-in set. Print mode lang]:tools:'
    '--disallowed-tools[Listahan ng mga hindi pinahihintulutang pangalan ng tool na pinaghihiwalay ng kuwit o espasyo (hal.: "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Listahan ng mga hindi pinahihintulutang pangalan ng tool na pinaghihiwalay ng kuwit o espasyo (camelCase format)]:tools:'
    '--mcp-config[Mag-load ng mga MCP server mula sa JSON file o string (pinaghihiwalay ng espasyo)]:configs:'
    '--system-prompt[System prompt na gagamitin para sa session]:prompt:'
    '--append-system-prompt[Idagdag ang system prompt sa default system prompt]:prompt:'
    '--permission-mode[Permission mode na gagamitin para sa session]:mode:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Ipagpatuloy ang pinakabagong pag-uusap]'
    '(-r --resume)'{-r,--resume}'[Ipagpatuloy ang isang pag-uusap - tukuyin ang session ID o pumili nang interactive]:sessionId:_claude_sessions'
    '--fork-session[Lumikha ng bagong session ID sa halip na gamitin ulit ang orihinal na session ID kapag nagre-resume (kasama ang --resume o --continue)]'
    '--model[Model para sa kasalukuyang session. Tukuyin ang alias para sa pinakabagong model (hal.: '\''sonnet'\'' o '\''opus'\'')]:model:'
    '--fallback-model[Paganahin ang awtomatikong fallback sa tinukoy na model kapag ang default model ay overloaded (--print lang)]:model:'
    '--settings[Path sa settings JSON file o JSON string para mag-load ng karagdagang mga setting]:file-or-json:_files'
    '--add-dir[Karagdagang mga direktoryo para pahintulutan ang tool access]:directories:_directories'
    '--ide[Auto-connect sa IDE sa startup kung eksakto isang valid na IDE ang available]'
    '--strict-mcp-config[Gumamit lang ng mga MCP server mula sa --mcp-config at huwag pansinin ang lahat ng iba pang MCP setting]'
    '--session-id[Partikular na session ID na gagamitin para sa pag-uusap (dapat valid na UUID)]:uuid:'
    '--agents[JSON object na nagtutukoy ng mga custom agent]:json:'
    '--setting-sources[Listahan ng mga setting source na pinaghihiwalay ng kuwit para i-load (user, project, local)]:sources:'
    '--plugin-dir[Direktoryo kung saan mag-load ng mga plugin para sa session na ito lang (maaaring ulitin)]:paths:_directories'
    '(-v --version)'{-v,--version}'[Ilabas ang numero ng bersyon]'
    '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]'
  )
  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'mga claude command' main_commands
      ;;
    args)
      case $words[1] in
        mcp)
          _claude_mcp
          ;;
        plugin)
          _claude_plugin
          ;;
        install)
          _claude_install
          ;;
        setup-token|doctor|update)
          _message "walang mga argumento"
          ;;
      esac
      ;;
  esac
}
_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Magsimula ng Claude Code MCP server'
    'add:Magdagdag ng MCP server sa Claude Code'
    'remove:Alisin ang MCP server'
    'list:Ilista ang mga naka-configure na MCP server'
    'get:Kunin ang mga detalye ng MCP server'
    'add-json:Magdagdag ng MCP server (stdio o SSE) gamit ang JSON string'
    'add-from-claude-desktop:Mag-import ng mga MCP server mula sa Claude Desktop (Mac at WSL lang)'
    'reset-project-choices:I-reset ang lahat ng naaprubahan/tinanggihan na project-scoped (.mcp.json) na mga server sa proyektong ito'
    'help:Ipakita ang tulong'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'mga mcp command' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Paganahin ang debug mode]' \
            '--verbose[I-override ang verbose mode setting mula sa config file]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Saklaw ng config (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Uri ng transport (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Itakda ang environment variable (hal.: -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Itakda ang WebSocket header]:header:' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Saklaw ng config (local, user, project) - alisin mula sa umiiral na scope kung hindi tinukoy]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Saklaw ng config (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Saklaw ng config (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]'
          ;;
      esac
      ;;
  esac
}
_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:I-validate ang plugin o marketplace manifest'
    'marketplace:Pamahalaan ang mga Claude Code marketplace'
    'install:Mag-install ng plugin mula sa mga available na marketplace'
    'i:Mag-install ng plugin mula sa mga available na marketplace (maikli para sa install)'
    'uninstall:I-uninstall ang naka-install na plugin'
    'remove:I-uninstall ang naka-install na plugin (alyas para sa uninstall)'
    'enable:Paganahin ang naka-disable na plugin'
    'disable:I-disable ang naka-enable na plugin'
    'help:Ipakita ang tulong'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'mga plugin command' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:plugin:_claude_installed_plugins'
          ;;
      esac
      ;;
  esac
}
_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Magdagdag ng marketplace mula sa URL, path, o GitHub repository'
    'list:Ilista ang mga naka-configure na marketplace'
    'remove:Alisin ang naka-configure na marketplace'
    'rm:Alisin ang naka-configure na marketplace (alyas para sa remove)'
    'update:I-update ang marketplace mula sa source - i-update lahat kung walang tinukoy na pangalan'
    'help:Ipakita ang tulong'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'mga marketplace command' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]'
          ;;
        remove|rm)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}
_claude_install() {
  _arguments \
    '--force[Pilitin ang pag-install kahit naka-install na]' \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
    '::target:(stable latest)'
}
(( $+_comps[claude] )) || compdef _claude claude
