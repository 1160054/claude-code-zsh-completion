#compdef claude

# Fonction de complétion dynamique
_claude_mcp_servers() {
  local servers config_file
  local -a server_list

  # Mamaky mivantana avy amin ny rakitra configuration fa tsy mandefa claude mcp list
  for config_file in ~/.claude/mcp.json ~/.claude.json ~/.config/claude/mcp.json; do
    [[ -f "$config_file" ]] || continue

    # Manala ny anaran ny server avy amin ny JSON (fizarana mcpServers)
    servers=$(grep -oP '(?<="mcpServers":\s*\{)[^}]+' "$config_file" 2>/dev/null | \
              grep -oP '(?<=")[^"]+(?="\s*:)' 2>/dev/null)

    [[ -n "$servers" ]] && server_list+=(${(f)servers})
  done

  # Mampiasa claude mcp list raha tsy mahomby ny famakiana configuration
  if [[ ${#server_list[@]} -eq 0 ]]; then
    server_list=(${(f)"$(claude mcp list 2>/dev/null | sed -n 's/^\([^:]*\):.*/\1/p' | grep -v '^Checking')"})
  fi

  _describe 'serveurs mcp' server_list
}

_claude_installed_plugins() {
  local -a plugins
  local config_file plugin_dir

  # Manamarina ny lahatahiry plugins mivantana
  for plugin_dir in ~/.claude/plugins ~/.config/claude/plugins; do
    [[ -d "$plugin_dir" ]] || continue
    plugins+=(${plugin_dir}/*(N:t))
  done

  # Manala ny mitovy
  plugins=(${(u)plugins})

  _describe 'plugins voapetraka' plugins
}

_claude_sessions() {
  local -a sessions
  local session_dir

  # Manamarina ny lahatahiry session
  for session_dir in ~/.claude/sessions ~/.config/claude/sessions; do
    [[ -d "$session_dir" ]] || continue

    # Manala UUID mivantana avy amin ny anaran ny rakitra
    sessions+=(${session_dir}/*~*.zwc(N:t:r))
  done

  # Sivana ny UUID manan-kery ihany
  sessions=(${(M)sessions:#[0-9a-f](#c8)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c12)})

  _describe 'ID session' sessions
}

_claude() {
  local curcontext="$curcontext" state line
  typeset -A opt_args

  local -a main_commands
  main_commands=(
    'mcp:Mametraka sy mitantana ny serveurs MCP'
    'plugin:Mitantana ny plugins Claude Code'
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
    '--replay-user-messages[Mandefa indray ny hafatra mpampiasa avy amin ny stdin amin ny stdout ho an ny fanamafisana]'
    '--allowed-tools[Lisitr ireo anaran ny fitaovana avela izay sarahan ny virgule na espace (ohatra: "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Lisitr ireo anaran ny fitaovana avela izay sarahan ny virgule na espace (endrika camelCase)]:tools:'
    '--tools[Mamaritra lisitr ireo fitaovana misy avy amin ny andian-dahatra naorina. Mode print ihany]:tools:'
    '--disallowed-tools[Lisitr ireo anaran ny fitaovana tsy avela izay sarahan ny virgule na espace (ohatra: "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Lisitr ireo anaran ny fitaovana tsy avela izay sarahan ny virgule na espace (endrika camelCase)]:tools:'
    '--mcp-config[Mampiasa serveurs MCP avy amin ny rakitra JSON na tady (sarahan ny espace)]:configs:'
    '--system-prompt[System prompt hampiasaina amin ny session]:prompt:'
    '--append-system-prompt[Manampy system prompt amin ny system prompt default]:prompt:'
    '--permission-mode[Mode alalana hampiasaina amin ny session]:mode:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Manohizo ny resaka farany]'
    '(-r --resume)'{-r,--resume}'[Miverina amin ny resaka - manamarihana ID session na mifidy amin ny alalan ny fifandraisana]:sessionId:_claude_sessions'
    '--fork-session[Mamorona ID session vaovao fa tsy mampiasa indray ny ID session tany am-boalohany rehefa miverina (miaraka amin ny --resume na --continue)]'
    '--model[Modely ho an ny session ankehitriny. Mamaritra anarana hafa ho an ny modely farany (ohatra: "sonnet" na "opus")]:model:'
    '--fallback-model[Mamela fiovana automatique mankany amin ny modely voamarika rehefa be loatra ny modely default (--print ihany)]:model:'
    '--settings[Lalana mankany amin ny rakitra JSON settings na tady JSON hampidirana settings fanampiny]:file-or-json:_files'
    '--add-dir[Lahatahiry fanampiny hamela fidirana fitaovana]:directories:_directories'
    '--ide[Mampifandray ho azy amin ny IDE rehefa manomboka raha misy IDE manan-kery iray loha]'
    '--strict-mcp-config[Mampiasa serveurs MCP avy amin ny --mcp-config ihany ary tsy manahina ny settings MCP hafa rehetra]'
    '--session-id[ID session manokana hampiasaina amin ny resaka (tsy maintsy UUID manan-kery)]:uuid:'
    '--agents[JSON object mamaritra agents manokana]:json:'
    '--setting-sources[Lisitr ireo loharanom-baovao settings sarahan ny virgule ho ampidirina (user, project, local)]:sources:'
    '--plugin-dir[Lahatahiry hampidirana plugins ho an ny session ity ihany (azo averina)]:paths:_directories'
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
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Manamarina plugin na manifest marketplace'
    'marketplace:Mitantana ny marketplaces Claude Code'
    'install:Mametraka plugin avy amin ny marketplaces misy'
    'i:Mametraka plugin avy amin ny marketplaces misy (fohy ho an ny install)'
    'uninstall:Manala plugin voapetraka'
    'remove:Manala plugin voapetraka (anarana hafa ho an ny uninstall)'
    'enable:Mamela plugin voasimba'
    'disable:Manakana plugin namela'
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
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Mampiseho fanampiana]' \
            '1:plugin:_claude_installed_plugins'
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

(( $+_comps[claude] )) || compdef _claude claude
