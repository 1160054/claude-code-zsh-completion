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
    'mcp:Mametraka sy mitantana ny serveurs MCP'
    'plugin:Mitantana ny plugins Claude Code'
    'agents:Mitantana ny agents miasa ao ambadika'
    'attach:Manokatra session ambadika ao amin ity terminal ity'
    'logs:Manonta ny output terminal farany an ny session ambadika'
    'stop:Manajanona session ambadika (voatahiry ny resaka)'
    'respawn:Mamerina manomboka session ambadika mba hampandeha ny version Claude Code ankehitriny'
    'rm:Mamafa session ambadika, sy ny worktree-ny rehefa azo antoka izany'
    'auth:Mitantana ny authentication'
    'auto-mode:Mizaha na mamerina amin ny laoniny ny configuration classifier auto mode'
    'gateway:Mampandeha ny gateway auth/telemetry orinasa'
    'import:Mampiditra config avy amin ny agent AI fanoratana kaody hafa ho ao amin ny Claude Code'
    'project:Mitantana ny toetry ny tetikasa Claude Code'
    'ultrareview:Mampandeha famerenana kaody multi-agent an-drahona ary manonta ny zavatra hita'
    'setup-token:Mametraka token authentication maharitra (mitaky famandrihana Claude)'
    'doctor:Fizahana fahasalamana ho an ny auto-updater Claude Code'
    'update:Manamarina sy mametraka fanavaozana'
    'install:Mametraka ny Claude Code native build'
  )

  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Mampiasa mode debug miaraka amin ny sivana kategoria safidy (ohatra: "api,hooks" na "!statsig,!file")]:filter:'
    '--verbose[Manova ny toerana mode verbose avy amin ny rakitra configuration]'
    '(-p --print)'{-p,--print}'[Manonta valiny ary mivoaka (ampiasaina amin ny fantsona). Mariho: ampiasao ao amin ny lahatahiry azo itokiana ihany]'
    '--output-format[Format output (miaraka amin ny --print): "text" (default), "json" (vokatra tokana), na "stream-json" (streaming amin ny fotoana tena izy)]:format:(text json stream-json)'
    '--json-schema[Schema JSON ho an ny fanamarinana output voarafitra]:schema:'
    '--include-partial-messages[Ampidiro ny ampahan ny hafatra ampahan-kevitra rehefa tonga (miaraka amin ny --print sy --output-format=stream-json)]'
    '--input-format[Format input (miaraka amin ny --print): "text" (default) na "stream-json" (streaming input amin ny fotoana tena izy)]:format:(text stream-json)'
    '--mcp-debug[\[Efa lany andro. Ampiasao --debug raha tokony ho izy\] Mampiasa mode debug MCP (mampiseho lesoka serveurs MCP)]'
    '--dangerously-skip-permissions[Mandingana ny fanamarinana alalana rehetra. Soso-kevitra ho an ny sandbox tsy misy fidirana internet ihany]'
    '--allow-dangerously-skip-permissions[Mamela safidy handingana fanamarinana alalana nefa tsy mamela izany amin ny alalan ny default]'
    '--restricted[Mode voafetra: manala ny fitaovana mampandeha baiko na kaody sy WebFetch, tsy manahina ny settings user/project/local, ary mametra ny fitaovana rakitra ao amin ny lahatahiry iasana]'
    '--max-budget-usd[Vola dolara ambony indrindra holaniana amin ny antso API (--print ihany)]:amount:'
    '--replay-user-messages[Mandefa indray ny hafatra mpampiasa avy amin ny stdin amin ny stdout ho an ny fanamafisana]'
    '--allowed-tools[Lisitr ireo anaran ny fitaovana avela izay sarahan ny virgule na espace (ohatra: "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Lisitr ireo anaran ny fitaovana avela izay sarahan ny virgule na espace (endrika camelCase)]:tools:'
    '--tools[Mamaritra lisitr ireo fitaovana misy avy amin ny andian-dahatra naorina. Mode print ihany]:tools:'
    '--disallowed-tools[Lisitr ireo anaran ny fitaovana tsy avela izay sarahan ny virgule na espace (ohatra: "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Lisitr ireo anaran ny fitaovana tsy avela izay sarahan ny virgule na espace (endrika camelCase)]:tools:'
    '--mcp-config[Mampiasa serveurs MCP avy amin ny rakitra JSON na tady (sarahan ny espace)]:configs:'
    '--system-prompt[System prompt hampiasaina amin ny session]:prompt:'
    '--system-prompt-file[Mamaky system prompt avy amin ny rakitra]:file:_files'
    '--append-system-prompt[Manampy system prompt amin ny system prompt default]:prompt:'
    '--append-system-prompt-file[Mamaky system prompt avy amin ny rakitra ary manampy azy amin ny system prompt default]:file:_files'
    '--system-prompt-snapshot[Mandrakitra ny system prompt indray mandeha isaky ny resaka ary mampiasa azy indray tsy miova amin ny fangatahana sy fiverenana rehetra (on, ny default) na mamorona azy vaovao isaky ny fangatahana (off)]:mode:(on off)'
    '--permission-mode[Mode alalana hampiasaina amin ny session]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Iza no mamaly ny fangatahana alalana miaraka amin ny --print: "host" (ny host SDK na --permission-prompt-tool) na "none" (lavina izay rehetra mety hangataka alalana)]:target:(host none)'
    '--permission-prompt-tool[Fitaovana MCP hampiasaina amin ny fangatahana alalana (--print ihany)]:tool:'
    '(-c --continue)'{-c,--continue}'[Manohizo ny resaka farany]'
    '(-r --resume)'{-r,--resume}'[Miverina amin ny resaka - manamarihana ID session na mifidy amin ny alalan ny fifandraisana]:sessionId:_claude_sessions'
    '--fork-session[Mamorona ID session vaovao fa tsy mampiasa indray ny ID session tany am-boalohany rehefa miverina (miaraka amin ny --resume na --continue)]'
    '--no-session-persistence[Manakana ny fitehirizana session - tsy hotehirizina ny session (--print ihany)]'
    '--model[Modely ho an ny session ankehitriny. Mamaritra anarana hafa ho an ny modely farany (ohatra: "sonnet" na "opus")]:model:_claude_model_names'
    '--agent[Agent ho an ny session ankehitriny. Manova ny setting '\''agent'\'']:agent:_claude_agent_names'
    '--betas[Headers beta hampidirina amin ny fangatahana API (mpampiasa API key ihany)]:betas:'
    '--fallback-model[Mamela fiovana automatique mankany amin ny modely voamarika rehefa be loatra ny modely default (--print ihany)]:model:_claude_model_names'
    '--settings[Lalana mankany amin ny rakitra JSON settings na tady JSON hampidirana settings fanampiny]:file-or-json:_files'
    '--add-dir[Lahatahiry fanampiny hamela fidirana fitaovana]:directories:_directories'
    '--ide[Mampifandray ho azy amin ny IDE rehefa manomboka raha misy IDE manan-kery iray loha]'
    '--desktop[Manokatra ao amin ny app Claude Desktop fa tsy ao amin ny terminal (miaraka amin ny --continue na --resume <id> hifidianana ny session)]'
    '--strict-mcp-config[Mampiasa serveurs MCP avy amin ny --mcp-config ihany ary tsy manahina ny settings MCP hafa rehetra]'
    '--session-id[ID session manokana hampiasaina amin ny resaka (tsy maintsy UUID manan-kery)]:uuid:'
    '--agents[JSON object mamaritra agents manokana]:json:'
    '--setting-sources[Lisitr ireo loharanom-baovao settings sarahan ny virgule ho ampidirina (user, project, local)]:sources:'
    '--plugin-dir[Lahatahiry hampidirana plugins ho an ny session ity ihany (azo averina)]:paths:_directories'
    '--disable-slash-commands[Manakana ny baiko slash rehetra]'
    '(--bg --background)'{--bg,--background}'[Manomboka ny session ho agent ao ambadika ary miverina avy hatrany]'
    '(-w --worktree)'{-w,--worktree}'[Mamorona git worktree vaovao ho an ity session ity (azo omena anarana safidy)]::name:'
    '--tmux=-[Mamorona session tmux ho an ny worktree (mitaky --worktree). Mampiasa panes native iTerm2 raha misy; --tmux=classic ho an ny tmux mahazatra]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Mametraka anarana aseho ho an ity session ity]:name:'
    '--effort[Ambaratongan ny ezaka ho an ny session ankehitriny]:level:(low medium high xhigh max)'
    '--autocompact[Haben ny context window auto-compact (auto, na tokens 100k-1M)]:size:(auto)'
    '--debug-file[Manoratra logs debug amin ny lalan-drakitra manokana (mampiasa mode debug ho azy)]:path:_files'
    '--from-pr[Miverina amin ny session mifandray amin ny PR amin ny alalan ny nomerao/URL, na manokatra mpisafidy interactive]::value:'
    '--teleport[Miverina amin ny session teleport, azo omena ID session raha tiana]::session:'
    '--cloud[Mamorona session cloud miaraka amin ny famaritana nomena, na mifandray amin ny session efa misy amin ny alalan ny ID session na URL claude.ai/code]::description-or-session:'
    '--environment[Mamorona session cloud vaovao mandeha amin ny environment self-hosted nomena (ccpool_...)]:environment_id:'
    '--remote-control[Manomboka session interactive miaraka amin ny Remote Control voaomana (azo omena anarana safidy)]::name:'
    '--remote-control-session-name-prefix[Prefix ho an ny anaran ny session Remote Control noforonina ho azy]:prefix:'
    '--chrome[Mampiasa ny fampidirana Claude ao Chrome]'
    '--no-chrome[Manakana ny fampidirana Claude ao Chrome]'
    '--plugin-url[Maka plugin .zip avy amin ny URL ho an ity session ity ihany (azo averina)]:url:'
    '--file[Loharanon-drakitra hampidinina rehefa manomboka (format: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Mampiasa soso-kevitra prompt (mamoaka prompt manaraka vinavina amin ny mode print/SDK)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Mandefa ny lahatsoratra sy ny bloc fisainana subagent ho hafatra (miaraka amin ny --print sy stream-json)]'
    '--include-hook-events[Ampidiro ny hetsika lifecycle hook rehetra amin ny stream output (miaraka amin ny stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Mamindra ny fizarana isaky ny milina mankany amin ny hafatra mpampiasa voalohany mba hanatsara ny fampiasana indray ny prompt-cache]'
    '--brief[Mampiasa ny fitaovana SendUserMessage ho an ny fifandraisana agent-amin-mpampiasa]'
    '--safe-mode[Manomboka amin ny fanovana rehetra voasakana (mahasoa amin ny famahana configuration simba)]'
    '--bare[Mode kely indrindra: dingana hooks, LSP, plugin sync, attribution, auto-memory, sy ny fitadiavana CLAUDE.md ho azy]'
    '--ax-screen-reader[Mamoaka output mora ho an ny screen-reader (lahatsoratra fisaka, tsy misy sisiny na animation haingo)]'
    '(-v --version)'{-v,--version}'[Mamoaka ny nomerao version]'
    '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]'
  )

  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'baikon ny claude' main_commands
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
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]' \
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
          _message "tsy misy argument"
          ;;
      esac
      ;;
  esac
}

_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Manomboka serveur MCP Claude Code'
    'add:Manampy serveur MCP amin ny Claude Code'
    'remove:Manala serveur MCP'
    'list:Milista ny serveurs MCP voarafitra'
    'get:Maka antsipirian ny serveur MCP'
    'add-json:Manampy serveur MCP (stdio na SSE) miaraka amin ny tady JSON'
    'add-from-claude-desktop:Mampiditra serveurs MCP avy amin ny Claude Desktop (Mac sy WSL ihany)'
    'reset-project-choices:Mamerina amin ny laoniny ny serveurs project-scoped (.mcp.json) rehetra nankatoavina/nolavina amin ity tetikasa ity'
    'login:Manamarina amin ny serveur MCP (HTTP, SSE, na connector claude.ai)'
    'logout:Mamafa ny credentials OAuth voatahiry ho an ny serveur MCP'
    'help:Mampiseho fanampiana'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'baikon ny mcp' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Mampiasa mode debug]' \
            '--verbose[Manova ny toerana mode verbose avy amin ny rakitra configuration]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Faritra configuration (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Karazana fitaterana (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Mametraka variable environment (ohatra: -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Mametraka header WebSocket]:header:' \
            '--client-id[ID client OAuth ho an ny serveurs HTTP/SSE]:clientId:' \
            '--client-secret[Mangataka ny client secret OAuth (na mametraka ny variable environment MCP_CLIENT_SECRET)]' \
            '--callback-port[Port raikitra ho an ny callback OAuth (ho an ny serveurs mitaky redirect URIs voasoratra mialoha)]:port:' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Faritra configuration (local, user, project) - esory avy amin ny faritra misy raha tsy voamarika]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Faritra configuration (local, user, project)]:scope:(local user project)' \
            '--client-secret[Mangataka ny client secret OAuth (na mametraka ny variable environment MCP_CLIENT_SECRET)]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Faritra configuration (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]'
          ;;
        login)
          _arguments \
            '--no-browser[Manonta ny URL fanomezan-dalana fa tsy manokatra navigateur (ho an ny session SSH/headless)]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:name:_claude_mcp_servers'
          ;;
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Manamarina plugin na manifest marketplace'
    'marketplace:Mitantana ny marketplaces Claude Code'
    'list:Milista ny plugins voapetraka'
    'details:Mampiseho ny lisitry ny component sy ny vidin ny token vinavina ho an ny plugin'
    'configure:Mampiseho ny safidin ny plugin sy izay tsy voapetraka, na mitahiry sanda avy amin ny stdin'
    'install:Mametraka plugin avy amin ny marketplaces misy'
    'i:Mametraka plugin avy amin ny marketplaces misy (fohy ho an ny install)'
    'init:Mamorona rafitra plugin vaovao (mampiditra ho azy amin ny session manaraka)'
    'new:Mamorona rafitra plugin vaovao (anarana hafa ho an ny init)'
    'uninstall:Manala plugin voapetraka'
    'remove:Manala plugin voapetraka (anarana hafa ho an ny uninstall)'
    'enable:Mamela plugin voasimba'
    'disable:Manakana plugin namela'
    'update:Manavao plugin ho amin ny version farany'
    'eval:Mampandeha tranga eval amin ny plugin ary manao tatitra ny valiny voaisa'
    'prune:Manala ny dependencies napetraka ho azy izay tsy ilaina intsony'
    'autoremove:Manala ny dependencies napetraka ho azy izay tsy ilaina intsony (anarana hafa ho an ny prune)'
    'tag:Mamorona git tag {name}--v{version} ho an ny famoahana plugin'
    'test:Mampandeha ny fitsapana an ny mod'
    'help:Mampiseho fanampiana'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'baikon ny plugin' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '--strict[Mihevitra ny fampitandremana ho lesoka (exit code 1)]' \
            '--json[Mamoaka ny tatitra fanamarinana ho JSON (exit codes mitovy)]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Faritry ny fametrahana]:scope:(user project local)' \
            '*--config[Mametraka safidy userConfig voalaza ao amin ny manifest plugin (azo averina)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[Manaiky ny baiko aseho izay nambaran ny marketplace tsy misy fangatahana fanamafisana]' \
            '--json[Manonta andalana valiny tokana azon ny milina vakiana fa tsy ny hafatra ho an olona]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Faritry ny fametrahana]:scope:(user project local)' \
            '--keep-data[Mitahiry ny lahatahiry data maharitra an ny plugin]' \
            '--prune[Manala koa ny dependencies napetraka ho azy izay tsy ilaina intsony]' \
            '(-y --yes)'{-y,--yes}'[Mandingana ny fangatahana fanamafisana --prune]' \
            '--json[Manonta andalana valiny tokana azon ny milina vakiana fa tsy ny hafatra ho an olona (tsy miaraka amin ny --prune)]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Faritry ny fametrahana]:scope:(user project local)' \
            '--json[Manonta andalana valiny tokana azon ny milina vakiana fa tsy ny hafatra ho an olona]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Manakana ny plugins navela rehetra]' \
            '(-s --scope)'{-s,--scope}'[Faritry ny fametrahana]:scope:(user project local)' \
            '--json[Manonta andalana valiny tokana azon ny milina vakiana fa tsy ny hafatra ho an olona]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Faritry ny fametrahana]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Manaiky ny baiko aseho izay nambaran ny marketplace tsy misy fangatahana fanamafisana]' \
            '--json[Manonta andalana valiny tokana azon ny milina vakiana fa tsy ny hafatra ho an olona]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Mamoaka ho JSON]' \
            '--available[Ampidiro ny plugins misy avy amin ny marketplaces (mitaky --json)]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Manadio amin ny faritra]:scope:(user project local)' \
            '--dry-run[Milista izay hesorina nefa tsy manala]' \
            '(-y --yes)'{-y,--yes}'[Mandingana ny fangatahana fanamafisana]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]'
          ;;
        configure)
          _arguments \
            '--json[Mamoaka ho JSON]' \
            '--values-stdin[Mamaky ny sandan ny safidy avy amin ny stdin ho JSON object misy tady andalana tokana; mitazona ny sandany ny safidy tsy voalaza]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Famaritana ao amin ny manifest]:text:' \
            '--author[Anaran ny mpanoratra (default: git config user.name)]:name:' \
            '--author-email[Mailaky ny mpanoratra (default: git config user.email)]:email:' \
            '--with[Components hamboarina rafitra koa]:components:' \
            '(-f --force)'{-f,--force}'[Manoratra ambonin ny .claude-plugin/ efa misy ao amin ny tanjona]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Manivana ny tranga amin ny glob anarana]:glob:' \
            '*--tag[Manivana ny tranga amin ny tag (azo averina)]:tag:' \
            '--runs[Manova ny isan ny fandehanana isaky ny tranga (default: case.runs, raha tsy izany 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Mampandeha fandehanana agent hatramin ny n miaraka (1-8; default 1)]:n:' \
            '--model[Manova ny modely ho an ny tranga rehetra]:model:_claude_model_names' \
            '--judge-model[Manova ny modely LLM-grader (default: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Fetra ambony indrindra hentitra ho an ny vidiny; manajanona ary manao tatitra ny valiny ampahany raha tratra (exit code 2)]:usd:' \
            '--output-dir[Lahatahiry ho an ny aggregate-result.json]:dir:_directories' \
            '--eval-dir[Anaran ny lahatahiry (ao ambanin ny plugin) misy ny tranga eval]:dir:' \
            '--json[Manonta ny valin ny fandehanana feno ho JSON amin ny stdout, na manoratra azy amin ity rakitra .json ity]::path:_files' \
            '--threshold[Mivoaka miaraka amin ny exit code 1 raha misy tranga manana isa ambanin ity fetra ity (default: 1.0)]:threshold:' \
            '*--allow-tools[Alalana omen ny operator ho an ny fitaovana voafehy (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Mampandeha ny scaffold_script an ny tranga tsirairay (mampandeha bash nomen ny mpanoratra amin ny anaranao; off amin ny default)]' \
            '(--scaffold)--no-scaffold[Mandingana mazava ny scaffold_script]' \
            '--trust-plugin[Manamafy fa matoky ity plugin ity sy ny eval suite-ny ianao, ka mandingana ny fangatahana fahatokisana amin ny fandehanana voalohany (ho an ny CI)]' \
            '--ablation[Mampandeha vondrona fampitahana baseline tsy misy plugin ary manao tatitra ny fahasamihafan ny isa]:mode:(none with-without)' \
            '--mocks[Mpisolo mock ho an ny serveurs MCP, avy amin ny <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Miaraka amin ny --mocks record: manomboka koa ny process serveur MCP tena izy tsy manana mock]' \
            '--keep-temp[Mitahiry ny lahatahiry scaffold ho an ny debug]' \
            '--verbose[Manoratra ny hetsika trace isaky ny hafatra ao amin ny log debug]' \
            '--report[Manoratra ny tatitra HTML mahaleo tena amin ity lalana ity fa tsy amin ny lahatahiry valiny]:path:_files' \
            '(--no-publish)--publish-report[Mitaky koa ny famoahana ny tatitra amin ny claude.ai]' \
            '(--publish-report)--no-publish[Mitazona ny tatitra HTML eo an-toerana ihany; mandingana ny famoahana azy amin ny claude.ai]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Mandefa ny tag mankany amin ny --remote rehefa avy namorona azy]' \
            '--dry-run[Manonta izay hasiana tag nefa tsy mamorona azy]' \
            '(-f --force)'{-f,--force}'[Mandingana ny fanamarinana dirty-working-tree sy tag-already-exists]' \
            '(-m --message)'{-m,--message}'[Hafatra annotation ny tag (ampiasao %s ho an ny version)]:msg:' \
            '--remote[Remote handefasana miaraka amin ny --push]:name:' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '::dir:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Manampy marketplace avy amin ny URL, lalana, na repository GitHub'
    'list:Milista ny marketplaces voarafitra'
    'remove:Manala marketplace voarafitra'
    'rm:Manala marketplace voarafitra (anarana hafa ho an ny remove)'
    'update:Manavao marketplace avy amin ny loharano - manavao ny rehetra raha tsy misy anarana voamarika'
    'help:Mampiseho fanampiana'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'baikon ny marketplace' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '--sparse[Mametra ny checkout amin ny lahatahiry manokana amin ny alalan ny git sparse-checkout (ho an ny monorepos)]:paths:' \
            '--scope[Toerana hanambarana ny marketplace]:scope:(user project local)' \
            '--claudeai[Manampy ny marketplace amin ity anarana ity izay ampiantranoin ny claude.ai ho anao]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Mamoaka ho JSON]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Manala ny fanambarana marketplace avy amin ny faritra settings manokana (aza asiana raha hesorina amin ny faritra rehetra)]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}

_claude_install() {
  _arguments \
    '--force[Manery ny fametrahana na dia voapetraka sahady aza]' \
    '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
    '::target:(stable latest)'
}

_claude_agents() {
  _arguments \
    '*--add-dir[Lahatahiry fanampiny hamela fidirana fitaovana amin ny session nalefa]:directory:_directories' \
    '--agent[Agent default ho an ny session nalefa avy amin ny agent view]:agent:_claude_agent_names' \
    '--all[Miaraka amin ny --json: ampidiro koa ny session ambadika vita]' \
    '--allow-dangerously-skip-permissions[Mamela ny mode bypass-permissions ho an ny session nalefa]' \
    '--cwd[Asehoy ny session ambadika natomboka ao ambanin ny lalana ihany]:path:_directories' \
    '--dangerously-skip-permissions[Anarana hafa ho an ny --permission-mode bypassPermissions]' \
    '--effort[Ambaratongan ny ezaka default ho an ny session nalefa]:level:(low medium high xhigh max)' \
    '--json[Manonta ny session mavitrika ho array JSON ary mivoaka]' \
    '*--mcp-config[Configuration serveur MCP hampiharina amin ny session nalefa]:config:' \
    '--model[Modely default ho an ny session nalefa avy amin ny agent view]:model:_claude_model_names' \
    '--permission-mode[Mode alalana default ho an ny session nalefa]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Mampiditra plugins avy amin ny lahatahiry ho an ny agent view sy ny session nalefa]:path:_directories' \
    '--setting-sources[Lisitr ireo loharanom-baovao settings sarahan ny virgule ho ampidirina (user, project, local)]:sources:' \
    '--settings[Rakitra settings na tady JSON hampiharina]:file-or-json:_files' \
    '--strict-mcp-config[Mampiasa serveurs MCP avy amin ny --mcp-config ihany amin ny session nalefa]' \
    '--restricted[Manomboka ny session nalefa amin ny mode voafetra]' \
    '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Miditra amin ny kaontinao Anthropic'
    'logout:Mivoaka amin ny kaontinao Anthropic'
    'status:Mampiseho ny toetry ny authentication'
    'help:Mampiseho fanampiana'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'baikon ny auth' auth_commands
      ;;
    args)
      case $words[1] in
        login)
          _arguments \
            '--email[Mameno mialoha ny adiresy mailaka eo amin ny pejy fidirana]:email:' \
            '--sso[Manery ny dingana fidirana SSO]' \
            '(--claudeai)--console[Mampiasa Anthropic Console (faktiora araka ny fampiasana API) fa tsy famandrihana Claude]' \
            '(--console)--claudeai[Mampiasa famandrihana Claude (default)]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]'
          ;;
        status)
          _arguments \
            '(--text)--json[Mamoaka ho JSON (default)]' \
            '(--json)--text[Mamoaka ho lahatsoratra azon olona vakiana]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Manonta ny config auto mode mihatra ho JSON'
    'critique:Maka valin-teny AI momba ny fitsipika auto mode manokana'
    'defaults:Manonta ny fitsipika auto mode default ho JSON'
    'reset:Mamerina ny configuration auto mode amin ny default nalefa'
    'help:Mampiseho fanampiana'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'baikon ny auto-mode' auto_mode_commands
      ;;
    args)
      case $words[1] in
        critique)
          _arguments \
            '--model[Manova ny modely ampiasaina]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]'
          ;;
        defaults)
          _arguments \
            '--label[Mampiseho ny fitsipika izay manomboka amin ity prefix ity ny label-ny ihany (tsy miraharaha soratra lehibe na kely)]:prefix:' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Mandingana ny fangatahana fanamafisana]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]'
          ;;
        config)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Lalana mankany amin ny config YAML gateway]:path:_files' \
    '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Mamafa ny toetra Claude Code rehetra ho an ny tetikasa (transcripts, asa, tantaran-drakitra, config entry)'
    'help:Mampiseho fanampiana'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'baikon ny project' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '--dry-run[Milista izay hofafana nefa tsy mamafa na inona na inona]' \
            '(-y --yes)'{-y,--yes}'[Mandingana ny fangatahana fanamafisana]' \
            '(-i --interactive)'{-i,--interactive}'[Manontany isaky ny singa alohan ny hamafana]' \
            '(1)--all[Mamafa ny toetra ho an ny tetikasa rehetra (tsy azo ampiarahina amin ny lalana)]' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Manonta ny payload bugs.json manta fa tsy ny zavatra hita voaformat]' \
    '--timeout[Minitra ambony indrindra hiandrasana ny famerenana hifarana (default: 45)]:minutes:' \
    '(--no-post)--post[Mamoaka ny zavatra hita tamin ny famerenana vita ao amin ny PR amin ny anaranao (tanjona PR ihany; fanehoan-kevitra tsotra iray, fa tsy review)]' \
    '(--post)--no-post[Tsy mamoaka ny zavatra hita ao amin ny PR (ny default)]' \
    '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Mamerina manomboka ny session ambadika mandeha rehetra]' \
    '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Manary koa ny commits tsy voalefa sy ny fanovana tsy voacommit an ny worktree (omeo ny commit@worktree-id nolazain ny claude rm teo aloha)]:commit@worktree-id:' \
    '--force-remove-worktree[Mamafa ny lahatahiry worktree na dia tsy nahavita nanala azy aza ny hook WorktreeRemove na git (omeo ny worktree-id nolazain ny claude rm teo aloha)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Mampiseho izay hampidirina nefa tsy manoratra na inona na inona]' \
    '--yes[Mandingana ny mpisafidy interactive (amin ny surfaces headless, omeo ny --yes=<digest> avy amin ny topi-maso /import)]' \
    '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
