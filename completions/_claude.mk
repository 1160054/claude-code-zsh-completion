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
    'mcp:Конфигурирање и управување со MCP сервери'
    'plugin:Управување со приклучоци на Claude Code'
    'agents:Управување со позадински агенти'
    'auth:Управување со автентикација'
    'auto-mode:Прегледај или ресетирај ја конфигурацијата на класификаторот за автоматски режим'
    'gateway:Стартувај го gateway за автентикација/телеметрија за претпријатија'
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
    '--max-budget-usd[Максимален износ во долари за трошење на API повици (само --print)]:amount:'
    '--replay-user-messages[Повторно испрати кориснички пораки од stdin на stdout за потврда]'
    '--allowed-tools[Список на дозволени имиња на алатки одделени со запирка или празно место (на пр. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Список на дозволени имиња на алатки одделени со запирка или празно место (формат camelCase)]:tools:'
    '--tools[Наведи список на достапни алатки од вградениот сет. Само во режим print]:tools:'
    '--disallowed-tools[Список на забранети имиња на алатки одделени со запирка или празно место (на пр. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Список на забранети имиња на алатки одделени со запирка или празно место (формат camelCase)]:tools:'
    '--mcp-config[Вчитај MCP сервери од JSON датотека или стринг (одделени со празни места)]:configs:'
    '--system-prompt[Системски prompt за употреба во сесијата]:prompt:'
    '--append-system-prompt[Додај системски prompt на стандардниот системски prompt]:prompt:'
    '--permission-mode[Режим на дозволи за употреба во сесијата]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Продолжи со последниот разговор]'
    '(-r --resume)'{-r,--resume}'[Продолжи разговор - наведете идентификатор на сесија или изберете интерактивно]:sessionId:_claude_sessions'
    '--fork-session[Креирај нов идентификатор на сесија наместо повторна употреба на оригиналниот при продолжување (со --resume или --continue)]'
    '--no-session-persistence[Оневозможи зачувување на сесија - сесиите нема да бидат зачувани (само --print)]'
    '--model[Модел за тековната сесија. Наведете алијас за најновиот модел (на пр. '\''sonnet'\'' или '\''opus'\'')]:model:'
    '--agent[Агент за тековната сесија. Ја препокрива поставката '\''agent'\'']:agent:'
    '--betas[Beta заглавија за вклучување во API барања (само корисници со API клуч)]:betas:'
    '--fallback-model[Овозможи автоматско префрлање на наведениот модел кога стандардниот модел е преоптоварен (само --print)]:model:'
    '--settings[Патека до JSON датотека со поставки или JSON стринг за вчитување на дополнителни поставки]:file-or-json:_files'
    '--add-dir[Дополнителни директориуми за обезбедување пристап на алатки]:directories:_directories'
    '--ide[Автоматски поврзи се со IDE при стартување ако е достапен точно еден валиден IDE]'
    '--strict-mcp-config[Користи само MCP сервери од --mcp-config и игнорирај ги сите други MCP поставки]'
    '--session-id[Одреден идентификатор на сесија за употреба во разговор (мора да биде валиден UUID)]:uuid:'
    '--agents[JSON објект кој дефинира приспособени агенти]:json:'
    '--setting-sources[Список на извори на поставки одделени со запирка за вчитување (user, project, local)]:sources:'
    '--plugin-dir[Директориум за вчитување на приклучоци само за оваа сесија (може да се повтори)]:paths:_directories'
    '--disable-slash-commands[Оневозможи ги сите slash команди]'
    '(--bg --background)'{--bg,--background}'[Стартувај ја сесијата како позадински агент и врати се веднаш]'
    '(-w --worktree)'{-w,--worktree}'[Креирај нов git worktree за оваа сесија (опционално наведете име)]::name:'
    '--tmux[Креирај tmux сесија за worktree (потребно е --worktree)]'
    '(-n --name)'{-n,--name}'[Постави прикажано име за оваа сесија]:name:'
    '--effort[Ниво на напор за тековната сесија]:level:(low medium high xhigh max)'
    '--debug-file[Запиши дневници за отстранување грешки во одредена патека на датотека (имплицитно го овозможува режимот на отстранување грешки)]:path:_files'
    '--from-pr[Продолжи сесија поврзана со PR по број/URL, или отвори интерактивен избирач]::value:'
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
        login|logout)
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
    'install:Инсталирај приклучок од достапни пазари'
    'i:Инсталирај приклучок од достапни пазари (кратенка за install)'
    'init:Скицирај нов приклучок (автоматски се вчитува во следната сесија)'
    'uninstall:Деинсталирај инсталиран приклучок'
    'remove:Деинсталирај инсталиран приклучок (алијас за uninstall)'
    'enable:Овозможи оневозможен приклучок'
    'disable:Оневозможи овозможен приклучок'
    'update:Ажурирај приклучок на најновата верзија'
    'eval:Стартувај eval случаи против приклучок и извести за бодуваните резултати'
    'prune:Отстрани автоматски инсталирани зависности што повеќе не се потребни'
    'tag:Креирај git таг {name}--v{version} за издание на приклучок'
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
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на инсталација]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на инсталација]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на инсталација]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на инсталација]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:path:_files'
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
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]'
          ;;
        remove|rm)
          _arguments \
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
    '--agent[Стандарден агент за сесии испратени од приказот на агенти]:agent:' \
    '--all[Со --json: вклучи ги и завршените позадински сесии]' \
    '--allow-dangerously-skip-permissions[Направи го режимот за заобиколување дозволи достапен за испратени сесии]' \
    '--cwd[Прикажи само позадински сесии стартувани под патека]:path:_directories' \
    '--dangerously-skip-permissions[Алијас за --permission-mode bypassPermissions]' \
    '--effort[Стандардно ниво на напор за испратени сесии]:level:(low medium high xhigh max)' \
    '--json[Испечати ги активните сесии како JSON низа и излез]' \
    '*--mcp-config[Конфигурација на MCP сервер за примена на испратени сесии]:config:' \
    '--model[Стандарден модел за сесии испратени од приказот на агенти]:model:' \
    '--permission-mode[Стандарден режим на дозволи за испратени сесии]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Вчитај приклучоци од директориум за приказот на агенти и испратени сесии]:path:_directories' \
    '--setting-sources[Список на извори на поставки одделени со запирка за вчитување (user, project, local)]:sources:' \
    '--settings[Датотека со поставки или JSON стринг за примена]:file-or-json:_files' \
    '--strict-mcp-config[Користи само MCP сервери од --mcp-config во испратени сесии]' \
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
        login|logout|status)
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
        config|critique|defaults|reset)
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
            '(-h --help)'{-h,--help}'[Прикажи помош за команда]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Испечати го суровиот bugs.json товар наместо форматирани наоди]' \
    '--timeout[Максимални минути за чекање прегледот да заврши]:minutes:' \
    '(-h --help)'{-h,--help}'[Прикажи помош за команда]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
