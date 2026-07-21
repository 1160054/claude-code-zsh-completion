#compdef claude

# Dynamic completion functions
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
    'agents:Pamahalaan ang mga background agent'
    'auth:Pamahalaan ang authentication'
    'auto-mode:Suriin o i-reset ang configuration ng auto mode classifier'
    'gateway:Patakbuhin ang enterprise auth/telemetry gateway'
    'project:Pamahalaan ang state ng Claude Code project'
    'ultrareview:Magpatakbo ng cloud-hosted multi-agent code review at i-print ang mga natuklasan'
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
    '--max-budget-usd[Pinakamataas na halaga ng dolyar na gagastusin sa mga API call (--print lang)]:amount:'
    '--replay-user-messages[Ipadala ulit ang mga mensahe ng user mula sa stdin sa stdout para sa kumpirmasyon]'
    '--allowed-tools[Listahan ng mga pinahihintulutang pangalan ng tool na pinaghihiwalay ng kuwit o espasyo (hal.: "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Listahan ng mga pinahihintulutang pangalan ng tool na pinaghihiwalay ng kuwit o espasyo (camelCase format)]:tools:'
    '--tools[Tukuyin ang listahan ng mga available na tool mula sa built-in set. Print mode lang]:tools:'
    '--disallowed-tools[Listahan ng mga hindi pinahihintulutang pangalan ng tool na pinaghihiwalay ng kuwit o espasyo (hal.: "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Listahan ng mga hindi pinahihintulutang pangalan ng tool na pinaghihiwalay ng kuwit o espasyo (camelCase format)]:tools:'
    '--mcp-config[Mag-load ng mga MCP server mula sa JSON file o string (pinaghihiwalay ng espasyo)]:configs:'
    '--system-prompt[System prompt na gagamitin para sa session]:prompt:'
    '--append-system-prompt[Idagdag ang system prompt sa default system prompt]:prompt:'
    '--permission-mode[Permission mode na gagamitin para sa session]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Ipagpatuloy ang pinakabagong pag-uusap]'
    '(-r --resume)'{-r,--resume}'[Ipagpatuloy ang isang pag-uusap - tukuyin ang session ID o pumili nang interactive]:sessionId:_claude_sessions'
    '--fork-session[Lumikha ng bagong session ID sa halip na gamitin ulit ang orihinal na session ID kapag nagre-resume (kasama ang --resume o --continue)]'
    '--no-session-persistence[I-disable ang session persistence - hindi mase-save ang mga session (--print lang)]'
    '--model[Model para sa kasalukuyang session. Tukuyin ang alias para sa pinakabagong model (hal.: '\''sonnet'\'' o '\''opus'\'')]:model:'
    '--agent[Agent para sa kasalukuyang session. I-override ang '\''agent'\'' setting]:agent:'
    '--betas[Mga beta header na isasama sa mga API request (mga user ng API key lang)]:betas:'
    '--fallback-model[Paganahin ang awtomatikong fallback sa tinukoy na model kapag ang default model ay overloaded (--print lang)]:model:'
    '--settings[Path sa settings JSON file o JSON string para mag-load ng karagdagang mga setting]:file-or-json:_files'
    '--add-dir[Karagdagang mga direktoryo para pahintulutan ang tool access]:directories:_directories'
    '--ide[Auto-connect sa IDE sa startup kung eksakto isang valid na IDE ang available]'
    '--strict-mcp-config[Gumamit lang ng mga MCP server mula sa --mcp-config at huwag pansinin ang lahat ng iba pang MCP setting]'
    '--session-id[Partikular na session ID na gagamitin para sa pag-uusap (dapat valid na UUID)]:uuid:'
    '--agents[JSON object na nagtutukoy ng mga custom agent]:json:'
    '--setting-sources[Listahan ng mga setting source na pinaghihiwalay ng kuwit para i-load (user, project, local)]:sources:'
    '--plugin-dir[Direktoryo kung saan mag-load ng mga plugin para sa session na ito lang (maaaring ulitin)]:paths:_directories'
    '--disable-slash-commands[I-disable ang lahat ng slash command]'
    '(--bg --background)'{--bg,--background}'[Simulan ang session bilang background agent at agad na bumalik]'
    '(-w --worktree)'{-w,--worktree}'[Lumikha ng bagong git worktree para sa session na ito (opsyonal na tukuyin ang pangalan)]::name:'
    '--tmux[Lumikha ng tmux session para sa worktree (kailangan ang --worktree)]'
    '(-n --name)'{-n,--name}'[Magtakda ng display name para sa session na ito]:name:'
    '--effort[Antas ng effort para sa kasalukuyang session]:level:(low medium high xhigh max)'
    '--debug-file[Isulat ang mga debug log sa isang partikular na file path (awtomatikong pinapagana ang debug mode)]:path:_files'
    '--from-pr[Ipagpatuloy ang session na naka-link sa PR sa pamamagitan ng numero/URL, o buksan ang interactive picker]::value:'
    '--remote-control[Simulan ang interactive session na may naka-enable na Remote Control (opsyonal na may pangalan)]::name:'
    '--remote-control-session-name-prefix[Prefix para sa mga awtomatikong nabuong pangalan ng Remote Control session]:prefix:'
    '--chrome[Paganahin ang Claude in Chrome integration]'
    '--no-chrome[I-disable ang Claude in Chrome integration]'
    '--plugin-url[Kumuha ng plugin .zip mula sa isang URL para sa session na ito lang (maaaring ulitin)]:url:'
    '--file[Mga file resource na ida-download sa startup (format: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Paganahin ang mga prompt suggestion (naglalabas ng hinulaang susunod na prompt sa print/SDK mode)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Ipasa ang subagent text at mga thinking block bilang mga mensahe (kasama ang --print at stream-json)]'
    '--include-hook-events[Isama ang lahat ng hook lifecycle event sa output stream (kasama ang stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Ilipat ang mga per-machine section sa unang mensahe ng user para mapabuti ang muling paggamit ng prompt-cache]'
    '--brief[Paganahin ang SendUserMessage tool para sa komunikasyon mula agent papuntang user]'
    '--safe-mode[Magsimula na naka-disable ang lahat ng customization (kapaki-pakinabang sa pag-troubleshoot ng sirang configuration)]'
    '--bare[Minimal mode: laktawan ang hooks, LSP, plugin sync, attribution, auto-memory, at CLAUDE.md auto-discovery]'
    '--ax-screen-reader[Mag-render ng output na madaling gamitin sa screen reader (flat na text, walang dekoratibong border o animation)]'
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
        agents)
          _claude_agents
          ;;
        auth)
          _claude_auth
          ;;
        auto-mode)
          _claude_auto_mode
          ;;
        gateway)
          _claude_gateway
          ;;
        project)
          _claude_project
          ;;
        ultrareview)
          _claude_ultrareview
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
    'login:Mag-authenticate sa isang MCP server (HTTP, SSE, o claude.ai connector)'
    'logout:I-clear ang mga naka-store na OAuth credential para sa isang MCP server'
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
        login|logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:name:_claude_mcp_servers'
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
    'list:Ilista ang mga naka-install na plugin'
    'details:Ipakita ang component inventory at inaasahang token cost para sa isang plugin'
    'install:Mag-install ng plugin mula sa mga available na marketplace'
    'i:Mag-install ng plugin mula sa mga available na marketplace (maikli para sa install)'
    'init:Mag-scaffold ng bagong plugin (awtomatikong naglo-load sa susunod na session)'
    'uninstall:I-uninstall ang naka-install na plugin'
    'remove:I-uninstall ang naka-install na plugin (alyas para sa uninstall)'
    'enable:Paganahin ang naka-disable na plugin'
    'disable:I-disable ang naka-enable na plugin'
    'update:I-update ang plugin sa pinakabagong bersyon'
    'eval:Magpatakbo ng mga eval case laban sa plugin at iulat ang mga na-score na resulta'
    'prune:Alisin ang mga awtomatikong na-install na dependency na hindi na kailangan'
    'tag:Lumikha ng {name}--v{version} git tag para sa isang plugin release'
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
            '(-s --scope)'{-s,--scope}'[Saklaw ng pag-install]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Saklaw ng pag-install]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Saklaw ng pag-install]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Saklaw ng pag-install]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:path:_files'
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

_claude_agents() {
  _arguments \
    '*--add-dir[Karagdagang direktoryo para pahintulutan ang tool access sa mga dispatched session]:directory:_directories' \
    '--agent[Default na agent para sa mga session na na-dispatch mula sa agent view]:agent:' \
    '--all[Kasama ang --json: isama rin ang mga natapos na background session]' \
    '--allow-dangerously-skip-permissions[Gawing available ang bypass-permissions mode sa mga dispatched session]' \
    '--cwd[Ipakita lang ang mga background session na sinimulan sa ilalim ng path]:path:_directories' \
    '--dangerously-skip-permissions[Alyas para sa --permission-mode bypassPermissions]' \
    '--effort[Default na antas ng effort para sa mga dispatched session]:level:(low medium high xhigh max)' \
    '--json[I-print ang mga aktibong session bilang JSON array at lumabas]' \
    '*--mcp-config[MCP server configuration na ilalapat sa mga dispatched session]:config:' \
    '--model[Default na model para sa mga session na na-dispatch mula sa agent view]:model:' \
    '--permission-mode[Default na permission mode para sa mga dispatched session]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Mag-load ng mga plugin mula sa direktoryo para sa agent view at mga dispatched session]:path:_directories' \
    '--setting-sources[Listahan ng mga setting source na pinaghihiwalay ng kuwit para i-load (user, project, local)]:sources:' \
    '--settings[Settings file o JSON string na ilalapat]:file-or-json:_files' \
    '--strict-mcp-config[Gumamit lang ng mga MCP server mula sa --mcp-config sa mga dispatched session]' \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Mag-sign in sa iyong Anthropic account'
    'logout:Mag-log out mula sa iyong Anthropic account'
    'status:Ipakita ang status ng authentication'
    'help:Ipakita ang tulong'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'mga auth command' auth_commands
      ;;
    args)
      case $words[1] in
        login|logout|status)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:I-print ang epektibong auto mode config bilang JSON'
    'critique:Kumuha ng AI feedback sa iyong mga custom auto mode rule'
    'defaults:I-print ang mga default auto mode rule bilang JSON'
    'reset:I-reset ang auto mode configuration sa mga ipinadalang default'
    'help:Ipakita ang tulong'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'mga auto-mode command' auto_mode_commands
      ;;
    args)
      case $words[1] in
        config|critique|defaults|reset)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Path sa gateway YAML config]:path:_files' \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Burahin ang lahat ng Claude Code state para sa isang project (mga transcript, task, file history, config entry)'
    'help:Ipakita ang tulong'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'mga project command' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[I-print ang raw bugs.json payload sa halip na mga naka-format na natuklasan]' \
    '--timeout[Pinakamataas na minuto na hihintayin para matapos ang review]:minutes:' \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
