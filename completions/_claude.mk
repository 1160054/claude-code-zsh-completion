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
    'mcp:Конфигурирање и управување со MCP сервери'
    'plugin:Управување со приклучоци на Claude Code'
    'agents:Управување со позадински агенти'
    'attach:Отвори позадинска сесија во овој терминал'
    'logs:Испечати го неодамнешниот излез од терминалот на позадинска сесија'
    'stop:Запри позадинска сесија (нејзиниот разговор се зачувува)'
    'respawn:Рестартирај позадинска сесија за да ја извршува тековната верзија на Claude Code'
    'rm:Избриши позадинска сесија, и нејзиниот worktree кога тоа е безбедно'
    'auth:Управување со автентикација'
    'auto-mode:Прегледај или ресетирај ја конфигурацијата на класификаторот за автоматски режим'
    'gateway:Стартувај го gateway за автентикација/телеметрија за претпријатија'
    'import:Увези конфигурација од друг AI агент за програмирање во Claude Code'
    'project:Управување со состојбата на проектот на Claude Code'
    'ultrareview:Стартувај повеќеагентски преглед на код хостиран во облак и испечати ги наодите'
    'setup-token:Поставување на токен за долгорочна автентикација (потребна е Claude претплата)'
    'doctor:Проверка на здравјето на системот за автоматски ажурирања на Claude Code'
    'update:Проверка и инсталација на ажурирања'
    'install:Инсталација на изворна верзија на Claude Code'
  )

  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Вклучи режим на отстранување грешки со опционално филтрирање по категории (на пр. "api,hooks" или "!statsig,!file")]:filter:'
    '--verbose[Препокриј поставка на детален режим од конфигурациската датотека]'
    '(-p --print)'{-p,--print}'[Испечати одговор и излез (за употреба со pipe). Напомена: користете само во доверливи директориуми]'
    '--output-format[Формат на излез (со --print): "text" (стандардно), "json" (еден резултат), или "stream-json" (стримување во реално време)]:format:(text json stream-json)'
    '--json-schema[JSON шема за валидација на структуриран излез]:schema:'
    '--include-partial-messages[Вклучи делумни фрагменти на пораки при нивното пристигнување (со --print и --output-format=stream-json)]'
    '--input-format[Формат на влез (со --print): "text" (стандардно) или "stream-json" (стримуван влез во реално време)]:format:(text stream-json)'
    '--mcp-debug[\[Застарено. Користете --debug наместо тоа\] Вклучи режим на отстранување грешки на MCP (прикажува грешки на MCP серверот)]'
    '--dangerously-skip-permissions[Заобиколи ги сите проверки за дозволи. Препорачливо само за sandbox окружувања без пристап до интернет]'
    '--allow-dangerously-skip-permissions[Овозможи опција за заобиколување на проверки за дозволи без овозможување стандардно]'
    '--restricted[Ограничен режим: отстрани ги алатките што извршуваат команди или код и WebFetch, игнорирај ги user/project/local поставките и ограничи ги алатките за датотеки на работните директориуми]'
    '--max-budget-usd[Максимален износ во долари за трошење на API повици (само --print)]:amount:'
    '--replay-user-messages[Повторно испрати кориснички пораки од stdin на stdout за потврда]'
    '--allowed-tools[Список на дозволени имиња на алатки одделени со запирка или празно место (на пр. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Список на дозволени имиња на алатки одделени со запирка или празно место (формат camelCase)]:tools:'
    '--tools[Наведи список на достапни алатки од вградениот сет. Само во режим print]:tools:'
    '--disallowed-tools[Список на забранети имиња на алатки одделени со запирка или празно место (на пр. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Список на забранети имиња на алатки одделени со запирка или празно место (формат camelCase)]:tools:'
    '--mcp-config[Вчитај MCP сервери од JSON датотека или стринг (одделени со празни места)]:configs:'
    '--system-prompt[Системски prompt за употреба во сесијата]:prompt:'
    '--system-prompt-file[Прочитај системски prompt од датотека]:file:_files'
    '--append-system-prompt[Додај системски prompt на стандардниот системски prompt]:prompt:'
    '--append-system-prompt-file[Прочитај системски prompt од датотека и додај го на стандардниот системски prompt]:file:_files'
    '--system-prompt-snapshot[Запиши го системскиот prompt еднаш по разговор и користи го дословно при секое барање и продолжување (on, стандардно) или генерирај го одново при секое барање (off)]:mode:(on off)'
    '--permission-mode[Режим на дозволи за употреба во сесијата]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Кој одговара на барањата за дозвола со --print: "host" (SDK хостот или --permission-prompt-tool) или "none" (сè што би барало дозвола се одбива)]:target:(host none)'
    '--permission-prompt-tool[MCP алатка за барањата за дозвола (само --print)]:tool:'
    '(-c --continue)'{-c,--continue}'[Продолжи со последниот разговор]'
    '(-r --resume)'{-r,--resume}'[Продолжи разговор - наведете идентификатор на сесија или изберете интерактивно]:sessionId:_claude_sessions'
    '--fork-session[Креирај нов идентификатор на сесија наместо повторна употреба на оригиналниот при продолжување (со --resume или --continue)]'
    '--no-session-persistence[Оневозможи зачувување на сесија - сесиите нема да бидат зачувани (само --print)]'
    '--model[Модел за тековната сесија. Наведете алијас за најновиот модел (на пр. '\''sonnet'\'' или '\''opus'\'')]:model:_claude_model_names'
    '--agent[Агент за тековната сесија. Ја препокрива поставката '\''agent'\'']:agent:_claude_agent_names'
    '--betas[Beta заглавија за вклучување во API барања (само корисници со API клуч)]:betas:'
    '--fallback-model[Овозможи автоматско префрлање на наведениот модел кога стандардниот модел е преоптоварен (само --print)]:model:_claude_model_names'
    '--settings[Патека до JSON датотека со поставки или JSON стринг за вчитување на дополнителни поставки]:file-or-json:_files'
    '--add-dir[Дополнителни директориуми за обезбедување пристап на алатки]:directories:_directories'
    '--ide[Автоматски поврзи се со IDE при стартување ако е достапен точно еден валиден IDE]'
    '--desktop[Отвори во апликацијата Claude Desktop наместо во терминалот (со --continue или --resume <id> за избор на сесијата)]'
    '--strict-mcp-config[Користи само MCP сервери од --mcp-config и игнорирај ги сите други MCP поставки]'
    '--session-id[Одреден идентификатор на сесија за употреба во разговор (мора да биде валиден UUID)]:uuid:'
    '--agents[JSON објект кој дефинира приспособени агенти]:json:'
    '--setting-sources[Список на извори на поставки одделени со запирка за вчитување (user, project, local)]:sources:'
    '--plugin-dir[Директориум за вчитување на приклучоци само за оваа сесија (може да се повтори)]:paths:_directories'
    '--disable-slash-commands[Оневозможи ги сите slash команди]'
    '(--bg --background)'{--bg,--background}'[Стартувај ја сесијата како позадински агент и врати се веднаш]'
    '(-w --worktree)'{-w,--worktree}'[Креирај нов git worktree за оваа сесија (опционално наведете име)]::name:'
    '--tmux=-[Креирај tmux сесија за worktree (потребно е --worktree). Користи изворни панели на iTerm2 кога се достапни; --tmux=classic за традиционален tmux]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Постави прикажано име за оваа сесија]:name:'
    '--effort[Ниво на напор за тековната сесија]:level:(low medium high xhigh max)'
    '--autocompact[Големина на прозорецот за автоматско збивање (auto, или 100k-1M токени)]:size:(auto)'
    '--debug-file[Запиши дневници за отстранување грешки во одредена патека на датотека (имплицитно го овозможува режимот на отстранување грешки)]:path:_files'
    '--from-pr[Продолжи сесија поврзана со PR по број/URL, или отвори интерактивен избирач]::value:'
    '--teleport[Продолжи teleport сесија, опционално наведете идентификатор на сесија]::session:'
    '--cloud[Креирај сесија во облак со дадениот опис, или поврзи се со постоечка преку идентификатор на сесија или claude.ai/code URL]::description-or-session:'
    '--environment[Креирај нова сесија во облак што се извршува на даденото самохостирано окружување (ccpool_...)]:environment_id:'
    '--remote-control[Стартувај интерактивна сесија со овозможена Далечинска контрола (опционално именувана)]::name:'
    '--remote-control-session-name-prefix[Префикс за автоматски генерирани имиња на сесии за Далечинска контрола]:prefix:'
    '--chrome[Овозможи интеграција на Claude во Chrome]'
    '--no-chrome[Оневозможи интеграција на Claude во Chrome]'
    '--plugin-url[Преземи приклучок .zip од URL само за оваа сесија (може да се повтори)]:url:'
    '--file[Датотечни ресурси за преземање при стартување (формат: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Овозможи предлози за prompt (емитува предвиден следен prompt во режим print/SDK)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Проследи текст од подагент и блокови на размислување како пораки (со --print и stream-json)]'
    '--include-hook-events[Вклучи ги сите настани од животниот циклус на hook во излезниот стрим (со stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Премести ги секциите специфични за машина во првата корисничка порака за подобра повторна употреба на prompt-кешот]'
    '--brief[Овозможи ја алатката SendUserMessage за комуникација од агент до корисник]'
    '--safe-mode[Стартувај со оневозможени сите приспособувања (корисно за решавање проблеми со расипана конфигурација)]'
    '--bare[Минимален режим: прескокни hooks, LSP, синхронизација на приклучоци, атрибуција, авто-меморија и авто-откривање на CLAUDE.md]'
    '--ax-screen-reader[Прикажи излез прилагоден за читач на екран (рамен текст, без декоративни рабови или анимации)]'
    '(-v --version)'{-v,--version}'[Испечати број на верзија]'
    '(-h --help)'{-h,--help}'[Прикажи помош за команда]'
  )

  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'команди на claude' main_commands
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
            '(-h --help)'{-h,--help}'[Прикажи помош за команда]' \
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
          _message "без аргументи"
          ;;
      esac
      ;;
  esac
}

_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Стартувај MCP сервер на Claude Code'
    'add:Додај MCP сервер во Claude Code'
    'remove:Отстрани MCP сервер'
    'list:Прикажи список на конфигурирани MCP сервери'
    'get:Преземи детали за MCP серверот'
    'add-json:Додај MCP сервер (stdio или SSE) со JSON стринг'
    'add-from-claude-desktop:Увези MCP сервери од Claude Desktop (само Mac и WSL)'
    'reset-project-choices:Ресетирај ги сите одобрени/одбиени сервери со опсег на проект (.mcp.json) во овој проект'
    'login:Автентицирај се со MCP сервер (HTTP, SSE, или claude.ai конектор)'
    'logout:Исчисти зачувани OAuth акредитиви за MCP сервер'
    'help:Прикажи помош'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Прикажи помош]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'команди на mcp' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Вклучи режим на отстранување грешки]' \
            '--verbose[Препокриј поставка на детален режим од конфигурациската датотека]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на конфигурација (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Тип на пренос (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Постави променлива на околина (на пр. -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Постави WebSocket заглавие]:header:' \
            '--client-id[OAuth идентификатор на клиент за HTTP/SSE сервери]:clientId:' \
            '--client-secret[Побарај OAuth тајна на клиент (или постави ја променливата на околина MCP_CLIENT_SECRET)]' \
            '--callback-port[Фиксна порта за OAuth повратен повик (за сервери што бараат претходно регистрирани URI за пренасочување)]:port:' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на конфигурација (local, user, project) - отстрани од постоечки опсег ако не е наведено]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на конфигурација (local, user, project)]:scope:(local user project)' \
            '--client-secret[Побарај OAuth тајна на клиент (или постави ја променливата на околина MCP_CLIENT_SECRET)]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на конфигурација (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Прикажи помош]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]'
          ;;
        login)
          _arguments \
            '--no-browser[Испечати го URL-то за авторизација наместо да се отвора прелистувач (за SSH/headless сесии)]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:name:_claude_mcp_servers'
          ;;
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Валидирај приклучок или манифест на пазар'
    'marketplace:Управување со пазари на Claude Code'
    'list:Прикажи список на инсталирани приклучоци'
    'details:Прикажи инвентар на компоненти и проектиран трошок на токени за приклучок'
    'configure:Прикажи ги опциите на приклучок и кои не се поставени, или зачувај вредности од stdin'
    'install:Инсталирај приклучок од достапни пазари'
    'i:Инсталирај приклучок од достапни пазари (кратенка за install)'
    'init:Скицирај нов приклучок (автоматски се вчитува во следната сесија)'
    'new:Скицирај нов приклучок (алијас за init)'
    'uninstall:Деинсталирај инсталиран приклучок'
    'remove:Деинсталирај инсталиран приклучок (алијас за uninstall)'
    'enable:Овозможи оневозможен приклучок'
    'disable:Оневозможи овозможен приклучок'
    'update:Ажурирај приклучок на најновата верзија'
    'eval:Стартувај eval случаи против приклучок и извести за бодуваните резултати'
    'prune:Отстрани автоматски инсталирани зависности што повеќе не се потребни'
    'autoremove:Отстрани автоматски инсталирани зависности што повеќе не се потребни (алијас за prune)'
    'tag:Креирај git таг {name}--v{version} за издание на приклучок'
    'test:Изврши ги тестовите на мод'
    'help:Прикажи помош'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Прикажи помош]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'команди на plugin' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '--strict[Третирај ги предупредувањата како грешки (излезен код 1)]' \
            '--json[Испечати го извештајот за валидација како JSON (исти излезни кодови)]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на инсталација]:scope:(user project local)' \
            '*--config[Постави userConfig опција декларирана во манифестот на приклучокот (може да се повтори)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[Прифати ја прикажаната команда декларирана од пазарот без барање за потврда]' \
            '--json[Испечати една машински читлива линија со резултат наместо пораката за луѓе]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на инсталација]:scope:(user project local)' \
            '--keep-data[Зачувај го директориумот со трајни податоци на приклучокот]' \
            '--prune[Отстрани ги и автоматски инсталираните зависности што повеќе не се потребни]' \
            '(-y --yes)'{-y,--yes}'[Прескокни го барањето за потврда на --prune]' \
            '--json[Испечати една машински читлива линија со резултат наместо пораката за луѓе (не со --prune)]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на инсталација]:scope:(user project local)' \
            '--json[Испечати една машински читлива линија со резултат наместо пораката за луѓе]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Оневозможи ги сите овозможени приклучоци]' \
            '(-s --scope)'{-s,--scope}'[Опсег на инсталација]:scope:(user project local)' \
            '--json[Испечати една машински читлива линија со резултат наместо пораката за луѓе]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на инсталација]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Прифати ја прикажаната команда декларирана од пазарот без барање за потврда]' \
            '--json[Испечати една машински читлива линија со резултат наместо пораката за луѓе]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Излез како JSON]' \
            '--available[Вклучи ги достапните приклучоци од пазарите (потребно е --json)]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Исчисти во опсег]:scope:(user project local)' \
            '--dry-run[Прикажи список на она што би се отстранило без отстранување]' \
            '(-y --yes)'{-y,--yes}'[Прескокни го барањето за потврда]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]'
          ;;
        configure)
          _arguments \
            '--json[Излез како JSON]' \
            '--values-stdin[Прочитај ги вредностите на опциите од stdin како JSON објект од едноредни стрингови; изоставените опции ги задржуваат своите вредности]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Опис во манифестот]:text:' \
            '--author[Име на авторот (стандардно: git config user.name)]:name:' \
            '--author-email[Е-пошта на авторот (стандардно: git config user.email)]:email:' \
            '--with[Компоненти што исто така треба да се скицираат]:components:' \
            '(-f --force)'{-f,--force}'[Презапиши го постоечкиот .claude-plugin/ во целта]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Филтрирај случаи по glob шаблон за име]:glob:' \
            '*--tag[Филтрирај случаи по ознака (може да се повтори)]:tag:' \
            '--runs[Препокриј го бројот на извршувања по случај (стандардно: case.runs, инаку 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Изврши до n извршувања на агент истовремено (1-8; стандардно 1)]:n:' \
            '--model[Препокриј го моделот за сите случаи]:model:_claude_model_names' \
            '--judge-model[Препокриј го моделот за LLM оценување (стандардно: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Строга горна граница на трошоци; прекини и извести за делумните резултати ако се достигне (излезен код 2)]:usd:' \
            '--output-dir[Директориум за aggregate-result.json]:dir:_directories' \
            '--eval-dir[Име на директориумот (под приклучокот) што ги содржи eval случаите]:dir:' \
            '--json[Испечати го целиот резултат од извршувањето како JSON на stdout, или запиши го во оваа .json датотека]::path:_files' \
            '--threshold[Излези со излезен код 1 ако резултатот на кој било случај е под овој праг (стандардно: 1.0)]:threshold:' \
            '*--allow-tools[Дозвола од операторот за ограничени алатки (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Изврши го scaffold_script на секој случај (извршува bash обезбеден од авторот во твое име; стандардно исклучено)]' \
            '(--scaffold)--no-scaffold[Експлицитно прескокни го scaffold_script]' \
            '--trust-plugin[Потврди дека му веруваш на овој приклучок и на неговиот eval пакет, прескокнувајќи го барањето за доверба при првото извршување (за CI)]' \
            '--ablation[Изврши контролна група без приклучок и извести за разликата во резултатот]:mode:(none with-without)' \
            '--mocks[Лажни замени за MCP сервери, од <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Со --mocks record: стартувај ги и вистинските процеси на MCP сервери што немаат лажна замена]' \
            '--keep-temp[Зачувај ги директориумите на скицата за отстранување грешки]' \
            '--verbose[Запиши настани за следење по порака во дневникот за отстранување грешки]' \
            '--report[Запиши го самостојниот HTML извештај во оваа патека наместо во директориумот со резултати]:path:_files' \
            '(--no-publish)--publish-report[Барај и објавување на извештајот на claude.ai]' \
            '(--publish-report)--no-publish[Задржи го HTML извештајот само локално; прескокни го објавувањето на claude.ai]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Испрати го (push) тагот на --remote откако ќе се креира]' \
            '--dry-run[Испечати што би се означило со таг без да се креира]' \
            '(-f --force)'{-f,--force}'[Прескокни ги проверките за неисчистено работно дрво и за веќе постоечки таг]' \
            '(-m --message)'{-m,--message}'[Порака за анотација на тагот (користи %s за верзијата)]:msg:' \
            '--remote[Remote на кој се испраќа (push) со --push]:name:' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '::dir:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Додај пазар од URL, патека или GitHub репозиториум'
    'list:Прикажи список на конфигурирани пазари'
    'remove:Отстрани конфигуриран пазар'
    'rm:Отстрани конфигуриран пазар (алијас за remove)'
    'update:Ажурирај пазар од извор - ажурирај ги сите ако името не е наведено'
    'help:Прикажи помош'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Прикажи помош]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'команди на marketplace' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '--sparse[Ограничи го checkout на одредени директориуми преку git sparse-checkout (за монорепозиториуми)]:paths:' \
            '--scope[Каде да се декларира пазарот]:scope:(user project local)' \
            '--claudeai[Додај го пазарот со ова име што claude.ai го хостира за тебе]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Излез како JSON]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Отстрани ја декларацијата на пазарот од одреден опсег на поставки (изостави за да се отстрани од секој опсег)]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}

_claude_install() {
  _arguments \
    '--force[Принудителна инсталација дури и ако е веќе инсталирано]' \
    '(-h --help)'{-h,--help}'[Прикажи помош]' \
    '::target:(stable latest)'
}

_claude_agents() {
  _arguments \
    '*--add-dir[Дополнителен директориум за обезбедување пристап на алатки во испратени сесии]:directory:_directories' \
    '--agent[Стандарден агент за сесии испратени од приказот на агенти]:agent:_claude_agent_names' \
    '--all[Со --json: вклучи ги и завршените позадински сесии]' \
    '--allow-dangerously-skip-permissions[Направи го режимот за заобиколување дозволи достапен за испратени сесии]' \
    '--cwd[Прикажи само позадински сесии стартувани под патека]:path:_directories' \
    '--dangerously-skip-permissions[Алијас за --permission-mode bypassPermissions]' \
    '--effort[Стандардно ниво на напор за испратени сесии]:level:(low medium high xhigh max)' \
    '--json[Испечати ги активните сесии како JSON низа и излез]' \
    '*--mcp-config[Конфигурација на MCP сервер за примена на испратени сесии]:config:' \
    '--model[Стандарден модел за сесии испратени од приказот на агенти]:model:_claude_model_names' \
    '--permission-mode[Стандарден режим на дозволи за испратени сесии]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Вчитај приклучоци од директориум за приказот на агенти и испратени сесии]:path:_directories' \
    '--setting-sources[Список на извори на поставки одделени со запирка за вчитување (user, project, local)]:sources:' \
    '--settings[Датотека со поставки или JSON стринг за примена]:file-or-json:_files' \
    '--strict-mcp-config[Користи само MCP сервери од --mcp-config во испратени сесии]' \
    '--restricted[Стартувај ги испратените сесии во ограничен режим]' \
    '(-h --help)'{-h,--help}'[Прикажи помош за команда]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Најави се на твојата Anthropic сметка'
    'logout:Одјави се од твојата Anthropic сметка'
    'status:Прикажи статус на автентикација'
    'help:Прикажи помош'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Прикажи помош за команда]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'команди на auth' auth_commands
      ;;
    args)
      case $words[1] in
        login)
          _arguments \
            '--email[Однапред пополни ја е-поштенската адреса на страницата за најава]:email:' \
            '--sso[Принуди SSO тек на најава]' \
            '(--claudeai)--console[Користи Anthropic Console (наплата според употреба на API) наместо Claude претплата]' \
            '(--console)--claudeai[Користи Claude претплата (стандардно)]' \
            '(-h --help)'{-h,--help}'[Прикажи помош за команда]'
          ;;
        status)
          _arguments \
            '(--text)--json[Излез како JSON (стандардно)]' \
            '(--json)--text[Излез како текст читлив за луѓе]' \
            '(-h --help)'{-h,--help}'[Прикажи помош за команда]'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош за команда]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Испечати ја ефективната конфигурација за автоматски режим како JSON'
    'critique:Добиј повратна информација од AI за твоите приспособени правила за автоматски режим'
    'defaults:Испечати ги стандардните правила за автоматски режим како JSON'
    'reset:Ресетирај ја конфигурацијата за автоматски режим на испорачаните стандардни вредности'
    'help:Прикажи помош'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Прикажи помош за команда]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'команди на auto-mode' auto_mode_commands
      ;;
    args)
      case $words[1] in
        critique)
          _arguments \
            '--model[Препокриј кој модел се користи]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Прикажи помош за команда]'
          ;;
        defaults)
          _arguments \
            '--label[Прикажи само правила чија ознака започнува со овој префикс (без разлика на големи и мали букви)]:prefix:' \
            '(-h --help)'{-h,--help}'[Прикажи помош за команда]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Прескокни го барањето за потврда]' \
            '(-h --help)'{-h,--help}'[Прикажи помош за команда]'
          ;;
        config)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош за команда]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Патека до YAML конфигурација на gateway]:path:_files' \
    '(-h --help)'{-h,--help}'[Прикажи помош за команда]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Избриши ја целата состојба на Claude Code за проект (транскрипти, задачи, историја на датотеки, конфигурациски запис)'
    'help:Прикажи помош'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Прикажи помош за команда]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'команди на project' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '--dry-run[Прикажи список на она што би се избришало без да се брише ништо]' \
            '(-y --yes)'{-y,--yes}'[Прескокни го барањето за потврда]' \
            '(-i --interactive)'{-i,--interactive}'[Побарај потврда за секоја ставка пред бришење]' \
            '(1)--all[Избриши ја состојбата за секој проект (меѓусебно исклучиво со патека)]' \
            '(-h --help)'{-h,--help}'[Прикажи помош за команда]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Испечати го суровиот bugs.json товар наместо форматирани наоди]' \
    '--timeout[Максимални минути за чекање прегледот да заврши (стандардно: 45)]:minutes:' \
    '(--no-post)--post[Објави ги наодите од завршениот преглед на PR во твое име (само за PR цели; еден обичен коментар, не преглед)]' \
    '(--post)--no-post[Не ги објавувај наодите на PR (стандардно)]' \
    '(-h --help)'{-h,--help}'[Прикажи помош за команда]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Рестартирај ја секоја активна позадинска сесија]' \
    '(-h --help)'{-h,--help}'[Прикажи помош за команда]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Отфрли ги и неиспратените (unpushed) commit-и и некомитираните промени на worktree (проследи го commit@worktree-id што го пријавил претходен claude rm)]:commit@worktree-id:' \
    '--force-remove-worktree[Избриши го директориумот на worktree иако hook-от WorktreeRemove или git не можеле да го отстранат (проследи го worktree-id што го пријавил претходен claude rm)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Прикажи помош за команда]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Прикажи што би се увезло без да се запишува ништо]' \
    '--yes[Прескокни го интерактивниот избирач (на headless површини, проследи --yes=<digest> од прегледот на /import)]' \
    '(-h --help)'{-h,--help}'[Прикажи помош за команда]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
