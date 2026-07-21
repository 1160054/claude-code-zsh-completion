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
    'mcp:Ffurfweddu a rheoli gweinyddion MCP'
    'plugin:Rheoli ategion Claude Code'
    'agents:Rheoli asiantau cefndir'
    'auth:Rheoli dilysu'
    'auto-mode:Archwilio neu ailosod ffurfweddiad dosbarthwr modd awto'
    'gateway:Rhedeg y porth dilysu/telemetreg menter'
    'project:Rheoli cyflwr prosiect Claude Code'
    'ultrareview:Rhedeg adolygiad cod aml-asiant wedi'\''i gynnal ar y cwmwl ac argraffu'\''r canfyddiadau'
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
    '--max-budget-usd[Uchafswm o ddoleri i'\''w wario ar alwadau API (--print yn unig)]:swm:'
    '--replay-user-messages[Ail-anfon negeseuon defnyddiwr o stdin ar stdout ar gyfer cadarnhad]'
    '--allowed-tools[Rhestr wedi'\''i gwahanu â choma neu ofod o enwau offer a ganiateir (e.e., "Bash(git:*) Edit")]:offer:'
    '--allowedTools[Rhestr wedi'\''i gwahanu â choma neu ofod o enwau offer a ganiateir (fformat camelCase)]:offer:'
    '--tools[Pennu rhestr o offer ar gael o'\''r set adeiledig. Modd argraffu yn unig]:offer:'
    '--disallowed-tools[Rhestr wedi'\''i gwahanu â choma neu ofod o enwau offer na chaniateir (e.e., "Bash(git:*) Edit")]:offer:'
    '--disallowedTools[Rhestr wedi'\''i gwahanu â choma neu ofod o enwau offer na chaniateir (fformat camelCase)]:offer:'
    '--mcp-config[Llwytho gweinyddion MCP o ffeil neu linyn JSON (wedi'\''i wahanu ag ofod)]:ffurfweddiadau:'
    '--system-prompt[Anogwr system i'\''w ddefnyddio ar gyfer y sesiwn]:anogwr:'
    '--append-system-prompt[Atodi anogwr system i anogwr system rhagosodedig]:anogwr:'
    '--permission-mode[Modd caniatâd i'\''w ddefnyddio ar gyfer y sesiwn]:modd:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Parhau â'\''r sgwrs fwyaf diweddar]'
    '(-r --resume)'{-r,--resume}'[Ailddechrau sgwrs - pennu ID sesiwn neu ddewis yn rhyngweithiol]:IDsesiwn:_claude_sessions'
    '--fork-session[Creu ID sesiwn newydd yn lle ailddefnyddio ID sesiwn gwreiddiol wrth ailddechrau (gyda --resume neu --continue)]'
    '--no-session-persistence[Analluogi parhad sesiwn - ni chaiff sesiynau eu cadw (--print yn unig)]'
    '--model[Model ar gyfer y sesiwn gyfredol. Pennu alias ar gyfer y model diweddaraf (e.e., '\''sonnet'\'' neu '\''opus'\'')]:model:'
    '--agent[Asiant ar gyfer y sesiwn gyfredol. Mae'\''n gwrthwneud y gosodiad '\''agent'\'']:asiant:'
    '--betas[Penawdau beta i'\''w cynnwys mewn ceisiadau API (defnyddwyr allwedd API yn unig)]:betas:'
    '--fallback-model[Galluogi dirwyneb awtomatig i'\''r model a bennwyd pan fo'\''r model rhagosodedig dan straen (--print yn unig)]:model:'
    '--settings[Llwybr i ffeil JSON gosodiadau neu linyn JSON i lwytho gosodiadau ychwanegol]:ffeil-neu-json:_files'
    '--add-dir[Cyfeiriaduron ychwanegol i ganiatáu mynediad offer]:cyfeiriaduron:_directories'
    '--ide[Cysylltu'\''n awtomatig ag IDE wrth gychwyn os oes union un IDE dilys ar gael]'
    '--strict-mcp-config[Defnyddio gweinyddion MCP o --mcp-config yn unig ac anwybyddu pob gosodiad MCP arall]'
    '--session-id[ID sesiwn penodol i'\''w ddefnyddio ar gyfer y sgwrs (rhaid bod yn UUID dilys)]:uuid:'
    '--agents[Gwrthrych JSON yn diffinio asiantau cyfaddas]:json:'
    '--setting-sources[Rhestr wedi'\''i gwahanu â choma o ffynonellau gosodiadau i'\''w llwytho (user, project, local)]:ffynonellau:'
    '--plugin-dir[Cyfeiriadur i lwytho ategion ohono ar gyfer y sesiwn hon yn unig (ailadroddadwy)]:llwybrau:_directories'
    '--disable-slash-commands[Analluogi pob gorchymyn slaes]'
    '(--bg --background)'{--bg,--background}'[Cychwyn y sesiwn fel asiant cefndir a dychwelyd ar unwaith]'
    '(-w --worktree)'{-w,--worktree}'[Creu coeden waith git newydd ar gyfer y sesiwn hon (pennu enw yn ddewisol)]::enw:'
    '--tmux[Creu sesiwn tmux ar gyfer y goeden waith (angen --worktree)]'
    '(-n --name)'{-n,--name}'[Gosod enw arddangos ar gyfer y sesiwn hon]:enw:'
    '--effort[Lefel ymdrech ar gyfer y sesiwn gyfredol]:lefel:(low medium high xhigh max)'
    '--debug-file[Ysgrifennu cofnodion dadfygio i lwybr ffeil penodol (yn galluogi modd dadfygio yn ymhlyg)]:llwybr:_files'
    '--from-pr[Ailddechrau sesiwn wedi'\''i gysylltu â PR yn ôl rhif/URL, neu agor dewisydd rhyngweithiol]::gwerth:'
    '--remote-control[Cychwyn sesiwn rhyngweithiol gyda Rheolaeth o Bell wedi'\''i galluogi (wedi'\''i enwi'\''n ddewisol)]::enw:'
    '--remote-control-session-name-prefix[Rhagddodiad ar gyfer enwau sesiwn Rheolaeth o Bell a gynhyrchir yn awtomatig]:rhagddodiad:'
    '--chrome[Galluogi integreiddiad Claude yn Chrome]'
    '--no-chrome[Analluogi integreiddiad Claude yn Chrome]'
    '--plugin-url[Nôl .zip ategyn o URL ar gyfer y sesiwn hon yn unig (ailadroddadwy)]:url:'
    '--file[Adnoddau ffeil i'\''w lawrlwytho wrth gychwyn (fformat: file_id:relative_path)]:manylebau:'
    '--prompt-suggestions[Galluogi awgrymiadau anogwr (yn allyrru anogwr nesaf a ragfynegir mewn modd print/SDK)]::gwerth:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Anfon testun is-asiant a blociau meddwl ymlaen fel negeseuon (gyda --print a stream-json)]'
    '--include-hook-events[Cynnwys pob digwyddiad cylchred bywyd bachyn yn y ffrwd allbwn (gyda stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Symud adrannau fesul peiriant i'\''r neges defnyddiwr cyntaf i wella ailddefnydd storfa anogwr]'
    '--brief[Galluogi'\''r offeryn SendUserMessage ar gyfer cyfathrebu asiant-i-ddefnyddiwr]'
    '--safe-mode[Cychwyn gyda phob addasiad wedi'\''i analluogi (defnyddiol ar gyfer datrys problemau ffurfweddiad diffygiol)]'
    '--bare[Modd minimal: hepgor bachau, LSP, cydweddu ategion, priodoli, awto-gof, a darganfod CLAUDE.md yn awtomatig]'
    '--ax-screen-reader[Rendro allbwn cyfeillgar i ddarllenydd sgrin (testun gwastad, dim borderi addurniadol na animeiddiadau)]'
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
    'login:Dilysu gyda gweinydd MCP (HTTP, SSE, neu gysylltydd claude.ai)'
    'logout:Clirio manylion OAuth wedi'\''u storio ar gyfer gweinydd MCP'
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
        login|logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:enw:_claude_mcp_servers'
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
    'list:Rhestru ategion wedi'\''u gosod'
    'details:Dangos rhestr gydrannau a chost tocynnau a ragamcanir ar gyfer ategyn'
    'install:Gosod ategyn o farchnadoedd sydd ar gael'
    'i:Gosod ategyn o farchnadoedd sydd ar gael (byrfodd ar gyfer install)'
    'init:Sgaffaldio ategyn newydd (yn llwytho'\''n awtomatig y sesiwn nesaf)'
    'uninstall:Dadosod ategyn wedi'\''i osod'
    'remove:Dadosod ategyn wedi'\''i osod (alias ar gyfer uninstall)'
    'enable:Galluogi ategyn wedi'\''i analluogi'
    'disable:Analluogi ategyn wedi'\''i alluogi'
    'update:Diweddaru ategyn i'\''r fersiwn ddiweddaraf'
    'eval:Rhedeg achosion eval yn erbyn ategyn ac adrodd canlyniadau wedi'\''u sgorio'
    'prune:Tynnu dibyniaethau a osodwyd yn awtomatig nad oes eu hangen mwyach'
    'tag:Creu tag git {name}--v{version} ar gyfer rhyddhad ategyn'
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
            '(-s --scope)'{-s,--scope}'[Cwmpas gosod]:cwmpas:(user project local)' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:ategyn:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Cwmpas gosod]:cwmpas:(user project local)' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:ategyn:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Cwmpas gosod]:cwmpas:(user project local)' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:ategyn:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Cwmpas gosod]:cwmpas:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:ategyn:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:ategyn:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:enw:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:targed:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:llwybr:_files'
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

_claude_agents() {
  _arguments \
    '*--add-dir[Cyfeiriadur ychwanegol i ganiatáu mynediad offer mewn sesiynau a anfonwyd]:cyfeiriadur:_directories' \
    '--agent[Asiant rhagosodedig ar gyfer sesiynau a anfonwyd o'\''r golwg asiant]:asiant:' \
    '--all[Gyda --json: cynnwys sesiynau cefndir cwblhawyd hefyd]' \
    '--allow-dangerously-skip-permissions[Gwneud modd osgoi-caniatâd ar gael i sesiynau a anfonwyd]' \
    '--cwd[Dangos sesiynau cefndir a gychwynnwyd o dan lwybr yn unig]:llwybr:_directories' \
    '--dangerously-skip-permissions[Alias ar gyfer --permission-mode bypassPermissions]' \
    '--effort[Lefel ymdrech ragosodedig ar gyfer sesiynau a anfonwyd]:lefel:(low medium high xhigh max)' \
    '--json[Argraffu sesiynau gweithredol fel arae JSON a gadael]' \
    '*--mcp-config[Ffurfweddiad gweinydd MCP i'\''w gymhwyso i sesiynau a anfonwyd]:ffurfweddiad:' \
    '--model[Model rhagosodedig ar gyfer sesiynau a anfonwyd o'\''r golwg asiant]:model:' \
    '--permission-mode[Modd caniatâd rhagosodedig ar gyfer sesiynau a anfonwyd]:modd:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Llwytho ategion o gyfeiriadur ar gyfer y golwg asiant a sesiynau a anfonwyd]:llwybr:_directories' \
    '--setting-sources[Rhestr wedi'\''i gwahanu â choma o ffynonellau gosodiadau i'\''w llwytho (user, project, local)]:ffynonellau:' \
    '--settings[Ffeil gosodiadau neu linyn JSON i'\''w gymhwyso]:ffeil-neu-json:_files' \
    '--strict-mcp-config[Defnyddio gweinyddion MCP o --mcp-config yn unig mewn sesiynau a anfonwyd]' \
    '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Mewngofnodi i'\''ch cyfrif Anthropic'
    'logout:Allgofnodi o'\''ch cyfrif Anthropic'
    'status:Dangos statws dilysu'
    'help:Dangos cymorth'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'gorchmynion auth' auth_commands
      ;;
    args)
      case $words[1] in
        login|logout|status)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Argraffu ffurfweddiad modd awto effeithiol fel JSON'
    'critique:Cael adborth AI ar eich rheolau modd awto cyfaddas'
    'defaults:Argraffu rheolau modd awto rhagosodedig fel JSON'
    'reset:Ailosod ffurfweddiad modd awto i'\''r rhagosodiadau a ddanfonwyd'
    'help:Dangos cymorth'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'gorchmynion auto-mode' auto_mode_commands
      ;;
    args)
      case $words[1] in
        config|critique|defaults|reset)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Llwybr i ffurfweddiad YAML porth]:llwybr:_files' \
    '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Dileu holl gyflwr Claude Code ar gyfer prosiect (trawsgrifiadau, tasgau, hanes ffeiliau, cofnod ffurfweddu)'
    'help:Dangos cymorth'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'gorchmynion project' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]' \
            '1:llwybr:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Argraffu'\''r llwyth bugs.json crai yn lle canfyddiadau wedi'\''u fformatio]' \
    '--timeout[Uchafswm munudau i aros i'\''r adolygiad orffen]:munudau:' \
    '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]' \
    '1:targed:'
}

(( $+_comps[claude] )) || compdef _claude claude
