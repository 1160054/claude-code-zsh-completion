#compdef claude
# Dynamic completion functions
_claude_mcp_servers() {
  local servers config_file
  local -a server_list
  # Read directly from config files instead of running 'claude mcp list'
  for config_file in ~/.claude/mcp.json ~/.claude.json ~/.config/claude/mcp.json; do
    [[ -f "$config_file" ]] || continue
    # Extract server names from JSON (mcpServers section)
    servers=$(grep -oP '(?<="mcpServers":\s*\{)[^}]+' "$config_file" 2>/dev/null | \
              grep -oP '(?<=")[^"]+(?="\s*:)' 2>/dev/null)
    [[ -n "$servers" ]] && server_list+=(${(f)servers})
  done
  # Fallback to claude mcp list if config parsing fails
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
    'mcp:Ffurfweddu a rheoli gweinyddion MCP'
    'plugin:Rheoli ategion Claude Code'
    'setup-token:Gosod tocyn dilysu hirdymor (angen tanysgrifiad Claude)'
    'doctor:Gwiriad iechyd ar gyfer diweddarwr Claude Code'
    'update:Gwirio am a gosod diweddariadau'
    'install:Gosod adeilad brodorol Claude Code'
  )
  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Galluogi modd dadfygio gyda hidlo categori dewisol (e.e., "api,hooks" neu "!statsig,!file")]:hidlydd:'
    '--verbose[Gwrthwneud gosodiad modd manwl o'\''r ffeil ffurfweddu]'
    '(-p --print)'{-p,--print}'[Argraffu ymateb a gadael (ar gyfer defnydd gyda phibellau). Nodyn: defnyddiwch yn unig mewn cyfeiriaduron diogel]'
    '--output-format[Fformat allbwn (gyda --print): "text" (rhagosodiad), "json" (canlyniad sengl), neu "stream-json" (ffrydio amser real)]:fformat:(text json stream-json)'
    '--json-schema[Sgema JSON ar gyfer dilysu allbwn strwythuredig]:sgema:'
    '--include-partial-messages[Cynnwys darnau neges rhannol wrth iddynt gyrraedd (gyda --print a --output-format=stream-json)]'
    '--input-format[Fformat mewnbwn (gyda --print): "text" (rhagosodiad) neu "stream-json" (mewnbwn ffrydio amser real)]:fformat:(text stream-json)'
    '--mcp-debug[\[Anghymell. Defnyddiwch --debug yn lle hynny\] Galluogi modd dadfygio MCP (dangos gwallau gweinydd MCP)]'
    '--dangerously-skip-permissions[Osgoi pob gwiriad caniatâd. Argymhellir ar gyfer blychau tywod yn unig heb fynediad i'\''r rhyngrwyd]'
    '--allow-dangerously-skip-permissions[Galluogi dewis i osgoi gwiriadau caniatâd heb alluogi yn ôl y rhagosodiad]'
    '--replay-user-messages[Ail-anfon negeseuon defnyddiwr o stdin ar stdout ar gyfer cadarnhad]'
    '--allowed-tools[Rhestr wedi'\''i gwahanu â choma neu ofod o enwau offer a ganiateir (e.e., "Bash(git:*) Edit")]:offer:'
    '--allowedTools[Rhestr wedi'\''i gwahanu â choma neu ofod o enwau offer a ganiateir (fformat camelCase)]:offer:'
    '--tools[Pennu rhestr o offer ar gael o'\''r set adeiledig. Modd argraffu yn unig]:offer:'
    '--disallowed-tools[Rhestr wedi'\''i gwahanu â choma neu ofod o enwau offer na chaniateir (e.e., "Bash(git:*) Edit")]:offer:'
    '--disallowedTools[Rhestr wedi'\''i gwahanu â choma neu ofod o enwau offer na chaniateir (fformat camelCase)]:offer:'
    '--mcp-config[Llwytho gweinyddion MCP o ffeil neu linyn JSON (wedi'\''i wahanu ag ofod)]:ffurfweddiadau:'
    '--system-prompt[Anogwr system i'\''w ddefnyddio ar gyfer y sesiwn]:anogwr:'
    '--append-system-prompt[Atodi anogwr system i anogwr system rhagosodedig]:anogwr:'
    '--permission-mode[Modd caniatâd i'\''w ddefnyddio ar gyfer y sesiwn]:modd:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Parhau â'\''r sgwrs fwyaf diweddar]'
    '(-r --resume)'{-r,--resume}'[Ailddechrau sgwrs - pennu ID sesiwn neu ddewis yn rhyngweithiol]:IDsesiwn:_claude_sessions'
    '--fork-session[Creu ID sesiwn newydd yn lle ailddefnyddio ID sesiwn gwreiddiol wrth ailddechrau (gyda --resume neu --continue)]'
    '--model[Model ar gyfer y sesiwn gyfredol. Pennu alias ar gyfer y model diweddaraf (e.e., '\''sonnet'\'' neu '\''opus'\'')]:model:'
    '--fallback-model[Galluogi dirwyneb awtomatig i'\''r model a bennwyd pan fo'\''r model rhagosodedig dan straen (--print yn unig)]:model:'
    '--settings[Llwybr i ffeil JSON gosodiadau neu linyn JSON i lwytho gosodiadau ychwanegol]:ffeil-neu-json:_files'
    '--add-dir[Cyfeiriaduron ychwanegol i ganiatáu mynediad offer]:cyfeiriaduron:_directories'
    '--ide[Cysylltu'\''n awtomatig ag IDE wrth gychwyn os oes union un IDE dilys ar gael]'
    '--strict-mcp-config[Defnyddio gweinyddion MCP o --mcp-config yn unig ac anwybyddu pob gosodiad MCP arall]'
    '--session-id[ID sesiwn penodol i'\''w ddefnyddio ar gyfer y sgwrs (rhaid bod yn UUID dilys)]:uuid:'
    '--agents[Gwrthrych JSON yn diffinio asiantau cyfaddas]:json:'
    '--setting-sources[Rhestr wedi'\''i gwahanu â choma o ffynonellau gosodiadau i'\''w llwytho (user, project, local)]:ffynonellau:'
    '--plugin-dir[Cyfeiriadur i lwytho ategion ohono ar gyfer y sesiwn hon yn unig (ailadroddadwy)]:llwybrau:_directories'
    '(-v --version)'{-v,--version}'[Allbwn rhif fersiwn]'
    '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]'
  )
  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'gorchmynion claude' main_commands
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
          _message "dim dadleuon"
          ;;
      esac
      ;;
  esac
}
_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Cychwyn gweinydd MCP Claude Code'
    'add:Ychwanegu gweinydd MCP i Claude Code'
    'remove:Tynnu gweinydd MCP'
    'list:Rhestru gweinyddion MCP wedi'\''u ffurfweddu'
    'get:Cael manylion gweinydd MCP'
    'add-json:Ychwanegu gweinydd MCP (stdio neu SSE) gyda llinyn JSON'
    'add-from-claude-desktop:Mewnforio gweinyddion MCP o Claude Desktop (Mac a WSL yn unig)'
    'reset-project-choices:Ailosod pob gweinydd (.mcp.json) wedi'\''i gymeradwyo/ei wrthod yn y prosiect hwn'
    'help:Dangos cymorth'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Dangos cymorth]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'gorchmynion mcp' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Galluogi modd dadfygio]' \
            '--verbose[Gwrthwneud gosodiad modd manwl o'\''r ffeil ffurfweddu]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Cwmpas ffurfweddu (local, user, project)]:cwmpas:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Math trafnidiaeth (stdio, sse, http)]:trafnidiaeth:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Gosod newidyn amgylchedd (e.e., -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Gosod pennawd WebSocket]:pennawd:' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:enw:' \
            '2:gorchmynNeuUrl:' \
            '*:dadleuon:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Cwmpas ffurfweddu (local, user, project) - tynnu o gwmpas presennol os na phennir]:cwmpas:(local user project)' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:enw:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:enw:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Cwmpas ffurfweddu (local, user, project)]:cwmpas:(local user project)' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:enw:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Cwmpas ffurfweddu (local, user, project)]:cwmpas:(local user project)' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]'
          ;;
      esac
      ;;
  esac
}
_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Dilysu ategyn neu faniffest marchnad'
    'marketplace:Rheoli marchnadoedd Claude Code'
    'install:Gosod ategyn o farchnadoedd sydd ar gael'
    'i:Gosod ategyn o farchnadoedd sydd ar gael (byrfodd ar gyfer install)'
    'uninstall:Dadosod ategyn wedi'\''i osod'
    'remove:Dadosod ategyn wedi'\''i osod (alias ar gyfer uninstall)'
    'enable:Galluogi ategyn wedi'\''i analluogi'
    'disable:Analluogi ategyn wedi'\''i alluogi'
    'help:Dangos cymorth'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Dangos cymorth]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'gorchmynion plugin' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:llwybr:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:ategyn:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:ategyn:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:ategyn:_claude_installed_plugins'
          ;;
      esac
      ;;
  esac
}
_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Ychwanegu marchnad o URL, llwybr, neu storfa GitHub'
    'list:Rhestru marchnadoedd wedi'\''u ffurfweddu'
    'remove:Tynnu marchnad wedi'\''i ffurfweddu'
    'rm:Tynnu marchnad wedi'\''i ffurfweddu (alias ar gyfer remove)'
    'update:Diweddaru marchnad o'\''r ffynhonnell - diweddaru popeth os na phennir enw'
    'help:Dangos cymorth'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Dangos cymorth]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'gorchmynion marketplace' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:ffynhonnell:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]'
          ;;
        remove|rm)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:enw:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '::enw:'
          ;;
      esac
      ;;
  esac
}
_claude_install() {
  _arguments \
    '--force[Gorfodi gosodiad hyd yn oed os eisoes wedi'\''i osod]' \
    '(-h --help)'{-h,--help}'[Dangos cymorth]' \
    '::targed:(stable latest)'
}
(( $+_comps[claude] )) || compdef _claude claude
