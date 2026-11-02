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
    'mcp:Ffurfweddu a rheoli gweinyddion MCP'
    'plugin:Rheoli ategion Claude Code'
    'agents:Rheoli asiantau cefndir'
    'attach:Agor sesiwn cefndir yn y derfynell hon'
    'logs:Argraffu allbwn diweddar y derfynell ar gyfer sesiwn cefndir'
    'stop:Atal sesiwn cefndir (cedwir ei sgwrs)'
    'respawn:Ailgychwyn sesiwn cefndir fel ei fod yn rhedeg y fersiwn gyfredol o Claude Code'
    'rm:Dileu sesiwn cefndir, a'\''i goeden waith pan fo hynny'\''n ddiogel'
    'remote-control:Rheoli sesiynau lleol o claude.ai/code neu ap symudol Claude'
    'daemon:Rheoli goruchwyliwr y sesiynau cefndir'
    'auth:Rheoli dilysu'
    'auto-mode:Archwilio neu ailosod ffurfweddiad dosbarthwr modd awto'
    'gateway:Rhedeg y porth dilysu/telemetreg menter'
    'self-hosted-runner:Lletya sesiynau cwmwl Claude Code ar y peiriant neu’r cynhwysydd hwn'
    'import:Mewnforio ffurfweddiad o asiant codio AI arall i Claude Code'
    'project:Rheoli cyflwr prosiect Claude Code'
    'purge:Dileu holl gyflwr Claude Code ar gyfer prosiect (trawsgrifiadau, tasgau, hanes ffeiliau, cofnod ffurfweddu)'
    'ultrareview:Rhedeg adolygiad cod aml-asiant wedi'\''i gynnal ar y cwmwl ac argraffu'\''r canfyddiadau'
    'setup-token:Gosod tocyn dilysu hirdymor (angen tanysgrifiad Claude)'
    'doctor:Gwiriad iechyd ar gyfer diweddarwr Claude Code'
    'update:Gwirio am a gosod diweddariadau'
    'install:Gosod adeilad brodorol Claude Code'
  )

  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Galluogi modd dadfygio gyda hidlo categori dewisol (e.e., "api,hooks" neu "!statsig,!file")]:filter:'
    '--verbose[Gwrthwneud gosodiad modd manwl o'\''r ffeil ffurfweddu]'
    '(-p --print)'{-p,--print}'[Argraffu ymateb a gadael (ar gyfer defnydd gyda phibellau). Nodyn: defnyddiwch yn unig mewn cyfeiriaduron diogel]'
    '--output-format[Fformat allbwn (gyda --print): "text" (rhagosodiad), "json" (canlyniad sengl), neu "stream-json" (ffrydio amser real)]:format:(text json stream-json)'
    '--json-schema[Sgema JSON ar gyfer dilysu allbwn strwythuredig]:schema:'
    '--include-partial-messages[Cynnwys darnau neges rhannol wrth iddynt gyrraedd (gyda --print a --output-format=stream-json)]'
    '--input-format[Fformat mewnbwn (gyda --print): "text" (rhagosodiad) neu "stream-json" (mewnbwn ffrydio amser real)]:format:(text stream-json)'
    '--dangerously-skip-permissions[Osgoi pob gwiriad caniatâd. Argymhellir ar gyfer blychau tywod yn unig heb fynediad i'\''r rhyngrwyd]'
    '--allow-dangerously-skip-permissions[Galluogi dewis i osgoi gwiriadau caniatâd heb alluogi yn ôl y rhagosodiad]'
    '--restricted[Modd cyfyngedig: tynnu'\''r offer sy'\''n rhedeg gorchmynion neu god a WebFetch, anwybyddu gosodiadau user/project/local, a chyfyngu offer ffeiliau i'\''r cyfeiriaduron gwaith]'
    '--max-budget-usd[Uchafswm o ddoleri i'\''w wario ar alwadau API (--print yn unig)]:amount:'
    '--max-turns[Cyfyngu ar nifer y troeon asiantaidd (--print yn unig)]:turns:'
    '--replay-user-messages[Ail-anfon negeseuon defnyddiwr o stdin ar stdout ar gyfer cadarnhad]'
    '--allowed-tools[Rhestr wedi'\''i gwahanu â choma neu ofod o enwau offer a ganiateir (e.e., "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Rhestr wedi'\''i gwahanu â choma neu ofod o enwau offer a ganiateir (fformat camelCase)]:tools:'
    '--tools[Pennu rhestr o offer ar gael o'\''r set adeiledig. Modd argraffu yn unig]:tools:'
    '--disallowed-tools[Rhestr wedi'\''i gwahanu â choma neu ofod o enwau offer na chaniateir (e.e., "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Rhestr wedi'\''i gwahanu â choma neu ofod o enwau offer na chaniateir (fformat camelCase)]:tools:'
    '--mcp-config[Llwytho gweinyddion MCP o ffeil neu linyn JSON (wedi'\''i wahanu ag ofod)]:configs:'
    '--system-prompt[Anogwr system i'\''w ddefnyddio ar gyfer y sesiwn]:prompt:'
    '--system-prompt-file[Darllen anogwr system o ffeil]:file:_files'
    '--append-system-prompt[Atodi anogwr system i anogwr system rhagosodedig]:prompt:'
    '--append-system-prompt-file[Darllen anogwr system o ffeil a'\''i atodi i'\''r anogwr system rhagosodedig]:file:_files'
    '(--append-subagent-system-prompt-file)--append-subagent-system-prompt[Atodi testun i anogwr system pob is-asiant (--print yn unig)]:prompt:'
    '(--append-subagent-system-prompt)--append-subagent-system-prompt-file[Darllen testun o ffeil a’i atodi i anogwyr system is-asiantau (--print yn unig)]:file:_files'
    '--system-prompt-snapshot[Cofnodi'\''r anogwr system unwaith fesul sgwrs a'\''i ailddefnyddio air am air ar bob cais ac wrth ailddechrau (on, y rhagosodiad) neu ei rendro o'\''r newydd ar bob cais (off)]:mode:(on off)'
    '--permission-mode[Modd caniatâd i'\''w ddefnyddio ar gyfer y sesiwn]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Pwy sy'\''n ateb anogwyr caniatâd gyda --print: "host" (gwesteiwr yr SDK neu --permission-prompt-tool) neu "none" (gwrthodir unrhyw beth a fyddai'\''n gofyn)]:target:(host none)'
    '--permission-prompt-tool[Offeryn MCP i'\''w ddefnyddio ar gyfer anogwyr caniatâd (--print yn unig)]:tool:'
    '(-c --continue)'{-c,--continue}'[Parhau â'\''r sgwrs fwyaf diweddar]'
    '(-r --resume)'{-r,--resume}'[Ailddechrau sgwrs - pennu ID sesiwn neu ddewis yn rhyngweithiol]:sessionId:_claude_sessions'
    '--fork-session[Creu ID sesiwn newydd yn lle ailddefnyddio ID sesiwn gwreiddiol wrth ailddechrau (gyda --resume neu --continue)]'
    '--no-session-persistence[Analluogi parhad sesiwn - ni chaiff sesiynau eu cadw (--print yn unig)]'
    '--model[Model ar gyfer y sesiwn gyfredol. Pennu alias ar gyfer y model diweddaraf (e.e., '\''sonnet'\'' neu '\''opus'\'')]:model:_claude_model_names'
    '--agent[Asiant ar gyfer y sesiwn gyfredol. Mae'\''n gwrthwneud y gosodiad '\''agent'\'']:agent:_claude_agent_names'
    '--betas[Penawdau beta i'\''w cynnwys mewn ceisiadau API (defnyddwyr allwedd API yn unig)]:betas:'
    '--fallback-model[Galluogi dirwyneb awtomatig i'\''r model a bennwyd pan fo'\''r model rhagosodedig dan straen (--print yn unig)]:model:_claude_model_names'
    '--settings[Llwybr i ffeil JSON gosodiadau neu linyn JSON i lwytho gosodiadau ychwanegol]:file-or-json:_files'
    '--add-dir[Cyfeiriaduron ychwanegol i ganiatáu mynediad offer]:directories:_directories'
    '--ide[Cysylltu'\''n awtomatig ag IDE wrth gychwyn os oes union un IDE dilys ar gael]'
    '--desktop[Agor yn ap Claude Desktop yn lle'\''r derfynell (gyda --continue neu --resume <id> i ddewis y sesiwn)]'
    '--strict-mcp-config[Defnyddio gweinyddion MCP o --mcp-config yn unig ac anwybyddu pob gosodiad MCP arall]'
    '--session-id[ID sesiwn penodol i'\''w ddefnyddio ar gyfer y sgwrs (rhaid bod yn UUID dilys)]:uuid:'
    '--agents[Gwrthrych JSON yn diffinio asiantau cyfaddas]:json:'
    '--advisor[Galluogi’r offeryn cynghorydd ar ochr y gweinydd ar gyfer y sesiwn hon gydag alias model neu ID model llawn]:model:_claude_model_names'
    '--teammate-mode[Sut mae cyd-chwaraewyr tîm asiantau yn cael eu dangos]:mode:(in-process auto tmux iterm2)'
    '--setting-sources[Rhestr wedi'\''i gwahanu â choma o ffynonellau gosodiadau i'\''w llwytho (user, project, local)]:sources:'
    '--plugin-dir[Cyfeiriadur i lwytho ategion ohono ar gyfer y sesiwn hon yn unig (ailadroddadwy)]:paths:_directories'
    '--disable-slash-commands[Analluogi pob gorchymyn slaes]'
    '(--bg --background)'{--bg,--background}'[Cychwyn y sesiwn fel asiant cefndir a dychwelyd ar unwaith]'
    '(-w --worktree)'{-w,--worktree}'[Creu coeden waith git newydd ar gyfer y sesiwn hon (pennu enw yn ddewisol)]::name:'
    '--tmux=-[Creu sesiwn tmux ar gyfer y goeden waith (angen --worktree). Yn defnyddio paenau brodorol iTerm2 pan fyddant ar gael; --tmux=classic ar gyfer tmux traddodiadol]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Gosod enw arddangos ar gyfer y sesiwn hon]:name:'
    '--effort[Lefel ymdrech ar gyfer y sesiwn gyfredol]:level:(low medium high xhigh max)'
    '--autocompact[Maint ffenestr awto-gywasgu (auto, neu 100k-1M tocyn)]:size:(auto)'
    '--debug-file[Ysgrifennu cofnodion dadfygio i lwybr ffeil penodol (yn galluogi modd dadfygio yn ymhlyg)]:path:_files'
    '--from-pr[Ailddechrau sesiwn wedi'\''i gysylltu â PR yn ôl rhif/URL, neu agor dewisydd rhyngweithiol]::value:'
    '--teleport[Ailddechrau sesiwn teleport, gan bennu ID sesiwn yn ddewisol]::session:'
    '(--remote)--cloud[Creu sesiwn cwmwl gyda'\''r disgrifiad a roddwyd, neu gysylltu ag un sy'\''n bodoli yn ôl ID sesiwn neu URL claude.ai/code]::description-or-session:'
    '(--cloud)--remote[Alias anghymeradwy ar gyfer --cloud]::description-or-session:'
    '--environment[Creu sesiwn cwmwl newydd sy'\''n rhedeg ar yr amgylchedd hunan-westeiedig a roddwyd (ccpool_...)]:environment_id:'
    '--ref[Gyda --environment: seilio checkout y sesiwn newydd ar ref a enwir yn lle HEAD lleol]:branch:'
    '(--remote-control --rc)'{--remote-control,--rc}'[Cychwyn sesiwn rhyngweithiol gyda Rheolaeth o Bell wedi’i galluogi (wedi’i enwi’n ddewisol)]::name:'
    '--remote-control-session-name-prefix[Rhagddodiad ar gyfer enwau sesiwn Rheolaeth o Bell a gynhyrchir yn awtomatig]:prefix:'
    '--chrome[Galluogi integreiddiad Claude yn Chrome]'
    '--no-chrome[Analluogi integreiddiad Claude yn Chrome]'
    '--plugin-url[Nôl .zip ategyn o URL ar gyfer y sesiwn hon yn unig (ailadroddadwy)]:url:'
    '--file[Adnoddau ffeil i'\''w lawrlwytho wrth gychwyn (fformat: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Galluogi awgrymiadau anogwr (yn allyrru anogwr nesaf a ragfynegir mewn modd print/SDK)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Anfon testun is-asiant a blociau meddwl ymlaen fel negeseuon (gyda --print a stream-json)]'
    '--include-hook-events[Cynnwys pob digwyddiad cylchred bywyd bachyn yn y ffrwd allbwn (gyda stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Symud adrannau fesul peiriant i'\''r neges defnyddiwr cyntaf i wella ailddefnydd storfa anogwr]'
    '--brief[Galluogi'\''r offeryn SendUserMessage ar gyfer cyfathrebu asiant-i-ddefnyddiwr]'
    '*--channels[(Rhagolwg ymchwil) Gweinyddion MCP y dylid gwrando ar eu hysbysiadau sianel (plugin\:<name>@<marketplace>)]:entries:'
    '*--dangerously-load-development-channels[Galluogi sianeli nad ydynt ar y rhestr ganiatáu gymeradwy, ar gyfer datblygu lleol (plugin\:<name>@<marketplace> neu server\:<name>)]:entries:'
    '--init[Rhedeg bachau Setup gyda’r cydweddwr init cyn y sesiwn (--print yn unig)]'
    '--init-only[Rhedeg bachau Setup a SessionStart, yna gadael heb ddechrau sgwrs]'
    '--maintenance[Rhedeg bachau Setup gyda’r cydweddwr maintenance cyn y sesiwn (--print yn unig)]'
    '--safe-mode[Cychwyn gyda phob addasiad wedi'\''i analluogi (defnyddiol ar gyfer datrys problemau ffurfweddiad diffygiol)]'
    '--bare[Modd minimal: hepgor bachau, LSP, cydweddu ategion, priodoli, awto-gof, a darganfod CLAUDE.md yn awtomatig]'
    '--ax-screen-reader[Rendro allbwn cyfeillgar i ddarllenydd sgrin (testun gwastad, dim borderi addurniadol na animeiddiadau)]'
    '(-v --version)'{-v,--version}'[Allbwn rhif fersiwn]'
    '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]'
  )

  # Stop at the first non-option word, so that the options after a command reach
  # that command's own specs instead of being consumed here
  _arguments -C -A '-*' \
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
            '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]' \
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
            '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]'
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
            '(-s --scope)'{-s,--scope}'[Cwmpas ffurfweddu (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Math trafnidiaeth (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Gosod newidyn amgylchedd (e.e., -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Gosod pennawd WebSocket]:header:' \
            '--client-id[ID cleient OAuth ar gyfer gweinyddion HTTP/SSE]:clientId:' \
            '--client-secret[Gofyn am gyfrinach cleient OAuth (neu osod y newidyn amgylchedd MCP_CLIENT_SECRET)]' \
            '--callback-port[Porth sefydlog ar gyfer galwad-yn-ôl OAuth (ar gyfer gweinyddion sydd angen URIs ailgyfeirio wedi'\''u cofrestru ymlaen llaw)]:port:' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Cwmpas ffurfweddu (local, user, project) - tynnu o gwmpas presennol os na phennir]:scope:(local user project)' \
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
            '(-s --scope)'{-s,--scope}'[Cwmpas ffurfweddu (local, user, project)]:scope:(local user project)' \
            '--client-secret[Gofyn am gyfrinach cleient OAuth (neu osod y newidyn amgylchedd MCP_CLIENT_SECRET)]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Cwmpas ffurfweddu (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]'
          ;;
        login)
          _arguments \
            '--no-browser[Argraffu'\''r URL awdurdodi yn lle agor porwr (ar gyfer sesiynau SSH/heb sgrin)]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
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
    'configure:Dangos dewisiadau ategyn a pha rai sydd heb eu gosod, neu gadw gwerthoedd o stdin'
    'install:Gosod ategyn o farchnadoedd sydd ar gael'
    'i:Gosod ategyn o farchnadoedd sydd ar gael (byrfodd ar gyfer install)'
    'init:Sgaffaldio ategyn newydd (yn llwytho'\''n awtomatig y sesiwn nesaf)'
    'new:Sgaffaldio ategyn newydd (alias ar gyfer init)'
    'uninstall:Dadosod ategyn wedi'\''i osod'
    'remove:Dadosod ategyn wedi'\''i osod (alias ar gyfer uninstall)'
    'enable:Galluogi ategyn wedi'\''i analluogi'
    'disable:Analluogi ategyn wedi'\''i alluogi'
    'update:Diweddaru ategyn i'\''r fersiwn ddiweddaraf'
    'eval:Rhedeg achosion eval yn erbyn ategyn ac adrodd canlyniadau wedi'\''u sgorio'
    'prune:Tynnu dibyniaethau a osodwyd yn awtomatig nad oes eu hangen mwyach'
    'autoremove:Tynnu dibyniaethau a osodwyd yn awtomatig nad oes eu hangen mwyach (alias ar gyfer prune)'
    'tag:Creu tag git {name}--v{version} ar gyfer rhyddhad ategyn'
    'test:Rhedeg profion mod'
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
            '--strict[Trin rhybuddion fel gwallau (cod gadael 1)]' \
            '--profile[Gadael gyda chod 1 hefyd pan fyddai’r catalog a enwir yn gwrthod cyflwyno’r ategyn ar wiriad y mae’r gorchymyn hwn yn ei redeg]:name:(directory)' \
            '--json[Allbynnu'\''r adroddiad dilysu fel JSON (yr un codau gadael)]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:llwybr:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Cwmpas gosod]:scope:(user project local)' \
            '--accept-command[Derbyn y gorchymyn a ddatganwyd gan y farchnad y nododd rhediad --json blaenorol ei sha256 fel shownCommand.sha256]:sha256:' \
            '*--config[Gosod dewis userConfig a ddatganwyd ym maniffest yr ategyn (ailadroddadwy)]:key=value:' \
            '--marketplace[Gosod yr ategyn wrth ei enw moel o’r farchnad yn y ffynhonnell hon (owner/repo, URL git neu https, neu lwybr), gan ychwanegu’r farchnad yn gyntaf os oes angen]:source:' \
            '--registry[Ar gyfer gosodiad package@npm: datrys a llwytho i lawr o’r gofrestrfa npm hon]:url:' \
            '(-y --yes)'{-y,--yes}'[Derbyn y gorchymyn a ddangosir a ddatganwyd gan y farchnad heb yr anogwr cadarnhau]' \
            '--json[Argraffu un llinell ganlyniad y gall peiriant ei darllen yn lle'\''r neges i bobl]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:ategyn:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Cwmpas gosod]:scope:(user project local)' \
            '--keep-data[Cadw cyfeiriadur data parhaus yr ategyn]' \
            '--prune[Tynnu hefyd ddibyniaethau a osodwyd yn awtomatig nad oes eu hangen mwyach]' \
            '(-y --yes)'{-y,--yes}'[Hepgor anogwr cadarnhau --prune]' \
            '--json[Argraffu un llinell ganlyniad y gall peiriant ei darllen yn lle'\''r neges i bobl (nid gyda --prune)]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:ategyn:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Cwmpas gosod]:scope:(user project local)' \
            '--json[Argraffu un llinell ganlyniad y gall peiriant ei darllen yn lle'\''r neges i bobl]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:ategyn:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Analluogi pob ategyn wedi'\''i alluogi]' \
            '(-s --scope)'{-s,--scope}'[Cwmpas gosod]:scope:(user project local)' \
            '--json[Argraffu un llinell ganlyniad y gall peiriant ei darllen yn lle'\''r neges i bobl]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '--accept-command[Derbyn y gorchymyn a ddatganwyd gan y farchnad y nododd rhediad --json blaenorol ei sha256 fel shownCommand.sha256]:sha256:' \
            '(-s --scope)'{-s,--scope}'[Cwmpas gosod]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Derbyn y gorchymyn a ddangosir a ddatganwyd gan y farchnad heb yr anogwr cadarnhau]' \
            '--json[Argraffu un llinell ganlyniad y gall peiriant ei darllen yn lle'\''r neges i bobl]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:ategyn:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Allbynnu fel JSON]' \
            '--available[Cynnwys ategion sydd ar gael o farchnadoedd (angen --json)]' \
            '--data-size[Mesur cyfeiriadur data cadw pob ategyn wedi’i osod, neu’r ategyn a enwir yn unig (angen --json)]::plugin:_claude_installed_plugins' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Tocio yn y cwmpas]:scope:(user project local)' \
            '--dry-run[Rhestru'\''r hyn a fyddai'\''n cael ei dynnu heb dynnu dim]' \
            '(-y --yes)'{-y,--yes}'[Hepgor yr anogwr cadarnhau]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]'
          ;;
        configure)
          _arguments \
            '--json[Allbynnu fel JSON]' \
            '--values-stdin[Darllen gwerthoedd dewisiadau o stdin fel gwrthrych JSON o linynnau un llinell; mae dewisiadau a hepgorir yn cadw eu gwerthoedd]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:ategyn:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Disgrifiad y maniffest]:text:' \
            '--author[Enw'\''r awdur (rhagosodiad: git config user.name)]:name:' \
            '--author-email[E-bost yr awdur (rhagosodiad: git config user.email)]:email:' \
            '--with[Cydrannau i'\''w sgaffaldio hefyd]:components:' \
            '(-f --force)'{-f,--force}'[Trosysgrifo .claude-plugin/ sy'\''n bodoli yn y targed]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:enw:'
          ;;
        eval)
          if [[ $words[2] == init ]]; then
            _arguments \
              '--bare[Ysgrifennu templed gwag yn lle cynnal y cyfweliad]' \
              '--eval-dir[Cyfeiriadur o dan y cyfeiriadur cyfredol i ysgrifennu achosion iddo]:dir:_directories' \
              '(-i --interactive)'{-i,--interactive}'[Cynnal y cyfweliad awduro (angen terfynell ryngweithiol)]' \
              '(-h --help)'{-h,--help}'[Dangos cymorth]' \
              '::name:'
            return
          fi
          _arguments \
            '--case[Hidlo achosion yn ôl glob enw]:glob:' \
            '*--tag[Hidlo achosion yn ôl tag (ailadroddadwy)]:tag:' \
            '--runs[Gwrthwneud nifer y rhediadau fesul achos (rhagosodiad: case.runs, neu 3 fel arall)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Cynnal hyd at n rhediad asiant ar yr un pryd (1-8; rhagosodiad 1)]:n:' \
            '--model[Gwrthwneud y model ar gyfer pob achos]:model:_claude_model_names' \
            '--judge-model[Gwrthwneud model y graddiwr LLM (rhagosodiad: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Terfyn cost caeth; erthylu ac adrodd canlyniadau rhannol os cyrhaeddir ef (cod gadael 2)]:usd:' \
            '--output-dir[Cyfeiriadur ar gyfer aggregate-result.json]:dir:_directories' \
            '--eval-dir[Enw'\''r cyfeiriadur (o dan yr ategyn) sy'\''n dal yr achosion eval]:dir:' \
            '--json[Argraffu canlyniad llawn y rhediad fel JSON i stdout, neu ei ysgrifennu i'\''r ffeil .json hon]::path:_files' \
            '--threshold[Gadael gyda chod gadael 1 os yw sgôr unrhyw achos yn is na'\''r trothwy hwn (rhagosodiad: 1.0)]:threshold:' \
            '*--allow-tools[Caniatâd gweithredwr ar gyfer offer cyfyngedig (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '*--disallow-tools[Offer adeiledig i’w cadw rhag Claude ym mhob achos, hyd yn oed os rhoddwyd caniatâd]:tools:' \
            '(--no-scaffold)--scaffold[Rhedeg scaffold_script pob achos (yn rhedeg bash a ddarparwyd gan yr awdur o dan eich cyfrif chi; i ffwrdd yn ôl y rhagosodiad)]' \
            '(--scaffold)--no-scaffold[Hepgor scaffold_script yn benodol]' \
            '--trust-plugin[Datgan eich bod yn ymddiried yn yr ategyn hwn a'\''i gyfres eval, gan hepgor yr anogwr ymddiriedaeth rhediad cyntaf (ar gyfer CI)]' \
            '--ablation[Rhedeg grŵp cymharu sylfaenol heb ategyn ac adrodd y gwahaniaeth sgôr]:mode:(none with-without)' \
            '--mocks[Dirprwyon ffug ar gyfer gweinyddion MCP, o <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Gyda --mocks record: cychwyn hefyd y prosesau gweinydd MCP go iawn nad oes ganddynt ffug]' \
            '--keep-temp[Cadw cyfeiriaduron sgaffald ar gyfer dadfygio]' \
            '--verbose[Cofnodi digwyddiadau olrhain fesul neges yn y cofnod dadfygio]' \
            '--report[Ysgrifennu'\''r adroddiad HTML hunangynhwysol i'\''r llwybr hwn yn lle'\''r cyfeiriadur canlyniadau]:path:_files' \
            '(--no-publish)--publish-report[Mynnu hefyd fod yr adroddiad yn cael ei gyhoeddi i claude.ai]' \
            '(--publish-report)--no-publish[Cadw'\''r adroddiad HTML yn lleol yn unig; hepgor ei gyhoeddi i claude.ai]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '::target: _alternative "commands\:eval command\:(init)" "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Gwthio'\''r tag i --remote ar ôl ei greu]' \
            '--dry-run[Argraffu'\''r hyn a fyddai'\''n cael ei dagio heb ei greu]' \
            '(-f --force)'{-f,--force}'[Hepgor y gwiriadau coeden waith fudr a thag sydd eisoes yn bodoli]' \
            '(-m --message)'{-m,--message}'[Neges anodi'\''r tag (defnyddiwch %s ar gyfer y fersiwn)]:msg:' \
            '--remote[Y pellennig i wthio iddo gyda --push]:name:' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '::dir:_directories'
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
            '--sparse[Cyfyngu'\''r checkout i gyfeiriaduron penodol drwy git sparse-checkout (ar gyfer monorepos)]:paths:' \
            '--scope[Ble i ddatgan y farchnad]:scope:(user project local)' \
            '--json[Argraffu un llinell ganlyniad y gall peiriant ei darllen fel y llinell olaf ar stdout]' \
            '--claudeai[Ychwanegu'\''r farchnad o'\''r enw hwn y mae claude.ai yn ei chynnal ar eich cyfer]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:ffynhonnell:'
          ;;
        list)
          _arguments \
            '--json[Allbynnu fel JSON]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Tynnu datganiad y farchnad o gwmpas gosodiadau penodol (hepgor i'\''w dynnu o bob cwmpas)]:scope:(user project local)' \
            '--json[Argraffu un llinell ganlyniad y gall peiriant ei darllen fel y llinell olaf ar stdout]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '1:enw:'
          ;;
        update)
          _arguments \
            '--json[Gydag enw marchnad: argraffu un llinell ganlyniad y gall peiriant ei darllen fel y llinell olaf ar stdout]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}

_claude_install() {
  _arguments \
    '--force[Gorfodi gosodiad hyd yn oed os eisoes wedi'\''i osod]' \
    '(-h --help)'{-h,--help}'[Dangos cymorth]' \
    '::target:(stable latest)'
}

_claude_agents() {
  _arguments \
    '*--add-dir[Cyfeiriadur ychwanegol i ganiatáu mynediad offer mewn sesiynau a anfonwyd]:directory:_directories' \
    '--agent[Asiant rhagosodedig ar gyfer sesiynau a anfonwyd o'\''r golwg asiant]:agent:_claude_agent_names' \
    '--all[Gyda --json: cynnwys sesiynau cefndir cwblhawyd hefyd]' \
    '--allow-dangerously-skip-permissions[Gwneud modd osgoi-caniatâd ar gael i sesiynau a anfonwyd]' \
    '--cwd[Dangos sesiynau cefndir a gychwynnwyd o dan lwybr yn unig]:path:_directories' \
    '--dangerously-skip-permissions[Alias ar gyfer --permission-mode bypassPermissions]' \
    '--effort[Lefel ymdrech ragosodedig ar gyfer sesiynau a anfonwyd]:level:(low medium high xhigh max)' \
    '--json[Argraffu sesiynau gweithredol fel arae JSON a gadael]' \
    '*--mcp-config[Ffurfweddiad gweinydd MCP i'\''w gymhwyso i sesiynau a anfonwyd]:config:' \
    '--model[Model rhagosodedig ar gyfer sesiynau a anfonwyd o'\''r golwg asiant]:model:_claude_model_names' \
    '--permission-mode[Modd caniatâd rhagosodedig ar gyfer sesiynau a anfonwyd]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Llwytho ategion o gyfeiriadur ar gyfer y golwg asiant a sesiynau a anfonwyd]:path:_directories' \
    '--setting-sources[Rhestr wedi'\''i gwahanu â choma o ffynonellau gosodiadau i'\''w llwytho (user, project, local)]:sources:' \
    '--settings[Ffeil gosodiadau neu linyn JSON i'\''w gymhwyso]:file-or-json:_files' \
    '--strict-mcp-config[Defnyddio gweinyddion MCP o --mcp-config yn unig mewn sesiynau a anfonwyd]' \
    '--restricted[Cychwyn sesiynau a anfonwyd mewn modd cyfyngedig]' \
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
        login)
          _arguments \
            '--email[Llenwi'\''r cyfeiriad e-bost ymlaen llaw ar y dudalen mewngofnodi]:email:' \
            '--sso[Gorfodi llif mewngofnodi SSO]' \
            '(--claudeai)--console[Defnyddio Anthropic Console (bilio defnydd API) yn lle tanysgrifiad Claude]' \
            '(--console)--claudeai[Defnyddio tanysgrifiad Claude (rhagosodiad)]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]'
          ;;
        status)
          _arguments \
            '(--text)--json[Allbynnu fel JSON (rhagosodiad)]' \
            '(--json)--text[Allbynnu fel testun darllenadwy i bobl]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]'
          ;;
        logout)
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
        critique)
          _arguments \
            '--model[Gwrthwneud pa fodel a ddefnyddir]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]'
          ;;
        defaults)
          _arguments \
            '--label[Dangos dim ond rheolau y mae eu label yn dechrau gyda'\''r rhagddodiad hwn (heb wahaniaethu rhwng priflythrennau a llythrennau bach)]:prefix:' \
            '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Hepgor yr anogwr cadarnhau]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]'
          ;;
        config)
          _arguments \
            '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Llwybr i ffurfweddiad YAML porth]:path:_files' \
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
            '--dry-run[Rhestru'\''r hyn a fyddai'\''n cael ei ddileu heb ddileu dim]' \
            '(-y --yes)'{-y,--yes}'[Hepgor yr anogwr cadarnhau]' \
            '(-i --interactive)'{-i,--interactive}'[Gofyn am gadarnhad ar gyfer pob eitem cyn dileu]' \
            '(1)--all[Dileu'\''r cyflwr ar gyfer pob prosiect (ni ellir ei ddefnyddio ynghyd â llwybr)]' \
            '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_purge() {
  _arguments \
    '--dry-run[Rhestru'\''r hyn a fyddai'\''n cael ei ddileu heb ddileu dim]' \
    '(-y --yes)'{-y,--yes}'[Hepgor yr anogwr cadarnhau]' \
    '(-i --interactive)'{-i,--interactive}'[Gofyn am gadarnhad ar gyfer pob eitem cyn dileu]' \
    '(1)--all[Dileu'\''r cyflwr ar gyfer pob prosiect (ni ellir ei ddefnyddio ynghyd â llwybr)]' \
    '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]' \
    '(--all)::path:_directories'
}

_claude_ultrareview() {
  _arguments \
    '--json[Argraffu'\''r llwyth bugs.json crai yn lle canfyddiadau wedi'\''u fformatio]' \
    '--timeout[Uchafswm munudau i aros i'\''r adolygiad orffen (rhagosodiad: 45)]:minutes:' \
    '(--no-post)--post[Postio canfyddiadau'\''r adolygiad gorffenedig i'\''r PR yn eich enw chi (targedau PR yn unig; un sylw plaen, nid adolygiad)]' \
    '(--post)--no-post[Peidio â phostio'\''r canfyddiadau i'\''r PR (y rhagosodiad)]' \
    '--trust-workspace[Ymddiried yn y ffolder gyfredol ar gyfer y rhediad hwn yn unig, heb ofyn (ar gyfer sgriptiau a CI)]' \
    '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]' \
    '1:targed:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Ailgychwyn pob sesiwn cefndir sy'\''n rhedeg]' \
    '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Taflu hefyd ymrwymiadau heb eu gwthio a newidiadau heb eu hymrwymo yn y goeden waith (rhowch y commit@worktree-id a adroddwyd gan claude rm blaenorol)]:commit@worktree-id:' \
    '--force-remove-worktree[Dileu cyfeiriadur y goeden waith er na allai'\''r bachyn WorktreeRemove na git ei dynnu (rhowch y worktree-id a adroddwyd gan claude rm blaenorol)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]' \
    '1:session:_claude_background_sessions'
}

_claude_self_hosted_runner() {
  _arguments \
    '--api-url[URL sylfaen API (rhagosodiad: https://api.anthropic.com)]:url:' \
    '--environment-secret-file[Llwybr i ffeil gyfrinach yr amgylchedd]:path:_files' \
    '--lock-to-account[Cloi’r rhedwr i un cyfrif wrth gofrestru]:id:' \
    '--client-label[Label arsylwadwyedd a anfonir wrth gofrestru (rhagosodiad: hostname)]:label:' \
    '(--proxy-authorization-file --agent-proxy-url)--proxy-authorization-command[Gorchymyn y mae ei stdout yn bennyn Proxy-Authorization ar gyfer dirprwyon allanol]:shell command:' \
    '(--proxy-authorization-command --agent-proxy-url)--proxy-authorization-file[Ffeil sy’n dal y pennyn Proxy-Authorization ar gyfer dirprwyon allanol]:path:_files' \
    '(--proxy-authorization-command --proxy-authorization-file)--agent-proxy-url[Llwybro pob sesiwn drwy’r dirprwy asiant yn yr URL hwn (https yn unig)]:url:' \
    '--capacity[Uchafswm sesiynau cydamserol (rhagosodiad: 1)]:n:' \
    '--base-dir[Cyfeiriadur sylfaen ar gyfer checkouts ystorfeydd (rhagosodiad: /workspace)]:path:_directories' \
    '--exec-path[Deuaidd i’w lansio ar gyfer sesiynau plentyn (rhagosodiad: y deuaidd hwn)]:path:_files' \
    '--hooks-dir[Cyfeiriadur sgriptiau bachau cylchred bywyd (checkout, command, post-session)]:path:_directories' \
    '--session-stop-grace-sec[Pa mor hir i aros am adael glân ar ôl i sesiwn ddod i ben (rhagosodiad: 5)]:n:' \
    '--post-session-hook-timeout-sec[Cyllideb SIGTERM ar gyfer y bachyn post-session (rhagosodiad: 60)]:n:' \
    '--checkout-hook-timeout-min[Cyllideb amser real ar gyfer pob rhediad o’r bachyn checkout (rhagosodiad: 30; 0 yn analluogi)]:n:' \
    '--drain-wait-sec[Ar SIGTERM/SIGINT, aros hyd at N eiliad am waith sydd ar y gweill (rhagosodiad: 0)]:n:' \
    '--drain-marker-file[Ffeil farcio y mae’r gwesteiwr yn cyhoeddi draenio graslon â hi]:path:_files' \
    '*--git-ssh-rewrite[Ailysgrifennu URLau ffynhonnell https://<host>/... i git@<host>:... (ailadroddadwy)]:host:' \
    '*--git-host-rewrite[Ailysgrifennu URLau ffynhonnell https://<f>/... i https://<t>/... (ailadroddadwy)]:from=to:' \
    '--use-anthropic-git-proxy[Defnyddio git a reolir gan Anthropic. RHYBUDD: yn dileu ac yn disodli ffurfwedd git lefel HOME, defnyddiwch dan gyfrif penodedig yn unig]' \
    '--configure-git[Gosod hunaniaeth git fyd-eang a galluogi llofnodi commits drwy wasanaeth llofnodi Anthropic. Yn ysgrifennu ~/.gitconfig]' \
    '--push-outcome-on-release[Gwthio canghennau canlyniad a draciwyd pan fydd y rhedwr yn dod â sesiwn anghyflawn i ben]' \
    '--trust-workspace[Hadu ymddiriedaeth barhaus ar gyfer llwybrau ystorfa pob sesiwn (rhagosodiad: true)]::bool:(true false)' \
    '--remove-session-state[Tynnu cyflwr pob sesiwn pan ddaw sesiwn i ben (rhagosodiad: false)]::bool:(true false)' \
    '--diff-finds-nested-repository[Dangos ystorfa a glonwyd i is-ffolder yn y paen Changes; angen --capacity 1 (rhagosodiad: false)]::bool:(true false)' \
    '--confine-repo-settings[Modd gwarchodwr cyfyngu gosodiadau a ymrwymwyd i’r ystorfa (rhagosodiad: warn)]:mode:(warn enforce off)' \
    '--server-auto-mode-lists[Pa restrau dosbarthydd modd awto o’r gweinydd y caiff sesiwn eu derbyn (rhagosodiad: no-allow)]:mode:(all no-allow none)' \
    '--host-config-snapshot[Ble cedwir ciplun cychwyn ffurfwedd y gwesteiwr (rhagosodiad: disk)]:mode:(disk memory)' \
    '--health-port[Porth ar gyfer gwrandawr HTTP /healthz (rhagosodiad: 8080; 0 yn analluogi)]:port:' \
    '--log-level[Lefel log (rhagosodiad: info)]:level:(info debug)' \
    '--log-file[Copïo logiau’r rhedwr i ffeil hefyd yn y modd atodi (fel tee)]:path:_files' \
    '--exit-if-unused-min[Gadael y rhedwr os na roddir gwaith iddo am N munud]:n:' \
    '--drain-grace-sec[Eiliadau i barhau i holi am waith ar ôl i sesiynau gweithredol orffen (rhagosodiad: 0)]:n:' \
    '--retire-at[Ymddeol y rhedwr ar yr amser Unix absoliwt hwn, mewn eiliadau]:epoch-seconds:' \
    '--defer-shutdown-max-min[Ar y SIGTERM/SIGINT cyntaf, rhoi’r gorau i gymryd gwaith a gorffen cau M munud yn ddiweddarach (rhagosodiad: 0)]:m:' \
    '--release-idle-session-min[Rhyddhau slot sesiwn ar ôl N munud heb fewnbwn defnyddiwr]:n:' \
    '--startup-timeout-min[Rhyddhau slot sesiwn os nad yw’r plentyn wedi gorffen cychwyn ar ôl N munud (rhagosodiad: 15; 0 yn analluogi)]:n:' \
    '--kill-session-after-min[Cyfyngu oes amser real plentyn sesiwn i N munud]:n:' \
    '--debug-token-dir[DADFYGIO YN UNIG: yn ysgrifennu tocynnau byw i’r ddisg. Peidiwch â defnyddio wrth gynhyrchu]:path:_directories' \
    '(-h --help)'{-h,--help}'[Dangos y neges gymorth hon]'
}

_claude_remote_control() {
  _arguments \
    '--name[Enw ar gyfer y sesiwn (a ddangosir yn claude.ai/code)]:name:' \
    '--remote-control-session-name-prefix[Rhagddodiad ar gyfer enwau sesiwn a gynhyrchir yn awtomatig (rhagosodiad: hostname)]:prefix:' \
    '(-c --continue --session-id)'{-c,--continue}'[Ailgysylltu â’r sesiwn a gofnodwyd ddiwethaf ar gyfer y cyfeiriadur hwn neu un o’i goed gwaith git]' \
    '(-c --continue --session-id)--session-id[Ailgysylltu â sesiwn benodol yn ôl ID]:id:' \
    '--permission-mode[Modd caniatâd ar gyfer sesiynau a lansiwyd]:mode:(acceptEdits auto bypassPermissions default dontAsk plan)' \
    '(--no-chrome)--chrome[Galluogi Claude in Chrome ar gyfer sesiynau a lansiwyd]' \
    '(--chrome)--no-chrome[Analluogi Claude in Chrome ar gyfer sesiynau a lansiwyd]' \
    '(-d --debug)'{-d,--debug}'[Galluogi modd dadfygio gyda hidlo categori dewisol]::filter:' \
    '--debug-file[Ysgrifennu logiau dadfygio i ffeil]:path:_files' \
    '(-v --verbose)'{-v,--verbose}'[Galluogi allbwn manwl]' \
    '--spawn[Modd lansio (rhagosodiad: same-dir)]:mode:(same-dir worktree session)' \
    '--capacity[Uchafswm sesiynau cydamserol yn y modd worktree neu same-dir (rhagosodiad: 32)]:n:' \
    '(--no-create-session-in-dir)--create-session-in-dir[Creu sesiwn ymlaen llaw yn y cyfeiriadur cyfredol (rhagosodiad)]' \
    '(--create-session-in-dir)--no-create-session-in-dir[Peidio â chreu sesiwn ymlaen llaw yn y cyfeiriadur cyfredol]' \
    '(-h --help)'{-h,--help}'[Dangos y cymorth hwn]'
}

_claude_daemon() {
  local -a daemon_commands common_options
  daemon_commands=(
    'run:Rhedeg y goruchwyliwr yn y blaendir'
    'status:Dangos pid, fersiwn ac amser rhedeg y daemon'
    'logs:Dilyn log y daemon (Ctrl-C i atal)'
    'uninstall:Tynnu’r gwasanaeth cefndir (launchctl/systemd)'
    'stop:Cau’r goruchwyliwr a therfynu sesiynau cefndir'
  )
  common_options=(
    '--json-path[Ffeil ffurfweddu (rhagosodiad: ~/.claude/daemon.json)]:path:_files'
    '--log-file[Ffeil log (rhagosodiad: ~/.claude/daemon.log)]:path:_files'
    '(-h --help)'{-h,--help}'[Dangos y cymorth hwn]'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    $common_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'gorchmynion daemon' daemon_commands
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
            '--any[Atal daemon dros dro (nid gwasanaeth) hefyd]' \
            '--keep-workers[Gadael sesiynau datgysylltiedig yn rhedeg]'
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
    '--dry-run[Dangos yr hyn a fyddai'\''n cael ei fewnforio heb ysgrifennu dim]' \
    '--yes[Hepgor y dewisydd rhyngweithiol (ar arwynebau heb sgrin, rhowch --yes=<digest> o ragolwg /import)]' \
    '(-h --help)'{-h,--help}'[Dangos cymorth ar gyfer gorchymyn]' \
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
