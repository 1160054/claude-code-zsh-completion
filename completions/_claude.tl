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
    'mcp:I-configure at pamahalaan ang mga MCP server'
    'plugin:Pamahalaan ang mga Claude Code plugin'
    'agents:Pamahalaan ang mga background agent'
    'attach:Buksan ang isang background session sa terminal na ito'
    'logs:I-print ang kamakailang terminal output ng isang background session'
    'stop:Ihinto ang isang background session (pinapanatili ang pag-uusap nito)'
    'respawn:I-restart ang isang background session para patakbuhin nito ang kasalukuyang bersyon ng Claude Code'
    'rm:Burahin ang isang background session, at ang worktree nito kapag ligtas itong gawin'
    'remote-control:Kontrolin ang mga lokal na session mula sa claude.ai/code o sa Claude mobile app'
    'daemon:Pamahalaan ang supervisor ng mga background session'
    'auth:Pamahalaan ang authentication'
    'auto-mode:Suriin o i-reset ang configuration ng auto mode classifier'
    'gateway:Patakbuhin ang enterprise auth/telemetry gateway'
    'self-hosted-runner:Mag-host ng mga Claude Code cloud session sa machine o container na ito'
    'import:Mag-import ng config mula sa ibang AI coding agent papunta sa Claude Code'
    'project:Pamahalaan ang state ng Claude Code project'
    'purge:Burahin ang lahat ng Claude Code state para sa isang project (mga transcript, task, file history, config entry)'
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
    '--dangerously-skip-permissions[Laktawan ang lahat ng permission check. Inirerekomenda lang para sa mga sandbox na walang internet access]'
    '--allow-dangerously-skip-permissions[Paganahin ang opsyon na laktawan ang mga permission check nang hindi pinapagana by default]'
    '--restricted[Restricted mode: alisin ang mga tool na nagpapatakbo ng command o code at ang WebFetch, huwag pansinin ang mga user/project/local setting, at limitahan ang mga file tool sa mga working directory]'
    '--max-budget-usd[Pinakamataas na halaga ng dolyar na gagastusin sa mga API call (--print lang)]:amount:'
    '--max-turns[Limitahan ang bilang ng mga agentic turn (--print lang)]:turns:'
    '--replay-user-messages[Ipadala ulit ang mga mensahe ng user mula sa stdin sa stdout para sa kumpirmasyon]'
    '--allowed-tools[Listahan ng mga pinahihintulutang pangalan ng tool na pinaghihiwalay ng kuwit o espasyo (hal.: "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Listahan ng mga pinahihintulutang pangalan ng tool na pinaghihiwalay ng kuwit o espasyo (camelCase format)]:tools:'
    '--tools[Tukuyin ang listahan ng mga available na tool mula sa built-in set. Print mode lang]:tools:'
    '--disallowed-tools[Listahan ng mga hindi pinahihintulutang pangalan ng tool na pinaghihiwalay ng kuwit o espasyo (hal.: "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Listahan ng mga hindi pinahihintulutang pangalan ng tool na pinaghihiwalay ng kuwit o espasyo (camelCase format)]:tools:'
    '--mcp-config[Mag-load ng mga MCP server mula sa JSON file o string (pinaghihiwalay ng espasyo)]:configs:'
    '--system-prompt[System prompt na gagamitin para sa session]:prompt:'
    '--system-prompt-file[Basahin ang system prompt mula sa isang file]:file:_files'
    '--append-system-prompt[Idagdag ang system prompt sa default system prompt]:prompt:'
    '--append-system-prompt-file[Basahin ang system prompt mula sa isang file at idagdag ito sa default system prompt]:file:_files'
    '(--append-subagent-system-prompt-file)--append-subagent-system-prompt[Magdagdag ng text sa system prompt ng bawat subagent (--print lang)]:prompt:'
    '(--append-subagent-system-prompt)--append-subagent-system-prompt-file[Basahin ang text mula sa isang file at idagdag ito sa mga system prompt ng subagent (--print lang)]:file:_files'
    '--system-prompt-snapshot[I-record ang system prompt nang isang beses bawat pag-uusap at gamitin ulit ito nang eksakto sa bawat request at resume (on, ang default) o i-render ito nang bago sa bawat request (off)]:mode:(on off)'
    '--permission-mode[Permission mode na gagamitin para sa session]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Kung sino ang sasagot sa mga permission prompt kasama ang --print: "host" (ang SDK host o --permission-prompt-tool) o "none" (tinatanggihan ang anumang magpo-prompt)]:target:(host none)'
    '--permission-prompt-tool[MCP tool na gagamitin para sa mga permission prompt (--print lang)]:tool:'
    '(-c --continue)'{-c,--continue}'[Ipagpatuloy ang pinakabagong pag-uusap]'
    '(-r --resume)'{-r,--resume}'[Ipagpatuloy ang isang pag-uusap - tukuyin ang session ID o pumili nang interactive]:sessionId:_claude_sessions'
    '--fork-session[Lumikha ng bagong session ID sa halip na gamitin ulit ang orihinal na session ID kapag nagre-resume (kasama ang --resume o --continue)]'
    '--no-session-persistence[I-disable ang session persistence - hindi mase-save ang mga session (--print lang)]'
    '--model[Model para sa kasalukuyang session. Tukuyin ang alias para sa pinakabagong model (hal.: '\''sonnet'\'' o '\''opus'\'')]:model:_claude_model_names'
    '--agent[Agent para sa kasalukuyang session. I-override ang '\''agent'\'' setting]:agent:_claude_agent_names'
    '--betas[Mga beta header na isasama sa mga API request (mga user ng API key lang)]:betas:'
    '--fallback-model[Paganahin ang awtomatikong fallback sa tinukoy na model kapag ang default model ay overloaded (--print lang)]:model:_claude_model_names'
    '--settings[Path sa settings JSON file o JSON string para mag-load ng karagdagang mga setting]:file-or-json:_files'
    '--add-dir[Karagdagang mga direktoryo para pahintulutan ang tool access]:directories:_directories'
    '--ide[Auto-connect sa IDE sa startup kung eksakto isang valid na IDE ang available]'
    '--desktop[Buksan sa Claude Desktop app sa halip na sa terminal (kasama ang --continue o --resume <id> para piliin ang session)]'
    '--strict-mcp-config[Gumamit lang ng mga MCP server mula sa --mcp-config at huwag pansinin ang lahat ng iba pang MCP setting]'
    '--session-id[Partikular na session ID na gagamitin para sa pag-uusap (dapat valid na UUID)]:uuid:'
    '--agents[JSON object na nagtutukoy ng mga custom agent]:json:'
    '--advisor[Paganahin ang server-side advisor tool para sa session na ito gamit ang model alias o buong model ID]:model:_claude_model_names'
    '--teammate-mode[Paano ipinapakita ang mga teammate ng agent team]:mode:(in-process auto tmux iterm2)'
    '--setting-sources[Listahan ng mga setting source na pinaghihiwalay ng kuwit para i-load (user, project, local)]:sources:'
    '--plugin-dir[Direktoryo kung saan mag-load ng mga plugin para sa session na ito lang (maaaring ulitin)]:paths:_directories'
    '--disable-slash-commands[I-disable ang lahat ng slash command]'
    '(--bg --background)'{--bg,--background}'[Simulan ang session bilang background agent at agad na bumalik]'
    '(-w --worktree)'{-w,--worktree}'[Lumikha ng bagong git worktree para sa session na ito (opsyonal na tukuyin ang pangalan)]::name:'
    '--tmux=-[Lumikha ng tmux session para sa worktree (kailangan ang --worktree). Gumagamit ng iTerm2 native pane kapag available; --tmux=classic para sa tradisyonal na tmux]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Magtakda ng display name para sa session na ito]:name:'
    '--effort[Antas ng effort para sa kasalukuyang session]:level:(low medium high xhigh max)'
    '--autocompact[Laki ng auto-compact window (auto, o 100k-1M token)]:size:(auto)'
    '--debug-file[Isulat ang mga debug log sa isang partikular na file path (awtomatikong pinapagana ang debug mode)]:path:_files'
    '--from-pr[Ipagpatuloy ang session na naka-link sa PR sa pamamagitan ng numero/URL, o buksan ang interactive picker]::value:'
    '--teleport[Ipagpatuloy ang isang teleport session, opsyonal na tukuyin ang session ID]::session:'
    '(--remote)--cloud[Lumikha ng cloud session na may ibinigay na paglalarawan, o kumonekta sa umiiral na session gamit ang session ID o claude.ai/code URL]::description-or-session:'
    '(--cloud)--remote[Deprecated na alyas para sa --cloud]::description-or-session:'
    '--environment[Lumikha ng bagong cloud session na tumatakbo sa ibinigay na self-hosted environment (ccpool_...)]:environment_id:'
    '--ref[Kasama ang --environment: ibatay ang checkout ng bagong session sa isang pinangalanang ref sa halip na sa lokal na HEAD]:branch:'
    '(--remote-control --rc)'{--remote-control,--rc}'[Simulan ang interactive session na may naka-enable na Remote Control (opsyonal na may pangalan)]::name:'
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
    '*--channels[(Research preview) Mga MCP server na pakikinggan ang mga channel notification (plugin\:<name>@<marketplace>)]:entries:'
    '*--dangerously-load-development-channels[Paganahin ang mga channel na wala sa aprubadong allowlist, para sa lokal na development (plugin\:<name>@<marketplace> o server\:<name>)]:entries:'
    '--init[Patakbuhin ang mga Setup hook gamit ang init matcher bago ang session (--print lang)]'
    '--init-only[Patakbuhin ang mga Setup at SessionStart hook, pagkatapos ay lumabas nang hindi nagsisimula ng pag-uusap]'
    '--maintenance[Patakbuhin ang mga Setup hook gamit ang maintenance matcher bago ang session (--print lang)]'
    '--safe-mode[Magsimula na naka-disable ang lahat ng customization (kapaki-pakinabang sa pag-troubleshoot ng sirang configuration)]'
    '--bare[Minimal mode: laktawan ang hooks, LSP, plugin sync, attribution, auto-memory, at CLAUDE.md auto-discovery]'
    '--ax-screen-reader[Mag-render ng output na madaling gamitin sa screen reader (flat na text, walang dekoratibong border o animation)]'
    '(-v --version)'{-v,--version}'[Ilabas ang numero ng bersyon]'
    '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]'
  )

  # Stop at the first non-option word, so that the options after a command reach
  # that command's own specs instead of being consumed here
  _arguments -C -A '-*' \
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
        plugin|plugins)
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
            '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]' \
            '1:session:_claude_background_sessions'
          ;;
        respawn)
          _claude_respawn
          ;;
        rm)
          _claude_rm
          ;;
        remote-control|rc|remote|sync|bridge)
          _claude_remote_control
          ;;
        daemon)
          _claude_daemon
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
        self-hosted-runner)
          _claude_self_hosted_runner
          ;;
        import)
          _claude_import
          ;;
        project)
          _claude_project
          ;;
        purge)
          _claude_purge
          ;;
        ultrareview)
          _claude_ultrareview
          ;;
        setup-token|doctor|update|upgrade)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]'
          ;;
        *)
          # Not a command but the prompt: options may still follow it
          _arguments \
            $main_options \
            '*: :'
          ;;
      esac
      ;;
  esac
  local ret=$?

  # The last step, such as listing commands for --r, can fail although options
  # were added before it. Report success then: on failure zsh moves on to the
  # next completers, and _correct or _approximate pile on corrections
  (( compstate[nmatches] > 0 )) || return $ret
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
            '--client-id[OAuth client ID para sa mga HTTP/SSE server]:clientId:' \
            '--client-secret[Humingi ng OAuth client secret (o itakda ang MCP_CLIENT_SECRET env var)]' \
            '--callback-port[Nakapirming port para sa OAuth callback (para sa mga server na nangangailangan ng mga pre-registered redirect URI)]:port:' \
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
            '--client-secret[Humingi ng OAuth client secret (o itakda ang MCP_CLIENT_SECRET env var)]' \
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
        login)
          _arguments \
            '--no-browser[I-print ang authorization URL sa halip na magbukas ng browser (para sa mga SSH/headless session)]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
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
    'configure:Ipakita ang mga opsyon ng plugin at kung alin ang hindi pa nakatakda, o mag-save ng mga value mula sa stdin'
    'install:Mag-install ng plugin mula sa mga available na marketplace'
    'i:Mag-install ng plugin mula sa mga available na marketplace (maikli para sa install)'
    'init:Mag-scaffold ng bagong plugin (awtomatikong naglo-load sa susunod na session)'
    'new:Mag-scaffold ng bagong plugin (alyas para sa init)'
    'uninstall:I-uninstall ang naka-install na plugin'
    'remove:I-uninstall ang naka-install na plugin (alyas para sa uninstall)'
    'enable:Paganahin ang naka-disable na plugin'
    'disable:I-disable ang naka-enable na plugin'
    'update:I-update ang plugin sa pinakabagong bersyon'
    'eval:Magpatakbo ng mga eval case laban sa plugin at iulat ang mga na-score na resulta'
    'prune:Alisin ang mga awtomatikong na-install na dependency na hindi na kailangan'
    'autoremove:Alisin ang mga awtomatikong na-install na dependency na hindi na kailangan (alyas para sa prune)'
    'tag:Lumikha ng {name}--v{version} git tag para sa isang plugin release'
    'test:Patakbuhin ang mga test ng isang mod'
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
            '--strict[Ituring na error ang mga babala (exit code 1)]' \
            '--profile[Lumabas din nang may exit code 1 kapag tatanggihan ng tinukoy na catalog ang submission ng plugin sa isang check na pinapatakbo ng command na ito]:name:(directory)' \
            '--json[Ilabas ang validation report bilang JSON (parehong mga exit code)]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Saklaw ng pag-install]:scope:(user project local)' \
            '--accept-command[Tanggapin ang command na idineklara ng marketplace na ang sha256 ay iniulat ng nakaraang --json run bilang shownCommand.sha256]:sha256:' \
            '*--config[Itakda ang isang userConfig option na idineklara sa plugin manifest (maaaring ulitin)]:key=value:' \
            '--marketplace[I-install ang plugin ayon sa payak na pangalan nito mula sa marketplace sa source na ito (owner/repo, git o https URL, o path), idinadagdag muna ito kung kailangan]:source:' \
            '--registry[Para sa package@npm install: mag-resolve at mag-download mula sa npm registry na ito]:url:' \
            '(-y --yes)'{-y,--yes}'[Tanggapin ang ipinakitang command na idineklara ng marketplace nang walang confirmation prompt]' \
            '--json[Mag-print ng isang machine-readable na linya ng resulta sa halip na ang mensaheng para sa tao]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Saklaw ng pag-install]:scope:(user project local)' \
            '--keep-data[Panatilihin ang persistent data directory ng plugin]' \
            '--prune[Alisin din ang mga awtomatikong na-install na dependency na hindi na kailangan]' \
            '(-y --yes)'{-y,--yes}'[Laktawan ang confirmation prompt ng --prune]' \
            '--json[Mag-print ng isang machine-readable na linya ng resulta sa halip na ang mensaheng para sa tao (hindi magagamit kasabay ng --prune)]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Saklaw ng pag-install]:scope:(user project local)' \
            '--json[Mag-print ng isang machine-readable na linya ng resulta sa halip na ang mensaheng para sa tao]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[I-disable ang lahat ng naka-enable na plugin]' \
            '(-s --scope)'{-s,--scope}'[Saklaw ng pag-install]:scope:(user project local)' \
            '--json[Mag-print ng isang machine-readable na linya ng resulta sa halip na ang mensaheng para sa tao]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '--accept-command[Tanggapin ang command na idineklara ng marketplace na ang sha256 ay iniulat ng nakaraang --json run bilang shownCommand.sha256]:sha256:' \
            '(-s --scope)'{-s,--scope}'[Saklaw ng pag-install]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Tanggapin ang ipinakitang command na idineklara ng marketplace nang walang confirmation prompt]' \
            '--json[Mag-print ng isang machine-readable na linya ng resulta sa halip na ang mensaheng para sa tao]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Ilabas bilang JSON]' \
            '--available[Isama ang mga available na plugin mula sa mga marketplace (kailangan ang --json)]' \
            '--data-size[Sukatin ang naka-save na data directory ng bawat naka-install na plugin, o ng tinukoy na plugin lang (kailangan ang --json)]::plugin:_claude_installed_plugins' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Mag-prune sa scope]:scope:(user project local)' \
            '--dry-run[Ilista ang aalisin nang hindi talaga nag-aalis]' \
            '(-y --yes)'{-y,--yes}'[Laktawan ang confirmation prompt]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]'
          ;;
        configure)
          _arguments \
            '--json[Ilabas bilang JSON]' \
            '--values-stdin[Basahin ang mga value ng opsyon mula sa stdin bilang JSON object ng mga single-line string; pinapanatili ng mga hindi isinamang opsyon ang kanilang mga value]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Paglalarawan sa manifest]:text:' \
            '--author[Pangalan ng author (default: git config user.name)]:name:' \
            '--author-email[Email ng author (default: git config user.email)]:email:' \
            '--with[Mga component na isa-scaffold din]:components:' \
            '(-f --force)'{-f,--force}'[I-overwrite ang umiiral na .claude-plugin/ sa target]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:name:'
          ;;
        eval)
          if [[ $words[2] == init ]]; then
            _arguments \
              '--bare[Magsulat ng blangkong template sa halip na patakbuhin ang interview]' \
              '--eval-dir[Direktoryo sa ilalim ng kasalukuyang direktoryo kung saan isusulat ang mga case]:dir:_directories' \
              '(-i --interactive)'{-i,--interactive}'[Patakbuhin ang authoring interview (kailangan ng interactive terminal)]' \
              '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
              '::name:'
            return
          fi
          _arguments \
            '--case[I-filter ang mga case ayon sa name glob]:glob:' \
            '*--tag[I-filter ang mga case ayon sa tag (maaaring ulitin)]:tag:' \
            '--runs[I-override ang bilang ng run bawat case (default: case.runs, kung wala ay 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Magpatakbo ng hanggang n na agent run nang sabay-sabay (1-8; default 1)]:n:' \
            '--model[I-override ang model para sa lahat ng case]:model:_claude_model_names' \
            '--judge-model[I-override ang model ng LLM grader (default: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Mahigpit na limitasyon sa gastos; ihinto at iulat ang mga partial na resulta kapag naabot (exit code 2)]:usd:' \
            '--output-dir[Direktoryo para sa aggregate-result.json]:dir:_directories' \
            '--eval-dir[Pangalan ng direktoryo (sa ilalim ng plugin) na naglalaman ng mga eval case]:dir:' \
            '--json[I-print ang buong resulta ng run bilang JSON sa stdout, o isulat ito sa .json file na ito]::path:_files' \
            '--threshold[Lumabas nang may exit code 1 kung may score ng case na mas mababa sa threshold na ito (default: 1.0)]:threshold:' \
            '*--allow-tools[Operator grant para sa mga gated tool (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '*--disallow-tools[Mga built-in tool na hindi ibibigay kay Claude sa anumang kaso, kahit na pinahintulutan]:tools:' \
            '(--no-scaffold)--scaffold[Patakbuhin ang scaffold_script ng bawat case (nagpapatakbo ng bash na ibinigay ng author sa ilalim ng iyong account; naka-off by default)]' \
            '(--scaffold)--no-scaffold[Tahasang laktawan ang scaffold_script]' \
            '--trust-plugin[Ipahayag na pinagkakatiwalaan mo ang plugin na ito at ang eval suite nito, nilalaktawan ang trust prompt sa unang run (para sa CI)]' \
            '--ablation[Magpatakbo ng baseline arm (paghahambing na grupo) na walang plugin at iulat ang pagkakaiba ng score]:mode:(none with-without)' \
            '--mocks[Mga mock na pamalit sa mga MCP server, mula sa <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Kasama ang --mocks record: simulan din ang mga totoong MCP server process na walang mock]' \
            '--keep-temp[Panatilihin ang mga scaffold dir para sa debugging]' \
            '--verbose[I-log ang mga trace event bawat mensahe sa debug log]' \
            '--report[Isulat ang self-contained na HTML report sa path na ito sa halip na sa results dir]:path:_files' \
            '(--no-publish)--publish-report[Hingin din na i-publish ang report sa claude.ai]' \
            '(--publish-report)--no-publish[Panatilihing lokal lang ang HTML report; laktawan ang pag-publish nito sa claude.ai]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '::target: _alternative "commands\:eval command\:(init)" "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[I-push ang tag sa --remote pagkatapos itong likhain]' \
            '--dry-run[I-print ang ita-tag nang hindi ito nililikha]' \
            '(-f --force)'{-f,--force}'[Laktawan ang mga check para sa dirty working tree at sa tag na umiiral na]' \
            '(-m --message)'{-m,--message}'[Annotation message ng tag (gamitin ang %s para sa bersyon)]:msg:' \
            '--remote[Remote na pagpu-push-an kasama ang --push]:name:' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '::dir:_directories'
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
            '--sparse[Limitahan ang checkout sa mga partikular na direktoryo gamit ang git sparse-checkout (para sa mga monorepo)]:paths:' \
            '--scope[Kung saan idedeklara ang marketplace]:scope:(user project local)' \
            '--json[Mag-print ng isang machine-readable na linya ng resulta bilang huling linya sa stdout]' \
            '--claudeai[Idagdag ang marketplace na may ganitong pangalan na hino-host ng claude.ai para sa iyo]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Ilabas bilang JSON]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Alisin ang deklarasyon ng marketplace mula sa isang partikular na settings scope (huwag tukuyin para alisin ito sa bawat scope)]:scope:(user project local)' \
            '--json[Mag-print ng isang machine-readable na linya ng resulta bilang huling linya sa stdout]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '--json[Kasama ang pangalan ng marketplace: mag-print ng isang machine-readable na linya ng resulta bilang huling linya sa stdout]' \
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
    '--agent[Default na agent para sa mga session na na-dispatch mula sa agent view]:agent:_claude_agent_names' \
    '--all[Kasama ang --json: isama rin ang mga natapos na background session]' \
    '--allow-dangerously-skip-permissions[Gawing available ang bypass-permissions mode sa mga dispatched session]' \
    '--cwd[Ipakita lang ang mga background session na sinimulan sa ilalim ng path]:path:_directories' \
    '--dangerously-skip-permissions[Alyas para sa --permission-mode bypassPermissions]' \
    '--effort[Default na antas ng effort para sa mga dispatched session]:level:(low medium high xhigh max)' \
    '--json[I-print ang mga aktibong session bilang JSON array at lumabas]' \
    '*--mcp-config[MCP server configuration na ilalapat sa mga dispatched session]:config:' \
    '--model[Default na model para sa mga session na na-dispatch mula sa agent view]:model:_claude_model_names' \
    '--permission-mode[Default na permission mode para sa mga dispatched session]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Mag-load ng mga plugin mula sa direktoryo para sa agent view at mga dispatched session]:path:_directories' \
    '--setting-sources[Listahan ng mga setting source na pinaghihiwalay ng kuwit para i-load (user, project, local)]:sources:' \
    '--settings[Settings file o JSON string na ilalapat]:file-or-json:_files' \
    '--strict-mcp-config[Gumamit lang ng mga MCP server mula sa --mcp-config sa mga dispatched session]' \
    '--restricted[Simulan ang mga dispatched session sa restricted mode]' \
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
        login)
          _arguments \
            '--email[Paunang punan ang email address sa login page]:email:' \
            '--sso[Pilitin ang SSO login flow]' \
            '(--claudeai)--console[Gamitin ang Anthropic Console (billing ayon sa paggamit ng API) sa halip na Claude subscription]' \
            '(--console)--claudeai[Gamitin ang Claude subscription (default)]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]'
          ;;
        status)
          _arguments \
            '(--text)--json[Ilabas bilang JSON (default)]' \
            '(--json)--text[Ilabas bilang text na madaling basahin ng tao]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]'
          ;;
        logout)
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
        critique)
          _arguments \
            '--model[I-override kung aling model ang gagamitin]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]'
          ;;
        defaults)
          _arguments \
            '--label[Ipakita lang ang mga rule na ang label ay nagsisimula sa prefix na ito (hindi case-sensitive)]:prefix:' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Laktawan ang confirmation prompt]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]'
          ;;
        config)
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
            '--dry-run[Ilista ang buburahin nang walang binubura]' \
            '(-y --yes)'{-y,--yes}'[Laktawan ang confirmation prompt]' \
            '(-i --interactive)'{-i,--interactive}'[Magtanong para sa bawat item bago burahin]' \
            '(1)--all[Burahin ang state para sa bawat project (hindi maaaring isabay sa isang path)]' \
            '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_purge() {
  _arguments \
    '--dry-run[Ilista ang buburahin nang walang binubura]' \
    '(-y --yes)'{-y,--yes}'[Laktawan ang confirmation prompt]' \
    '(-i --interactive)'{-i,--interactive}'[Magtanong para sa bawat item bago burahin]' \
    '(1)--all[Burahin ang state para sa bawat project (hindi maaaring isabay sa isang path)]' \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]' \
    '(--all)::path:_directories'
}

_claude_ultrareview() {
  _arguments \
    '--json[I-print ang raw bugs.json payload sa halip na mga naka-format na natuklasan]' \
    '--timeout[Pinakamatagal na bilang ng minutong hihintayin para matapos ang review (default: 45)]:minutes:' \
    '(--no-post)--post[I-post ang mga natuklasan ng natapos na review sa PR sa ilalim ng iyong account (mga PR target lang; isang simpleng comment, hindi review)]' \
    '(--post)--no-post[Huwag i-post ang mga natuklasan sa PR (ang default)]' \
    '--trust-workspace[Pagkatiwalaan ang kasalukuyang folder para sa run na ito lang, nang hindi nagtatanong (para sa mga script at CI)]' \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[I-restart ang bawat tumatakbong background session]' \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Itapon din ang mga hindi pa na-push na commit at hindi pa na-commit na pagbabago ng worktree (ipasa ang commit@worktree-id na iniulat ng naunang claude rm)]:commit@worktree-id:' \
    '--force-remove-worktree[Burahin ang worktree directory kahit hindi ito naalis ng WorktreeRemove hook o ng git (ipasa ang worktree-id na iniulat ng naunang claude rm)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]' \
    '1:session:_claude_background_sessions'
}

_claude_self_hosted_runner() {
  _arguments \
    '--api-url[Base URL ng API (default: https://api.anthropic.com)]:url:' \
    '--environment-secret-file[Path papunta sa environment secret file]:path:_files' \
    '--lock-to-account[I-lock ang runner sa iisang account sa pag-register]:id:' \
    '--client-label[Observability label na ipinapadala sa pag-register (default: hostname)]:label:' \
    '(--proxy-authorization-file --agent-proxy-url)--proxy-authorization-command[Command na ang stdout ay ang Proxy-Authorization header para sa mga egress proxy]:shell command:' \
    '(--proxy-authorization-command --agent-proxy-url)--proxy-authorization-file[File na naglalaman ng Proxy-Authorization header para sa mga egress proxy]:path:_files' \
    '(--proxy-authorization-command --proxy-authorization-file)--agent-proxy-url[Iruta ang bawat session sa agent proxy sa URL na ito (https lang)]:url:' \
    '--capacity[Pinakamaraming sabay-sabay na session (default: 1)]:n:' \
    '--base-dir[Base na direktoryo para sa mga repo checkout (default: /workspace)]:path:_directories' \
    '--exec-path[Binary na gagamitin para sa mga child session (default: ang binary na ito)]:path:_files' \
    '--hooks-dir[Direktoryo ng mga lifecycle hook script (checkout, command, post-session)]:path:_directories' \
    '--session-stop-grace-sec[Gaano katagal maghihintay ng malinis na exit pagkatapos matapos ang session (default: 5)]:n:' \
    '--post-session-hook-timeout-sec[Palugit pagkatapos ng SIGTERM para sa post-session hook (default: 60)]:n:' \
    '--checkout-hook-timeout-min[Wall-clock na limitasyon para sa bawat run ng checkout hook (default: 30; 0 para i-disable)]:n:' \
    '--drain-wait-sec[Sa SIGTERM/SIGINT, maghintay nang hanggang N segundo para sa kasalukuyang trabaho (default: 0)]:n:' \
    '--drain-marker-file[Marker file kung saan inaanunsyo ng host ang maayos na drain]:path:_files' \
    '*--git-ssh-rewrite[I-rewrite ang mga source URL na https://<host>/... bilang git@<host>:... (maaaring ulitin)]:host:' \
    '*--git-host-rewrite[I-rewrite ang mga source URL na https://<f>/... bilang https://<t>/... (maaaring ulitin)]:from=to:' \
    '--use-anthropic-git-proxy[Gamitin ang git na pinamamahalaan ng Anthropic. BABALA: binubura at pinapalitan ang HOME-level na git config, gamitin lang sa isang nakalaang account]' \
    '--configure-git[Itakda ang global na git identity at paganahin ang commit signing gamit ang Anthropic signing service. Isinusulat ang ~/.gitconfig]' \
    '--push-outcome-on-release[I-push ang mga sinusubaybayang outcome branch kapag ang runner ang nagtapos sa isang hindi pa kumpletong session]' \
    '--trust-workspace[Maglagay nang maaga ng persistent na trust para sa mga repo path ng bawat session (default: true)]::bool:(true false)' \
    '--remove-session-state[Alisin ang state ng session kapag natapos ang session (default: false)]::bool:(true false)' \
    '--diff-finds-nested-repository[Ipakita ang repository na na-clone sa isang sub-folder sa Changes pane; kailangan ang --capacity 1 (default: false)]::bool:(true false)' \
    '--confine-repo-settings[Guard mode na naglilimita sa mga setting na naka-commit sa repo (default: warn)]:mode:(warn enforce off)' \
    '--server-auto-mode-lists[Aling mga auto mode classifier list mula sa server ang maaaring matanggap ng session (default: no-allow)]:mode:(all no-allow none)' \
    '--host-config-snapshot[Kung saan itinatago ang startup snapshot ng host config (default: disk)]:mode:(disk memory)' \
    '--health-port[Port para sa /healthz HTTP listener (default: 8080; 0 para i-disable)]:port:' \
    '--log-level[Log level (default: info)]:level:(info debug)' \
    '--log-file[Kopyahin din ang mga runner log sa isang file sa append mode]:path:_files' \
    '--exit-if-unused-min[Lumabas sa runner kung walang naitalagang trabaho sa loob ng N minuto]:n:' \
    '--drain-grace-sec[Ilang segundo pang magpo-poll para sa trabaho pagkatapos matapos ang mga aktibong session (default: 0)]:n:' \
    '--retire-at[Iretiro ang runner sa absolute Unix time na ito, sa segundo]:epoch-seconds:' \
    '--defer-shutdown-max-min[Sa unang SIGTERM/SIGINT, huminto sa pagtanggap ng trabaho at tapusin ang pag-shut down pagkalipas ng M minuto (default: 0)]:m:' \
    '--release-idle-session-min[Bitawan ang isang session slot pagkatapos ng N minutong walang input ng user]:n:' \
    '--startup-timeout-min[Bitawan ang isang session slot kung hindi pa tapos mag-start up ang child pagkalipas ng N minuto (default: 15; 0 para i-disable)]:n:' \
    '--kill-session-after-min[Limitahan sa N minuto ang wall-clock na buhay ng isang session child]:n:' \
    '--debug-token-dir[PARA SA DEBUG LANG: isinusulat sa disk ang mga live token. Huwag gamitin sa production]:path:_directories' \
    '(-h --help)'{-h,--help}'[Ipakita ang help message na ito]'
}

_claude_remote_control() {
  _arguments \
    '--name[Pangalan ng session (ipinapakita sa claude.ai/code)]:name:' \
    '--remote-control-session-name-prefix[Prefix para sa mga awtomatikong nabuong pangalan ng session (default: hostname)]:prefix:' \
    '(-c --continue --session-id)'{-c,--continue}'[Muling kumonekta sa session na huling naitala para sa direktoryong ito o sa isa sa mga git worktree nito]' \
    '(-c --continue --session-id)--session-id[Muling kumonekta sa isang partikular na session ayon sa ID]:id:' \
    '--permission-mode[Permission mode para sa mga sinimulang session]:mode:(acceptEdits auto bypassPermissions default dontAsk plan)' \
    '(--no-chrome)--chrome[Paganahin ang Claude in Chrome para sa mga sinimulang session]' \
    '(--chrome)--no-chrome[I-disable ang Claude in Chrome para sa mga sinimulang session]' \
    '(-d --debug)'{-d,--debug}'[Paganahin ang debug mode na may opsyonal na pag-filter ng kategorya]::filter:' \
    '--debug-file[Isulat ang mga debug log sa file]:path:_files' \
    '(-v --verbose)'{-v,--verbose}'[Paganahin ang verbose output]' \
    '--spawn[Mode ng pag-spawn (default: same-dir)]:mode:(same-dir worktree session)' \
    '--capacity[Pinakamaraming sabay-sabay na session sa worktree o same-dir mode (default: 32)]:n:' \
    '(--no-create-session-in-dir)--create-session-in-dir[Gumawa nang maaga ng session sa kasalukuyang direktoryo (default)]' \
    '(--create-session-in-dir)--no-create-session-in-dir[Huwag gumawa nang maaga ng session sa kasalukuyang direktoryo]' \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong na ito]'
}

_claude_daemon() {
  local -a daemon_commands common_options
  daemon_commands=(
    'run:Patakbuhin ang supervisor sa foreground'
    'status:Ipakita ang pid, bersyon, uptime ng daemon'
    'logs:Sundan ang daemon log (Ctrl-C para huminto)'
    'uninstall:Alisin ang background service (launchctl/systemd)'
    'stop:I-shut down ang supervisor at tapusin ang mga background session'
  )
  common_options=(
    '--json-path[File ng config (default: ~/.claude/daemon.json)]:path:_files'
    '--log-file[File ng log (default: ~/.claude/daemon.log)]:path:_files'
    '(-h --help)'{-h,--help}'[Ipakita ang tulong na ito]'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    $common_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'mga daemon command' daemon_commands
      ;;
    args)
      case $words[1] in
        run)
          _arguments \
            $common_options \
            '::json-path:_files'
          ;;
        stop)
          _arguments \
            $common_options \
            '--any[Ihinto rin ang pansamantalang daemon (hindi service)]' \
            '--keep-workers[Hayaang tumatakbo ang mga detached na session]'
          ;;
        status|logs|uninstall)
          _arguments \
            $common_options
          ;;
      esac
      ;;
  esac
}

_claude_import() {
  _arguments \
    '--dry-run[Ipakita ang ii-import nang walang isinusulat]' \
    '--yes[Laktawan ang interactive picker (sa mga headless surface, ipasa ang --yes=<digest> mula sa /import preview)]' \
    '(-h --help)'{-h,--help}'[Ipakita ang tulong para sa command]' \
    '::source:(codex gemini cursor)'
}

# compinit autoloads this file, and that first call only defines the functions
# above: complete right away so the first TAB already works. Sourced directly,
# there is nothing to complete yet, only the registration.
if [[ $funcstack[1] == _claude ]]; then
  _claude "$@"
else
  (( $+_comps[claude] )) || compdef _claude claude
fi
