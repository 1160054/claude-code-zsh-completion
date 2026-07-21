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
    'mcp:Configure and manage MCP servers'
    'plugin:Manage Claude Code plugins'
    'agents:Laola diagente tse sebetsang ka morao'
    'auth:Laola netefatso'
    'auto-mode:Hlahloba kapa u khutlisetse tlhophiso ya sehlophi sa mokgwa wa auto'
    'gateway:Matha gateway ya netefatso/telemetry ya kgwebo'
    'project:Laola boemo ba morero wa Claude Code'
    'ultrareview:Matha tlhahlobo ya khoutu ya diagente-tse-ngata e tsamaisang lerung mme u hatise diphumano'
    'setup-token:Set up long-term authentication token (requires Claude subscription)'
    'doctor:Health check for Claude Code auto-updater'
    'update:Check for and install updates'
    'install:Install Claude Code native build'
  )

  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Enable debug mode with optional category filtering (e.g., "api,hooks" or "!statsig,!file")]:filter:'
    '--verbose[Override verbose mode setting from config file]'
    '(-p --print)'{-p,--print}'[Print response and exit (for use with pipes). Note: use only in trusted directories]'
    '--output-format[Output format (with --print): "text" (default), "json" (single result), or "stream-json" (real-time streaming)]:format:(text json stream-json)'
    '--json-schema[JSON schema for structured output validation]:schema:'
    '--include-partial-messages[Include partial message chunks as they arrive (with --print and --output-format=stream-json)]'
    '--input-format[Input format (with --print): "text" (default) or "stream-json" (real-time streaming input)]:format:(text stream-json)'
    '--mcp-debug[\[Deprecated. Use --debug instead\] Enable MCP debug mode (shows MCP server errors)]'
    '--dangerously-skip-permissions[Bypass all permission checks. Recommended only for sandboxes without internet access]'
    '--allow-dangerously-skip-permissions[Enable option to bypass permission checks without enabling by default]'
    '--max-budget-usd[Palo e phahameng ya didolara tseo u ka di sebedisang ho mehala ya API (--print feela)]:amount:'
    '--replay-user-messages[Re-send user messages from stdin on stdout for confirmation]'
    '--allowed-tools[Comma or space-separated list of allowed tool names (e.g., "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Comma or space-separated list of allowed tool names (camelCase format)]:tools:'
    '--tools[Specify list of available tools from built-in set. Print mode only]:tools:'
    '--disallowed-tools[Comma or space-separated list of disallowed tool names (e.g., "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Comma or space-separated list of disallowed tool names (camelCase format)]:tools:'
    '--mcp-config[Load MCP servers from JSON file or string (space-separated)]:configs:'
    '--system-prompt[System prompt to use for session]:prompt:'
    '--append-system-prompt[Append system prompt to default system prompt]:prompt:'
    '--permission-mode[Permission mode to use for session]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Continue the most recent conversation]'
    '(-r --resume)'{-r,--resume}'[Resume a conversation - specify session ID or select interactively]:sessionId:_claude_sessions'
    '--fork-session[Create new session ID instead of reusing original session ID when resuming (with --resume or --continue)]'
    '--no-session-persistence[Thibela ho boloka seboka - diboka di ke ke tsa bolokwa (--print feela)]'
    '--model[Model for current session. Specify alias for latest model (e.g., '\''sonnet'\'' or '\''opus'\'')]:model:'
    '--agent[Agente bakeng sa seboka sa hona joale. E fetola tlhophiso ya '\''agent'\'']:agent:'
    '--betas[Di-header tsa beta tse kenyeletswang dikopong tsa API (basebedisi ba senotlolo sa API feela)]:betas:'
    '--fallback-model[Enable automatic fallback to specified model when default model is overloaded (--print only)]:model:'
    '--settings[Path to settings JSON file or JSON string to load additional settings]:file-or-json:_files'
    '--add-dir[Additional directories to allow tool access]:directories:_directories'
    '--ide[Auto-connect to IDE on startup if exactly one valid IDE is available]'
    '--strict-mcp-config[Use only MCP servers from --mcp-config and ignore all other MCP settings]'
    '--session-id[Specific session ID to use for conversation (must be valid UUID)]:uuid:'
    '--agents[JSON object defining custom agents]:json:'
    '--setting-sources[Comma-separated list of setting sources to load (user, project, local)]:sources:'
    '--plugin-dir[Directory to load plugins from for this session only (repeatable)]:paths:_directories'
    '--disable-slash-commands[Thibela ditaelo tsohle tsa slash]'
    '(--bg --background)'{--bg,--background}'[Qala seboka e le agente ya morao mme u kgutle hang-hang]'
    '(-w --worktree)'{-w,--worktree}'[Theha worktree e ncha ya git bakeng sa seboka sena (ka boikgethelo bolela lebitso)]::name:'
    '--tmux[Theha seboka sa tmux bakeng sa worktree (e hloka --worktree)]'
    '(-n --name)'{-n,--name}'[Beha lebitso le bontshwang la seboka sena]:name:'
    '--effort[Boemo ba boiteko bakeng sa seboka sa hona joale]:level:(low medium high xhigh max)'
    '--debug-file[Ngola direkoto tsa debug tseleng e itseng ya faele (e nolofatsa mokgwa wa debug ka bofihlehi)]:path:_files'
    '--from-pr[Tsosolosa seboka se amanang le PR ka nomoro/URL, kapa bula sekgethi se sebedisanang]::value:'
    '--remote-control[Qala seboka se sebedisanang ka Remote Control e nolofaditsweng (ka boikgethelo le nang le lebitso)]::name:'
    '--remote-control-session-name-prefix[Sehlonghwa sa mabitso a diboka tsa Remote Control a iketsahallang]:prefix:'
    '--chrome[Nolofatsa kopano ya Claude ho Chrome]'
    '--no-chrome[Thibela kopano ya Claude ho Chrome]'
    '--plugin-url[Lata .zip ya plugin ho tswa URL bakeng sa seboka sena feela (e ka pheta-phetwa)]:url:'
    '--file[Disebediswa tsa faele tse tla jarolotswa qalong (sebopeho: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Nolofatsa ditlhahiso tsa prompt (e ntsha prompt e latelang e boletsweng esale pele mokgweng wa print/SDK)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Fetisetsa mongolo wa subagent le diblock tsa monahano e le melaetsa (ka --print le stream-json)]'
    '--include-hook-events[Kenyeletsa diketsahalo tsohle tsa bophelo ba hook phallong ya tswaho (ka stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Fallisetsa dikarolo tsa mochine ka mong molaetseng wa pele wa mosebedisi ho ntlafatsa tshebediso-bocha ya prompt-cache]'
    '--brief[Nolofatsa sesebediswa sa SendUserMessage bakeng sa puisano ya agente-ho-mosebedisi]'
    '--safe-mode[Qala ka ditlhophiso tsohle tsa botho di thibetswe (e thusa ho rarolla tlhophiso e senyehileng)]'
    '--bare[Mokgwa o fokolang: tlola di-hook, LSP, plugin sync, attribution, auto-memory, le CLAUDE.md auto-discovery]'
    '--ax-screen-reader[Hlahisa tswaho e loketseng sebadi sa skrine (mongolo o bataletseng, ntle le mehala ya mokgabiso kapa dianimation)]'
    '(-v --version)'{-v,--version}'[Output version number]'
    '(-h --help)'{-h,--help}'[Display help for command]'
  )

  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'ditaelo tsa claude' main_commands
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
          _message "ha ho na diparamethara"
          ;;
      esac
      ;;
  esac
}

_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Start a Claude Code MCP server'
    'add:Add an MCP server to Claude Code'
    'remove:Remove an MCP server'
    'list:List configured MCP servers'
    'get:Get MCP server details'
    'add-json:Add an MCP server (stdio or SSE) with JSON string'
    'add-from-claude-desktop:Import MCP servers from Claude Desktop (Mac and WSL only)'
    'reset-project-choices:Reset all approved/rejected project-scoped (.mcp.json) servers in this project'
    'login:Netefatsa ka seva sa MCP (HTTP, SSE, kapa sehokelo sa claude.ai)'
    'logout:Hlakola bopaki ba OAuth bo bolokilweng bakeng sa seva sa MCP'
    'help:Display help'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Display help]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'ditaelo tsa mcp' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Enable debug mode]' \
            '--verbose[Override verbose mode setting from config file]' \
            '(-h --help)'{-h,--help}'[Display help]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Config scope (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Transport type (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Set environment variable (e.g., -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Set WebSocket header]:header:' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Config scope (local, user, project) - remove from existing scope if unspecified]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Config scope (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Config scope (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Display help]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help]'
          ;;
        login|logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:name:_claude_mcp_servers'
          ;;
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Validate a plugin or marketplace manifest'
    'marketplace:Manage Claude Code marketplaces'
    'list:Thathamisa di-plugin tse kentsweng'
    'details:Bontsha lethathamo la dikarolo le tjhelete e lekanyeditsweng ya di-token bakeng sa plugin'
    'install:Install a plugin from available marketplaces'
    'i:Install a plugin from available marketplaces (short for install)'
    'init:Theha plugin e ncha (e kenngwa ka bomo sebokeng se latelang)'
    'uninstall:Uninstall an installed plugin'
    'remove:Uninstall an installed plugin (alias for uninstall)'
    'enable:Enable a disabled plugin'
    'disable:Disable an enabled plugin'
    'update:Ntlafatsa plugin ho phetolelo ya ho qetela'
    'eval:Matha dinyewe tsa eval khahlanong le plugin mme u tlalehe diphetho tse lekantsweng'
    'prune:Tlosa dintho tse itshetlehileng tse kentsweng ka bomo tse seng di sa hlokahale'
    'tag:Theha git tag ya {name}--v{version} bakeng sa tokollo ya plugin'
    'help:Display help'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Display help]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'ditaelo tsa plugin' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Bophara ba ho kenya]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Bophara ba ho kenya]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Bophara ba ho kenya]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Bophara ba ho kenya]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:path:_files'
          ;;
      esac
      ;;
  esac
}

_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Add a marketplace from URL, path, or GitHub repository'
    'list:List configured marketplaces'
    'remove:Remove a configured marketplace'
    'rm:Remove a configured marketplace (alias for remove)'
    'update:Update marketplace from source - update all if no name specified'
    'help:Display help'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Display help]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'ditaelo tsa mmaraka' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help]'
          ;;
        remove|rm)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}

_claude_install() {
  _arguments \
    '--force[Force install even if already installed]' \
    '(-h --help)'{-h,--help}'[Display help]' \
    '::target:(stable latest)'
}

_claude_agents() {
  _arguments \
    '*--add-dir[Tateletso e eketsehileng ya ho dumella phihlello ya sesebediswa dibokeng tse rometsweng]:directory:_directories' \
    '--agent[Agente ka tlhaho bakeng sa diboka tse rometsweng ho tswa ponong ya agente]:agent:' \
    '--all[Ka --json: kenyeletsa le diboka tsa morao tse phethilweng]' \
    '--allow-dangerously-skip-permissions[Etsa hore mokgwa wa bypass-permissions o fumanehe dibokeng tse rometsweng]' \
    '--cwd[Bontsha feela diboka tsa morao tse qadilweng tlasa tsela]:path:_directories' \
    '--dangerously-skip-permissions[Lebitso le leng la --permission-mode bypassPermissions]' \
    '--effort[Boemo ba boiteko ka tlhaho bakeng sa diboka tse rometsweng]:level:(low medium high xhigh max)' \
    '--json[Hatisa diboka tse sebetsang e le array ya JSON mme u tswe]' \
    '*--mcp-config[Tlhophiso ya seva sa MCP e sebediswang dibokeng tse rometsweng]:config:' \
    '--model[Mmotlolo ka tlhaho bakeng sa diboka tse rometsweng ho tswa ponong ya agente]:model:' \
    '--permission-mode[Mokgwa wa tumello ka tlhaho bakeng sa diboka tse rometsweng]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Kenya di-plugin ho tswa tatelanong bakeng sa pono ya agente le diboka tse rometsweng]:path:_directories' \
    '--setting-sources[Lethathamo le arohaneng ka dikoma la mehlodi ya ditlhophiso e tla kenngwa (user, project, local)]:sources:' \
    '--settings[Faele ya ditlhophiso kapa string ya JSON e sebediswang]:file-or-json:_files' \
    '--strict-mcp-config[Sebedisa feela diseva tsa MCP tse tswang --mcp-config dibokeng tse rometsweng]' \
    '(-h --help)'{-h,--help}'[Display help for command]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Kena ho akhaonto ya hao ya Anthropic'
    'logout:Tswa ho akhaonto ya hao ya Anthropic'
    'status:Bontsha boemo ba netefatso'
    'help:Display help'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Display help for command]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'ditaelo tsa netefatso' auth_commands
      ;;
    args)
      case $words[1] in
        login|logout|status)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help for command]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Hatisa tlhophiso e sebetsang ya mokgwa wa auto e le JSON'
    'critique:Fumana maikutlo a AI ka melao ya hao ya mokgwa wa auto ya botho'
    'defaults:Hatisa melao ya mokgwa wa auto ya tlhaho e le JSON'
    'reset:Khutlisetsa tlhophiso ya mokgwa wa auto ho ditlhaho tse rometsweng'
    'help:Display help'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Display help for command]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'ditaelo tsa auto-mode' auto_mode_commands
      ;;
    args)
      case $words[1] in
        config|critique|defaults|reset)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help for command]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Tsela ya tlhophiso ya YAML ya gateway]:path:_files' \
    '(-h --help)'{-h,--help}'[Display help for command]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Hlakola boemo bohle ba Claude Code bakeng sa morero (ditranskripta, mesebetsi, histori ya faele, kenyo ya tlhophiso)'
    'help:Display help'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Display help for command]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'ditaelo tsa morero' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help for command]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Hatisa payload ya bugs.json e sa lokiswang sebakeng sa diphumano tse hlophisitsweng]' \
    '--timeout[Metsotso e mengata ka ho fetisisa ya ho emela hore tlhahlobo e fele]:minutes:' \
    '(-h --help)'{-h,--help}'[Display help for command]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
