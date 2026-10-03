#compdef claude

# Dynamic completion functions

# Directories Claude Code keeps its state in (agents, plugins, sessions).
# CLAUDE_CONFIG_DIR replaces the default location when it is set.
_claude_state_dirs() {
  if [[ -n "$CLAUDE_CONFIG_DIR" ]]; then
    print -r -- "$CLAUDE_CONFIG_DIR"
  else
    print -l -- "$HOME/.claude" "$HOME/.config/claude"
  fi
}

# JSON files that may hold MCP server definitions.
_claude_config_files() {
  if [[ -n "$CLAUDE_CONFIG_DIR" ]]; then
    print -l -- "$CLAUDE_CONFIG_DIR/.claude.json" "$CLAUDE_CONFIG_DIR/mcp.json"
  else
    print -l -- "$HOME/.claude.json" "$HOME/.claude/mcp.json" "$HOME/.config/claude/mcp.json"
  fi
}

_claude_mcp_servers() {
  local config_file
  local -a server_list

  # Parse config files using grep/sed (no external dependencies)
  for config_file in ${(f)"$(_claude_config_files)"}; do
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
  local state_dir manifest

  # Installed plugins are "name@marketplace" keys in
  # plugins/installed_plugins.json - the directories beside it are caches.
  for state_dir in ${(f)"$(_claude_state_dirs)"}; do
    manifest="$state_dir/plugins/installed_plugins.json"
    [[ -f "$manifest" ]] || continue
    plugins+=(${(f)"$(grep -oE '"[^"]+@[^"]+"[[:space:]]*:' "$manifest" 2>/dev/null | \
      sed 's/[[:space:]]*:$//; s/"//g')"})
  done

  plugins=(${(u)plugins})

  compadd -a plugins
}

_claude_sessions() {
  setopt localoptions extendedglob

  local -a sessions project_dirs
  local state_dir project_dir cwd session_file uuid summary

  # Sessions live under <config>/projects/<cwd with / and . turned into ->.
  # A symlinked working directory is recorded under its resolved path, so
  # try that as well as the one the shell reports.
  for cwd in "$PWD" "${PWD:A}"; do
    project_dirs+=(${${cwd//\//-}//./-})
  done
  project_dirs=(${(u)project_dirs})

  for state_dir in ${(f)"$(_claude_state_dirs)"}; do
    for project_dir in $project_dirs; do
      [[ -d "$state_dir/projects/$project_dir" ]] || continue

      # Newest first, capped so completion stays instant on long-lived projects
      for session_file in ${state_dir}/projects/${project_dir}/*.jsonl(Nom[1,20]); do
        uuid=${session_file:t:r}
        [[ $uuid == [0-9a-f](#c8)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c12) ]] || continue

        # Describe each session by the name it was given (/rename or --name),
        # else by the first thing you typed in it. A name is appended near the
        # end of the transcript and the first message sits at the start, so
        # only those ends are read - these files grow into the megabytes.
        summary=$(tail -c 100000 "$session_file" 2>/dev/null | \
          grep -o '"customTitle":"[^"]*"' 2>/dev/null | tail -1 | \
          sed 's/^"customTitle":"//; s/"$//')
        if [[ -z $summary ]]; then
          summary=$(head -c 200000 "$session_file" 2>/dev/null | \
            grep -m 1 -o '"role":"user","content":"[^"]\{1,60\}' 2>/dev/null | \
            sed 's/.*"content":"//; s/\\n/ /g; s/\\*$//')
        fi
        sessions+=("${uuid}:${summary:-no description}")
      done
    done
  done

  _describe -t sessions 'session' sessions
}

_claude_agent_names() {
  local -a agents agent_dirs
  local state_dir agent_dir agent_file name

  # User-level and project-level agent definitions
  for state_dir in ${(f)"$(_claude_state_dirs)"}; do
    agent_dirs+=("$state_dir/agents")
  done
  agent_dirs+=(.claude/agents)

  for agent_dir in $agent_dirs; do
    [[ -d "$agent_dir" ]] || continue

    for agent_file in ${agent_dir}/*.md(N); do
      # Prefer the name declared in the front matter, fall back to the filename
      name=$(sed -n '1,10{s/^name:[[:space:]]*\([^[:space:]]*\).*/\1/p;}' "$agent_file" 2>/dev/null | head -1)
      agents+=(${name:-${agent_file:t:r}})
    done
  done

  agents=(${(u)agents})

  compadd -a agents
}

_claude_background_sessions() {
  local -a sessions state_files
  local -A names states
  local state_dir state_file line id rest

  # Background sessions (`claude --bg`) live in <config>/jobs/<id>/, where
  # <id> is the short id that attach, logs, stop, respawn and rm take.
  for state_dir in ${(f)"$(_claude_state_dirs)"}; do
    # Newest first
    state_files=(${state_dir}/jobs/*/state.json(Nom))
    (( ${#state_files} )) || continue

    # One grep for all of them; the first "name" and "state" it reports for a
    # file are that file's top-level ones
    names=() states=()
    for line in ${(f)"$(grep -HoE '"(name|state)"[[:space:]]*:[[:space:]]*"[^"]*"' $state_files 2>/dev/null)"}; do
      id=${${line%%/state.json:*}:t}
      rest=${line#*/state.json:}
      case $rest in
        \"name\"*)  [[ -z $names[$id] ]]  && names[$id]=${${rest#*:*\"}%\"} ;;
        \"state\"*) [[ -z $states[$id] ]] && states[$id]=${${rest#*:*\"}%\"} ;;
      esac
    done

    for state_file in $state_files; do
      id=${state_file:h:t}
      sessions+=("${id}:${names[$id]:-no name}${states[$id]:+ (${states[$id]})}")
    done
  done

  _describe -t sessions 'background session' sessions
}

_claude_model_names() {
  local -a models config_files
  local state_dir config_file

  # Aliases always resolve to the latest model of that family
  models=(default fable opus sonnet haiku)

  # Full model names the user has already configured
  for state_dir in ${(f)"$(_claude_state_dirs)"}; do
    config_files+=("$state_dir/settings.json" "$state_dir/settings.local.json")
  done
  config_files+=(${(f)"$(_claude_config_files)"})

  for config_file in $config_files; do
    [[ -f "$config_file" ]] || continue
    models+=(${(f)"$(grep -oE '"(model|fallbackModel)"[[:space:]]*:[[:space:]]*"[^"]+"' "$config_file" 2>/dev/null | \
      sed 's/.*:[[:space:]]*"\([^"]*\)"/\1/')"})
  done

  # Remove duplicates
  models=(${(u)models})

  compadd -a models
}

_claude() {
  local curcontext="$curcontext" state line
  typeset -A opt_args

  local -a main_commands
  main_commands=(
    'mcp:Configure and manage MCP servers'
    'plugin:Manage Claude Code plugins'
    'agents:Laola diagente tse sebetsang ka morao'
    'attach:Bula seboka sa morao terminaleng ena'
    'logs:Hatisa tswaho ya morao-rao ya terminale ya seboka sa morao'
    'stop:Emisa seboka sa morao (puisano ya sona e a bolokwa)'
    'respawn:Qala hape seboka sa morao hore se sebedise phetolelo ya hona joale ya Claude Code'
    'rm:Hlakola seboka sa morao, le worktree ya sona ha ho bolokehile'
    'auth:Laola netefatso'
    'auto-mode:Hlahloba kapa u khutlisetse tlhophiso ya sehlophi sa mokgwa wa auto'
    'gateway:Matha gateway ya netefatso/telemetry ya kgwebo'
    'import:Kenya tlhophiso ho tswa ho agente e nngwe ya AI ya ho ngola khoutu ho Claude Code'
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
    '--restricted[Mokgwa o thibetsweng: tlosa disebediswa tse mathang ditaelo kapa khoutu le WebFetch, hlokomoloha ditlhophiso tsa user/project/local, mme u lekanyetse disebediswa tsa faele ho ditatelano tsa mosebetsi]'
    '--max-budget-usd[Palo e phahameng ya didolara tseo u ka di sebedisang ho mehala ya API (--print feela)]:amount:'
    '--replay-user-messages[Re-send user messages from stdin on stdout for confirmation]'
    '--allowed-tools[Comma or space-separated list of allowed tool names (e.g., "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Comma or space-separated list of allowed tool names (camelCase format)]:tools:'
    '--tools[Specify list of available tools from built-in set. Print mode only]:tools:'
    '--disallowed-tools[Comma or space-separated list of disallowed tool names (e.g., "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Comma or space-separated list of disallowed tool names (camelCase format)]:tools:'
    '--mcp-config[Load MCP servers from JSON file or string (space-separated)]:configs:'
    '--system-prompt[System prompt to use for session]:prompt:'
    '--system-prompt-file[Bala prompt ya sistimi ho tswa faeleng]:file:_files'
    '--append-system-prompt[Append system prompt to default system prompt]:prompt:'
    '--append-system-prompt-file[Bala prompt ya sistimi ho tswa faeleng mme u e eketse ho prompt ya sistimi ya tlhaho]:file:_files'
    '--system-prompt-snapshot[Rekota prompt ya sistimi hang ka puisano mme u e sebedise hape ka ho tshwana hantle kopong e nngwe le e nngwe le tsosolosong (on, ka tlhaho) kapa u e hlahise bocha kopong e nngwe le e nngwe (off)]:mode:(on off)'
    '--permission-mode[Permission mode to use for session]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Ke mang ya arabang dikopo tsa tumello ka --print: "host" (host ya SDK kapa --permission-prompt-tool) kapa "none" (eng kapa eng e neng e tla kopa e a hanwa)]:target:(host none)'
    '--permission-prompt-tool[Sesebediswa sa MCP se sebediswang bakeng sa dikopo tsa tumello (--print feela)]:tool:'
    '(-c --continue)'{-c,--continue}'[Continue the most recent conversation]'
    '(-r --resume)'{-r,--resume}'[Resume a conversation - specify session ID or select interactively]:sessionId:_claude_sessions'
    '--fork-session[Create new session ID instead of reusing original session ID when resuming (with --resume or --continue)]'
    '--no-session-persistence[Thibela ho boloka seboka - diboka di ke ke tsa bolokwa (--print feela)]'
    '--model[Model for current session. Specify alias for latest model (e.g., '\''sonnet'\'' or '\''opus'\'')]:model:_claude_model_names'
    '--agent[Agente bakeng sa seboka sa hona joale. E fetola tlhophiso ya '\''agent'\'']:agent:_claude_agent_names'
    '--betas[Di-header tsa beta tse kenyeletswang dikopong tsa API (basebedisi ba senotlolo sa API feela)]:betas:'
    '--fallback-model[Enable automatic fallback to specified model when default model is overloaded (--print only)]:model:_claude_model_names'
    '--settings[Path to settings JSON file or JSON string to load additional settings]:file-or-json:_files'
    '--add-dir[Additional directories to allow tool access]:directories:_directories'
    '--ide[Auto-connect to IDE on startup if exactly one valid IDE is available]'
    '--desktop[Bula ka app ya Claude Desktop sebakeng sa terminale (ka --continue kapa --resume <id> ho kgetha seboka)]'
    '--strict-mcp-config[Use only MCP servers from --mcp-config and ignore all other MCP settings]'
    '--session-id[Specific session ID to use for conversation (must be valid UUID)]:uuid:'
    '--agents[JSON object defining custom agents]:json:'
    '--setting-sources[Comma-separated list of setting sources to load (user, project, local)]:sources:'
    '--plugin-dir[Directory to load plugins from for this session only (repeatable)]:paths:_directories'
    '--disable-slash-commands[Thibela ditaelo tsohle tsa slash]'
    '(--bg --background)'{--bg,--background}'[Qala seboka e le agente ya morao mme u kgutle hang-hang]'
    '(-w --worktree)'{-w,--worktree}'[Theha worktree e ncha ya git bakeng sa seboka sena (ka boikgethelo bolela lebitso)]::name:'
    '--tmux=-[Theha seboka sa tmux bakeng sa worktree (e hloka --worktree). E sebedisa dipane tsa tlhaho tsa iTerm2 ha di fumaneha; --tmux=classic bakeng sa tmux ya setso]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Beha lebitso le bontshwang la seboka sena]:name:'
    '--effort[Boemo ba boiteko bakeng sa seboka sa hona joale]:level:(low medium high xhigh max)'
    '--autocompact[Boholo ba fensetere ya auto-compact (auto, kapa di-token tse 100k-1M)]:size:(auto)'
    '--debug-file[Ngola direkoto tsa debug tseleng e itseng ya faele (e nolofatsa mokgwa wa debug ka bofihlehi)]:path:_files'
    '--from-pr[Tsosolosa seboka se amanang le PR ka nomoro/URL, kapa bula sekgethi se sebedisanang]::value:'
    '--teleport[Tsosolosa seboka sa teleport, ka boikgethelo bolela ID ya seboka]::session:'
    '--cloud[Theha seboka sa leru ka tlhaloso e fanweng, kapa o hokahane le se seng se ntse se le teng ka ID ya seboka kapa URL ya claude.ai/code]::description-or-session:'
    '--environment[Theha seboka se setjha sa leru se sebetsang tikolohong e fanweng e tshwarwang ke wena (ccpool_...)]:environment_id:'
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
        attach|logs|stop|kill)
          _arguments \
            '(-h --help)'{-h,--help}'[Bontsha thuso bakeng sa taelo]' \
            '1:session:_claude_background_sessions'
          ;;
        respawn)
          _claude_respawn
          ;;
        rm)
          _claude_rm
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
        import)
          _claude_import
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
            '--client-id[ID ya moreki wa OAuth bakeng sa diseva tsa HTTP/SSE]:clientId:' \
            '--client-secret[Kopa sephiri sa moreki wa OAuth (kapa beha phetoho ya tikoloho ya MCP_CLIENT_SECRET)]' \
            '--callback-port[Port e tsitsitseng bakeng sa callback ya OAuth (bakeng sa diseva tse hlokang di-URI tsa redirect tse ngodisitsweng esale pele)]:port:' \
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
            '--client-secret[Kopa sephiri sa moreki wa OAuth (kapa beha phetoho ya tikoloho ya MCP_CLIENT_SECRET)]' \
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
        login)
          _arguments \
            '--no-browser[Hatisa URL ya tumello sebakeng sa ho bula sebadi sa marang-rang (bakeng sa diboka tsa SSH/headless)]' \
            '(-h --help)'{-h,--help}'[Bontsha thuso]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
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
    'configure:Bontsha dikgetho tsa plugin le hore na ke dife tse sa behwang, kapa boloka boleng ho tswa stdin'
    'install:Install a plugin from available marketplaces'
    'i:Install a plugin from available marketplaces (short for install)'
    'init:Theha plugin e ncha (e kenngwa ka boiketsetso sebokeng se latelang)'
    'new:Haha sebopeho sa plugin e ncha (lebitso le leng la init)'
    'uninstall:Uninstall an installed plugin'
    'remove:Uninstall an installed plugin (alias for uninstall)'
    'enable:Enable a disabled plugin'
    'disable:Disable an enabled plugin'
    'update:Ntlafatsa plugin ho phetolelo ya ho qetela'
    'eval:Matha dinyewe tsa eval khahlanong le plugin mme u tlalehe diphetho tse lekantsweng'
    'prune:Tlosa dintho tse itshetlehileng tse kentsweng ka boiketsetso tse seng di sa hlokahale'
    'autoremove:Tlosa dintho tse itshetlehileng tse kentsweng ka boiketsetso tse seng di sa hlokahale (lebitso le leng la prune)'
    'tag:Theha git tag ya {name}--v{version} bakeng sa tokollo ya plugin'
    'test:Matha diteko tsa mod'
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
            '--strict[Nka ditemoso e le diphoso (khoutu ya ho tswa 1)]' \
            '--json[Hlahisa tlaleho ya netefatso e le JSON (dikhoutu tsa ho tswa tse tshwanang)]' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Bophara ba ho kenya]:scope:(user project local)' \
            '*--config[Beha kgetho ya userConfig e phatlaladitsweng ho manifest ya plugin (e ka pheta-phetwa)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[Amohela taelo e bontshitsweng e phatlaladitsweng ke mmaraka ntle le kopo ya netefatso]' \
            '--json[Hatisa mola o le mong wa sephetho o balehang ke mochine sebakeng sa molaetsa wa motho]' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Bophara ba ho kenya]:scope:(user project local)' \
            '--keep-data[Boloka tatelano ya data e tsitsitseng ya plugin]' \
            '--prune[Tlosa hape dintho tse itshetlehileng tse kentsweng ka boiketsetso tse seng di sa hlokahale]' \
            '(-y --yes)'{-y,--yes}'[Tlola kopo ya netefatso ya --prune]' \
            '--json[Hatisa mola o le mong wa sephetho o balehang ke mochine sebakeng sa molaetsa wa motho (eseng ka --prune)]' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Bophara ba ho kenya]:scope:(user project local)' \
            '--json[Hatisa mola o le mong wa sephetho o balehang ke mochine sebakeng sa molaetsa wa motho]' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Thibela di-plugin tsohle tse nolofaditsweng]' \
            '(-s --scope)'{-s,--scope}'[Bophara ba ho kenya]:scope:(user project local)' \
            '--json[Hatisa mola o le mong wa sephetho o balehang ke mochine sebakeng sa molaetsa wa motho]' \
            '(-h --help)'{-h,--help}'[Bontsha thuso]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Bophara ba ho kenya]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Amohela taelo e bontshitsweng e phatlaladitsweng ke mmaraka ntle le kopo ya netefatso]' \
            '--json[Hatisa mola o le mong wa sephetho o balehang ke mochine sebakeng sa molaetsa wa motho]' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Hlahisa e le JSON]' \
            '--available[Kenyeletsa di-plugin tse fumanehang ho tswa mebarakeng (e hloka --json)]' \
            '(-h --help)'{-h,--help}'[Display help]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Hlwekisa ho bophara]:scope:(user project local)' \
            '--dry-run[Thathamisa se neng se tla tloswa ntle le ho tlosa]' \
            '(-y --yes)'{-y,--yes}'[Tlola kopo ya netefatso]' \
            '(-h --help)'{-h,--help}'[Bontsha thuso]'
          ;;
        configure)
          _arguments \
            '--json[Hlahisa e le JSON]' \
            '--values-stdin[Bala boleng ba dikgetho ho tswa stdin e le ntho ya JSON ya di-string tsa mola o le mong; dikgetho tse siuweng di boloka boleng ba tsona]' \
            '(-h --help)'{-h,--help}'[Bontsha thuso]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Tlhaloso ya manifest]:text:' \
            '--author[Lebitso la mongodi (ka tlhaho: git config user.name)]:name:' \
            '--author-email[Imeile ya mongodi (ka tlhaho: git config user.email)]:email:' \
            '--with[Dikarolo tseo le tsona di tla hahelwa sebopeho]:components:' \
            '(-f --force)'{-f,--force}'[Ngola hodima .claude-plugin/ e seng e le teng sebakeng se lebisitsweng]' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Sefa dinyewe ka glob ya lebitso]:glob:' \
            '*--tag[Sefa dinyewe ka tag (e ka pheta-phetwa)]:tag:' \
            '--runs[Fetola palo ya ho matha ka nyewe ka nngwe (ka tlhaho: case.runs, ho seng jwalo 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Matha ho fihlela ho ditshebetso tse n tsa agente ka nako e le nngwe (1-8; ka tlhaho 1)]:n:' \
            '--model[Fetola mmotlolo bakeng sa dinyewe tsohle]:model:_claude_model_names' \
            '--judge-model[Fetola mmotlolo wa mohlahlobi wa LLM (ka tlhaho: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Moedi o thata wa ditshenyehelo; emisa mme u tlalehe diphetho tse sa phethehang ha o fihlelwa (khoutu ya ho tswa 2)]:usd:' \
            '--output-dir[Tatelano bakeng sa aggregate-result.json]:dir:_directories' \
            '--eval-dir[Lebitso la tatelano (ka tlase ho plugin) e tshwereng dinyewe tsa eval]:dir:' \
            '--json[Hatisa sephetho se feletseng sa ho matha e le JSON ho stdout, kapa u se ngole faeleng ena ya .json]::path:_files' \
            '--threshold[Tswa ka khoutu ya ho tswa 1 haeba dintlha tsa nyewe efe kapa efe di le ka tlase ho moedi ona (ka tlhaho: 1.0)]:threshold:' \
            '*--allow-tools[Tumello ya mosebetsisi bakeng sa disebediswa tse thibetsweng (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Matha scaffold_script ya nyewe ka nngwe (e matha bash e fanweng ke mongodi tlasa akhaonto ya hao; e timilwe ka tlhaho)]' \
            '(--scaffold)--no-scaffold[Tlola scaffold_script ka ho hlaka]' \
            '--trust-plugin[Tiisa hore o tshepa plugin ena le sehlopha sa yona sa eval, o tlola kopo ya tshepo ya ho matha ha pele (bakeng sa CI)]' \
            '--ablation[Matha sehlopha sa papiso sa motheo se se nang plugin mme u tlalehe phapang ya dintlha]:mode:(none with-without)' \
            '--mocks[Baemedi ba maiketsetso bakeng sa diseva tsa MCP, ho tswa <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Ka --mocks record: qala hape ditshebetso tsa sebele tsa diseva tsa MCP tse se nang moemedi wa maiketsetso]' \
            '--keep-temp[Boloka ditatelano tsa sebopeho bakeng sa debug]' \
            '--verbose[Ngola diketsahalo tsa trace tsa molaetsa ka mong rekotong ya debug]' \
            '--report[Ngola tlaleho ya HTML e ikemetseng tseleng ena sebakeng sa tatelano ya diphetho]:path:_files' \
            '(--no-publish)--publish-report[Hloka hape ho phatlalatsa tlaleho ho claude.ai]' \
            '(--publish-report)--no-publish[Boloka tlaleho ya HTML sebakeng sa heno feela; tlola ho e phatlalatsa ho claude.ai]' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Romela tag ho --remote ka mora ho e theha]' \
            '--dry-run[Hatisa se neng se tla fuwa tag ntle le ho e theha]' \
            '(-f --force)'{-f,--force}'[Tlola ditlhahlobo tsa sefate sa mosebetsi se nang le diphetoho le tag e seng e le teng]' \
            '(-m --message)'{-m,--message}'[Molaetsa wa tlhaloso ya tag (sebedisa %s bakeng sa phetolelo)]:msg:' \
            '--remote[Remote eo u tla romela ho yona ka --push]:name:' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Bontsha thuso]' \
            '::dir:_directories'
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
            '--sparse[Lekanyetsa checkout ho ditatelano tse itseng ka git sparse-checkout (bakeng sa di-monorepo)]:paths:' \
            '--scope[Moo mmaraka o tla phatlalatswa teng]:scope:(user project local)' \
            '--claudeai[Eketsa mmaraka wa lebitso lena oo claude.ai e o tshwarelang wena]' \
            '(-h --help)'{-h,--help}'[Display help]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Hlahisa e le JSON]' \
            '(-h --help)'{-h,--help}'[Display help]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Tlosa phatlalatso ya mmaraka bopharing bo itseng ba ditlhophiso (e tlohele ho e tlosa bopharing bohle)]:scope:(user project local)' \
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
    '--agent[Agente ka tlhaho bakeng sa diboka tse rometsweng ho tswa ponong ya agente]:agent:_claude_agent_names' \
    '--all[Ka --json: kenyeletsa le diboka tsa morao tse phethilweng]' \
    '--allow-dangerously-skip-permissions[Etsa hore mokgwa wa bypass-permissions o fumanehe dibokeng tse rometsweng]' \
    '--cwd[Bontsha feela diboka tsa morao tse qadilweng tlasa tsela]:path:_directories' \
    '--dangerously-skip-permissions[Lebitso le leng la --permission-mode bypassPermissions]' \
    '--effort[Boemo ba boiteko ka tlhaho bakeng sa diboka tse rometsweng]:level:(low medium high xhigh max)' \
    '--json[Hatisa diboka tse sebetsang e le array ya JSON mme u tswe]' \
    '*--mcp-config[Tlhophiso ya seva sa MCP e sebediswang dibokeng tse rometsweng]:config:' \
    '--model[Mmotlolo ka tlhaho bakeng sa diboka tse rometsweng ho tswa ponong ya agente]:model:_claude_model_names' \
    '--permission-mode[Mokgwa wa tumello ka tlhaho bakeng sa diboka tse rometsweng]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Kenya di-plugin ho tswa tatelanong bakeng sa pono ya agente le diboka tse rometsweng]:path:_directories' \
    '--setting-sources[Lethathamo le arohaneng ka dikoma la mehlodi ya ditlhophiso e tla kenngwa (user, project, local)]:sources:' \
    '--settings[Faele ya ditlhophiso kapa string ya JSON e sebediswang]:file-or-json:_files' \
    '--strict-mcp-config[Sebedisa feela diseva tsa MCP tse tswang --mcp-config dibokeng tse rometsweng]' \
    '--restricted[Qala diboka tse rometsweng ka mokgwa o thibetsweng]' \
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
        login)
          _arguments \
            '--email[Tlatsa aterese ya imeile esale pele leqepheng la ho kena]:email:' \
            '--sso[Qobella phallo ya ho kena ka SSO]' \
            '(--claudeai)--console[Sebedisa Anthropic Console (tefiso ya tshebediso ya API) sebakeng sa peeletso ya Claude]' \
            '(--console)--claudeai[Sebedisa peeletso ya Claude (ka tlhaho)]' \
            '(-h --help)'{-h,--help}'[Bontsha thuso bakeng sa taelo]'
          ;;
        status)
          _arguments \
            '(--text)--json[Hlahisa e le JSON (ka tlhaho)]' \
            '(--json)--text[Hlahisa e le mongolo o balehang ke motho]' \
            '(-h --help)'{-h,--help}'[Bontsha thuso bakeng sa taelo]'
          ;;
        logout)
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
        critique)
          _arguments \
            '--model[Fetola mmotlolo o sebediswang]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Bontsha thuso bakeng sa taelo]'
          ;;
        defaults)
          _arguments \
            '--label[Bontsha feela melao eo leibole ya yona e qalang ka sehlonghwa sena (ho sa natswe ditlhaku tse kgolo kapa tse nyane)]:prefix:' \
            '(-h --help)'{-h,--help}'[Bontsha thuso bakeng sa taelo]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Tlola kopo ya netefatso]' \
            '(-h --help)'{-h,--help}'[Bontsha thuso bakeng sa taelo]'
          ;;
        config)
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
            '--dry-run[Thathamisa se neng se tla hlakolwa ntle le ho hlakola letho]' \
            '(-y --yes)'{-y,--yes}'[Tlola kopo ya netefatso]' \
            '(-i --interactive)'{-i,--interactive}'[Botsa bakeng sa ntho ka nngwe pele o hlakola]' \
            '(1)--all[Hlakola boemo bakeng sa morero o mong le o mong (e ke ke ya sebediswa hammoho le tsela)]' \
            '(-h --help)'{-h,--help}'[Display help for command]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Hatisa payload ya bugs.json e sa lokiswang sebakeng sa diphumano tse hlophisitsweng]' \
    '--timeout[Metsotso e mengata ka ho fetisisa ya ho emela hore tlhahlobo e fele (ka tlhaho: 45)]:minutes:' \
    '(--no-post)--post[Romela diphumano tsa tlhahlobo e phethilweng ho PR tlasa akhaonto ya hao (dipheo tsa PR feela; tlhaloso e le nngwe e tlwaelehileng, eseng tlhahlobo)]' \
    '(--post)--no-post[O se ke wa romela diphumano ho PR (ka tlhaho)]' \
    '(-h --help)'{-h,--help}'[Display help for command]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Qala hape seboka se seng le se seng sa morao se sebetsang]' \
    '(-h --help)'{-h,--help}'[Bontsha thuso bakeng sa taelo]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Lahla hape di-commit tse sa romelwang le diphetoho tse sa etswang commit tsa worktree (fana ka commit@worktree-id eo claude rm ya pejana e e tlalehileng)]:commit@worktree-id:' \
    '--force-remove-worktree[Hlakola tatelano ya worktree le ha hook ya WorktreeRemove kapa git di sa kgona ho e tlosa (fana ka worktree-id eo claude rm ya pejana e e tlalehileng)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Bontsha thuso bakeng sa taelo]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Bontsha se neng se tla kenngwa ntle le ho ngola letho]' \
    '--yes[Tlola sekgethi se sebedisanang (dibakeng tsa headless, fana ka --yes=<digest> ho tswa ponong-pele ya /import)]' \
    '(-h --help)'{-h,--help}'[Bontsha thuso bakeng sa taelo]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
