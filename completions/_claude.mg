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
    'mcp:Mametraka sy mitantana ny serveurs MCP'
    'plugin:Mitantana ny plugins Claude Code'
    'agents:Mitantana ny agents miasa ao ambadika'
    'auth:Mitantana ny authentication'
    'auto-mode:Mizaha na mamerina amin ny laoniny ny configuration classifier auto mode'
    'gateway:Mampandeha ny gateway auth/telemetry orinasa'
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
    '--max-budget-usd[Vola dolara ambony indrindra holaniana amin ny antso API (--print ihany)]:amount:'
    '--replay-user-messages[Mandefa indray ny hafatra mpampiasa avy amin ny stdin amin ny stdout ho an ny fanamafisana]'
    '--allowed-tools[Lisitr ireo anaran ny fitaovana avela izay sarahan ny virgule na espace (ohatra: "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Lisitr ireo anaran ny fitaovana avela izay sarahan ny virgule na espace (endrika camelCase)]:tools:'
    '--tools[Mamaritra lisitr ireo fitaovana misy avy amin ny andian-dahatra naorina. Mode print ihany]:tools:'
    '--disallowed-tools[Lisitr ireo anaran ny fitaovana tsy avela izay sarahan ny virgule na espace (ohatra: "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Lisitr ireo anaran ny fitaovana tsy avela izay sarahan ny virgule na espace (endrika camelCase)]:tools:'
    '--mcp-config[Mampiasa serveurs MCP avy amin ny rakitra JSON na tady (sarahan ny espace)]:configs:'
    '--system-prompt[System prompt hampiasaina amin ny session]:prompt:'
    '--append-system-prompt[Manampy system prompt amin ny system prompt default]:prompt:'
    '--permission-mode[Mode alalana hampiasaina amin ny session]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Manohizo ny resaka farany]'
    '(-r --resume)'{-r,--resume}'[Miverina amin ny resaka - manamarihana ID session na mifidy amin ny alalan ny fifandraisana]:sessionId:_claude_sessions'
    '--fork-session[Mamorona ID session vaovao fa tsy mampiasa indray ny ID session tany am-boalohany rehefa miverina (miaraka amin ny --resume na --continue)]'
    '--no-session-persistence[Manakana ny fitehirizana session - tsy hotehirizina ny session (--print ihany)]'
    '--model[Modely ho an ny session ankehitriny. Mamaritra anarana hafa ho an ny modely farany (ohatra: "sonnet" na "opus")]:model:'
    '--agent[Agent ho an ny session ankehitriny. Manova ny setting '\''agent'\'']:agent:'
    '--betas[Headers beta hampidirina amin ny fangatahana API (mpampiasa API key ihany)]:betas:'
    '--fallback-model[Mamela fiovana automatique mankany amin ny modely voamarika rehefa be loatra ny modely default (--print ihany)]:model:'
    '--settings[Lalana mankany amin ny rakitra JSON settings na tady JSON hampidirana settings fanampiny]:file-or-json:_files'
    '--add-dir[Lahatahiry fanampiny hamela fidirana fitaovana]:directories:_directories'
    '--ide[Mampifandray ho azy amin ny IDE rehefa manomboka raha misy IDE manan-kery iray loha]'
    '--strict-mcp-config[Mampiasa serveurs MCP avy amin ny --mcp-config ihany ary tsy manahina ny settings MCP hafa rehetra]'
    '--session-id[ID session manokana hampiasaina amin ny resaka (tsy maintsy UUID manan-kery)]:uuid:'
    '--agents[JSON object mamaritra agents manokana]:json:'
    '--setting-sources[Lisitr ireo loharanom-baovao settings sarahan ny virgule ho ampidirina (user, project, local)]:sources:'
    '--plugin-dir[Lahatahiry hampidirana plugins ho an ny session ity ihany (azo averina)]:paths:_directories'
    '--disable-slash-commands[Manakana ny baiko slash rehetra]'
    '(--bg --background)'{--bg,--background}'[Manomboka ny session ho agent ao ambadika ary miverina avy hatrany]'
    '(-w --worktree)'{-w,--worktree}'[Mamorona git worktree vaovao ho an ity session ity (azo omena anarana safidy)]::name:'
    '--tmux[Mamorona session tmux ho an ny worktree (mitaky --worktree)]'
    '(-n --name)'{-n,--name}'[Mametraka anarana aseho ho an ity session ity]:name:'
    '--effort[Ambaratongan ny ezaka ho an ny session ankehitriny]:level:(low medium high xhigh max)'
    '--debug-file[Manoratra logs debug amin ny lalan-drakitra manokana (mampiasa mode debug ho azy)]:path:_files'
    '--from-pr[Miverina amin ny session mifandray amin ny PR amin ny alalan ny nomerao/URL, na manokatra mpisafidy interactive]::value:'
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
        login|logout)
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
    'install:Mametraka plugin avy amin ny marketplaces misy'
    'i:Mametraka plugin avy amin ny marketplaces misy (fohy ho an ny install)'
    'init:Mamorona rafitra plugin vaovao (mampiditra ho azy amin ny session manaraka)'
    'uninstall:Manala plugin voapetraka'
    'remove:Manala plugin voapetraka (anarana hafa ho an ny uninstall)'
    'enable:Mamela plugin voasimba'
    'disable:Manakana plugin namela'
    'update:Manavao plugin ho amin ny version farany'
    'eval:Mampandeha tranga eval amin ny plugin ary manao tatitra ny valiny voaisa'
    'prune:Manala ny dependencies napetraka ho azy izay tsy ilaina intsony'
    'tag:Mamorona git tag {name}--v{version} ho an ny famoahana plugin'
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
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Faritry ny fametrahana]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Faritry ny fametrahana]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Faritry ny fametrahana]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Faritry ny fametrahana]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:path:_files'
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
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]'
          ;;
        remove|rm)
          _arguments \
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
    '--agent[Agent default ho an ny session nalefa avy amin ny agent view]:agent:' \
    '--all[Miaraka amin ny --json: ampidiro koa ny session ambadika vita]' \
    '--allow-dangerously-skip-permissions[Mamela ny mode bypass-permissions ho an ny session nalefa]' \
    '--cwd[Asehoy ny session ambadika natomboka ao ambanin ny lalana ihany]:path:_directories' \
    '--dangerously-skip-permissions[Anarana hafa ho an ny --permission-mode bypassPermissions]' \
    '--effort[Ambaratongan ny ezaka default ho an ny session nalefa]:level:(low medium high xhigh max)' \
    '--json[Manonta ny session mavitrika ho array JSON ary mivoaka]' \
    '*--mcp-config[Configuration serveur MCP hampiharina amin ny session nalefa]:config:' \
    '--model[Modely default ho an ny session nalefa avy amin ny agent view]:model:' \
    '--permission-mode[Mode alalana default ho an ny session nalefa]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Mampiditra plugins avy amin ny lahatahiry ho an ny agent view sy ny session nalefa]:path:_directories' \
    '--setting-sources[Lisitr ireo loharanom-baovao settings sarahan ny virgule ho ampidirina (user, project, local)]:sources:' \
    '--settings[Rakitra settings na tady JSON hampiharina]:file-or-json:_files' \
    '--strict-mcp-config[Mampiasa serveurs MCP avy amin ny --mcp-config ihany amin ny session nalefa]' \
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
        login|logout|status)
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
        config|critique|defaults|reset)
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
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Manonta ny payload bugs.json manta fa tsy ny zavatra hita voaformat]' \
    '--timeout[Minitra ambony indrindra hiandrasana ny famerenana hifarana]:minutes:' \
    '(-h --help)'{-h,--help}'[Mampiseho fanampiana ho an ny baiko]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
