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

        # Describe each session with the first thing you typed in it. Only the
        # head of the transcript is read - these files grow into the megabytes.
        summary=$(head -c 200000 "$session_file" 2>/dev/null | \
          grep -m 1 -o '"role":"user","content":"[^"]\{1,60\}' 2>/dev/null | \
          sed 's/.*"content":"//; s/\\n/ /g; s/\\*$//')
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
    'mcp:Configurar y gestionar servidores MCP'
    'plugin:Gestionar plugins de Claude Code'
    'agents:Gestionar agentes en segundo plano'
    'attach:Abrir una sesión en segundo plano en esta terminal'
    'logs:Mostrar la salida reciente de terminal de una sesión en segundo plano'
    'stop:Detener una sesión en segundo plano (su conversación se conserva)'
    'respawn:Reiniciar una sesión en segundo plano para que use la versión actual de Claude Code'
    'rm:Eliminar una sesión en segundo plano, y su worktree cuando sea seguro'
    'auth:Gestionar autenticación'
    'auto-mode:Inspeccionar o restablecer la configuración del clasificador del modo automático'
    'gateway:Ejecutar la puerta de enlace empresarial de autenticación/telemetría'
    'import:Importar la configuración de otro agente de programación con IA a Claude Code'
    'project:Gestionar el estado del proyecto de Claude Code'
    'ultrareview:Ejecutar una revisión de código multiagente alojada en la nube e imprimir los hallazgos'
    'setup-token:Configurar token de autenticación a largo plazo (requiere suscripción a Claude)'
    'doctor:Verificación de salud del actualizador automático de Claude Code'
    'update:Buscar e instalar actualizaciones'
    'install:Instalar compilación nativa de Claude Code'
  )

  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Habilitar modo de depuración con filtrado opcional de categorías (ej., "api,hooks" o "!statsig,!file")]:filter:'
    '--verbose[Anular configuración de modo detallado del archivo de configuración]'
    '(-p --print)'{-p,--print}'[Imprimir respuesta y salir (para usar con pipes). Nota: usar solo en directorios confiables]'
    '--output-format[Formato de salida (con --print): "text" (predeterminado), "json" (resultado único) o "stream-json" (transmisión en tiempo real)]:format:(text json stream-json)'
    '--json-schema[Esquema JSON para validación de salida estructurada]:schema:'
    '--include-partial-messages[Incluir fragmentos de mensajes parciales a medida que llegan (con --print y --output-format=stream-json)]'
    '--input-format[Formato de entrada (con --print): "text" (predeterminado) o "stream-json" (entrada de transmisión en tiempo real)]:format:(text stream-json)'
    '--mcp-debug[\[Obsoleto. Usar --debug en su lugar\] Habilitar modo de depuración MCP (muestra errores del servidor MCP)]'
    '--dangerously-skip-permissions[Omitir todas las verificaciones de permisos. Recomendado solo para sandboxes sin acceso a Internet]'
    '--allow-dangerously-skip-permissions[Habilitar opción para omitir verificaciones de permisos sin habilitarla por defecto]'
    '--restricted[Modo restringido: quita las herramientas que ejecutan comandos o código y WebFetch, ignora la configuración user/project/local y limita las herramientas de archivos a los directorios de trabajo]'
    '--max-budget-usd[Cantidad máxima en dólares a gastar en llamadas a la API (solo --print)]:amount:'
    '--replay-user-messages[Reenviar mensajes de usuario desde stdin en stdout para confirmación]'
    '--allowed-tools[Lista separada por comas o espacios de nombres de herramientas permitidas (ej., "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Lista separada por comas o espacios de nombres de herramientas permitidas (formato camelCase)]:tools:'
    '--tools[Especificar lista de herramientas disponibles del conjunto incorporado. Solo modo de impresión]:tools:'
    '--disallowed-tools[Lista separada por comas o espacios de nombres de herramientas no permitidas (ej., "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Lista separada por comas o espacios de nombres de herramientas no permitidas (formato camelCase)]:tools:'
    '--mcp-config[Cargar servidores MCP desde archivo JSON o cadena (separados por espacios)]:configs:'
    '--system-prompt[Prompt del sistema a usar para la sesión]:prompt:'
    '--system-prompt-file[Leer el prompt del sistema desde un archivo]:file:_files'
    '--append-system-prompt[Agregar prompt del sistema al prompt del sistema predeterminado]:prompt:'
    '--append-system-prompt-file[Leer el prompt del sistema desde un archivo y añadirlo al prompt del sistema predeterminado]:file:_files'
    '--system-prompt-snapshot[Registrar el prompt del sistema una vez por conversación y reutilizarlo tal cual en cada solicitud y reanudación (on, predeterminado) o generarlo de nuevo en cada solicitud (off)]:mode:(on off)'
    '--permission-mode[Modo de permisos a usar para la sesión]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Quién responde las solicitudes de permiso con --print: "host" (el host del SDK o --permission-prompt-tool) o "none" (todo lo que pediría permiso se deniega)]:target:(host none)'
    '--permission-prompt-tool[Herramienta MCP para las solicitudes de permiso (solo --print)]:tool:'
    '(-c --continue)'{-c,--continue}'[Continuar la conversación más reciente]'
    '(-r --resume)'{-r,--resume}'[Reanudar una conversación - especificar ID de sesión o seleccionar interactivamente]:sessionId:_claude_sessions'
    '--fork-session[Crear nuevo ID de sesión en lugar de reutilizar el ID de sesión original al reanudar (con --resume o --continue)]'
    '--no-session-persistence[Deshabilitar la persistencia de sesión - las sesiones no se guardarán (solo --print)]'
    '--model[Modelo para la sesión actual. Especificar alias del modelo más reciente (ej., '\''sonnet'\'' o '\''opus'\'')]:model:_claude_model_names'
    '--agent[Agente para la sesión actual. Anula la configuración '\''agent'\'']:agent:_claude_agent_names'
    '--betas[Encabezados beta a incluir en las solicitudes de la API (solo usuarios con clave de API)]:betas:'
    '--fallback-model[Habilitar respaldo automático al modelo especificado cuando el modelo predeterminado está sobrecargado (solo --print)]:model:_claude_model_names'
    '--settings[Ruta al archivo JSON de configuración o cadena JSON para cargar configuración adicional]:file-or-json:_files'
    '--add-dir[Directorios adicionales para permitir acceso de herramientas]:directories:_directories'
    '--ide[Conectar automáticamente al IDE al inicio si hay exactamente un IDE válido disponible]'
    '--strict-mcp-config[Usar solo servidores MCP de --mcp-config e ignorar todas las demás configuraciones MCP]'
    '--session-id[ID de sesión específico para usar en la conversación (debe ser UUID válido)]:uuid:'
    '--agents[Objeto JSON que define agentes personalizados]:json:'
    '--setting-sources[Lista separada por comas de fuentes de configuración a cargar (user, project, local)]:sources:'
    '--plugin-dir[Directorio desde el cual cargar plugins solo para esta sesión (repetible)]:paths:_directories'
    '--disable-slash-commands[Deshabilitar todos los comandos de barra]'
    '(--bg --background)'{--bg,--background}'[Iniciar la sesión como agente en segundo plano y regresar de inmediato]'
    '(-w --worktree)'{-w,--worktree}'[Crear un nuevo worktree de git para esta sesión (opcionalmente especificar un nombre)]::name:'
    '--tmux=-[Crear una sesión de tmux para el worktree (requiere --worktree). Usa paneles nativos de iTerm2 cuando están disponibles; --tmux=classic para tmux tradicional]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Establecer un nombre para mostrar de esta sesión]:name:'
    '--effort[Nivel de esfuerzo para la sesión actual]:level:(low medium high xhigh max)'
    '--autocompact[Tamaño de la ventana de compactación automática (auto, o de 100k a 1M de tokens)]:size:(auto)'
    '--debug-file[Escribir registros de depuración en una ruta de archivo específica (habilita implícitamente el modo de depuración)]:path:_files'
    '--from-pr[Reanudar una sesión vinculada a un PR por número/URL, o abrir el selector interactivo]::value:'
    '--teleport[Reanudar una sesión de teleport, opcionalmente especificar el ID de sesión]::session:'
    '--cloud[Crear una sesión en la nube con la descripción dada, o conectarse a una existente por ID de sesión o URL de claude.ai/code]::description-or-session:'
    '--environment[Crear una nueva sesión en la nube que se ejecute en el entorno autoalojado indicado (ccpool_...)]:environment_id:'
    '--remote-control[Iniciar una sesión interactiva con Control Remoto habilitado (opcionalmente con nombre)]::name:'
    '--remote-control-session-name-prefix[Prefijo para los nombres de sesión de Control Remoto generados automáticamente]:prefix:'
    '--chrome[Habilitar la integración de Claude en Chrome]'
    '--no-chrome[Deshabilitar la integración de Claude en Chrome]'
    '--plugin-url[Descargar un .zip de plugin desde una URL solo para esta sesión (repetible)]:url:'
    '--file[Recursos de archivo a descargar al inicio (formato: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Habilitar sugerencias de prompt (emite un prompt siguiente previsto en modo print/SDK)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Reenviar texto y bloques de pensamiento del subagente como mensajes (con --print y stream-json)]'
    '--include-hook-events[Incluir todos los eventos del ciclo de vida de hooks en el flujo de salida (con stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Mover las secciones por máquina al primer mensaje de usuario para mejorar la reutilización de la caché de prompts]'
    '--brief[Habilitar la herramienta SendUserMessage para comunicación de agente a usuario]'
    '--safe-mode[Iniciar con todas las personalizaciones deshabilitadas (útil para solucionar una configuración dañada)]'
    '--bare[Modo mínimo: omitir hooks, LSP, sincronización de plugins, atribución, auto-memoria y detección automática de CLAUDE.md]'
    '--ax-screen-reader[Renderizar salida compatible con lectores de pantalla (texto plano, sin bordes decorativos ni animaciones)]'
    '(-v --version)'{-v,--version}'[Mostrar número de versión]'
    '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]'
  )

  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'comandos de claude' main_commands
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
            '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]' \
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
          _message "sin argumentos"
          ;;
      esac
      ;;
  esac
}

_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Iniciar un servidor MCP de Claude Code'
    'add:Agregar un servidor MCP a Claude Code'
    'remove:Eliminar un servidor MCP'
    'list:Listar servidores MCP configurados'
    'get:Obtener detalles del servidor MCP'
    'add-json:Agregar un servidor MCP (stdio o SSE) con cadena JSON'
    'add-from-claude-desktop:Importar servidores MCP desde Claude Desktop (solo Mac y WSL)'
    'reset-project-choices:Restablecer todos los servidores de ámbito de proyecto (.mcp.json) aprobados/rechazados en este proyecto'
    'login:Autenticar con un servidor MCP (HTTP, SSE o conector de claude.ai)'
    'logout:Borrar las credenciales OAuth almacenadas de un servidor MCP'
    'help:Mostrar ayuda'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'comandos de mcp' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Habilitar modo de depuración]' \
            '--verbose[Anular configuración de modo detallado del archivo de configuración]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ámbito de configuración (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Tipo de transporte (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Establecer variable de entorno (ej., -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Establecer encabezado WebSocket]:header:' \
            '--client-id[ID de cliente OAuth para servidores HTTP/SSE]:clientId:' \
            '--client-secret[Pedir el secreto de cliente OAuth (o definir la variable de entorno MCP_CLIENT_SECRET)]' \
            '--callback-port[Puerto fijo para el callback de OAuth (para servidores que requieren URIs de redirección preregistradas)]:port:' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ámbito de configuración (local, user, project) - eliminar del ámbito existente si no se especifica]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ámbito de configuración (local, user, project)]:scope:(local user project)' \
            '--client-secret[Pedir el secreto de cliente OAuth (o definir la variable de entorno MCP_CLIENT_SECRET)]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ámbito de configuración (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]'
          ;;
        login)
          _arguments \
            '--no-browser[Mostrar la URL de autorización en lugar de abrir un navegador (para sesiones SSH/sin interfaz)]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:name:_claude_mcp_servers'
          ;;
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Validar un plugin o manifiesto de marketplace'
    'marketplace:Gestionar marketplaces de Claude Code'
    'list:Listar plugins instalados'
    'details:Mostrar el inventario de componentes y el costo de tokens proyectado de un plugin'
    'install:Instalar un plugin desde marketplaces disponibles'
    'i:Instalar un plugin desde marketplaces disponibles (abreviatura de install)'
    'init:Generar un nuevo plugin (se carga automáticamente en la siguiente sesión)'
    'new:Generar la estructura de un nuevo plugin (alias de init)'
    'uninstall:Desinstalar un plugin instalado'
    'remove:Desinstalar un plugin instalado (alias de uninstall)'
    'enable:Habilitar un plugin deshabilitado'
    'disable:Deshabilitar un plugin habilitado'
    'update:Actualizar un plugin a la última versión'
    'eval:Ejecutar casos de evaluación contra un plugin e informar los resultados puntuados'
    'prune:Eliminar dependencias instaladas automáticamente que ya no se necesitan'
    'autoremove:Eliminar dependencias instaladas automáticamente que ya no se necesitan (alias de prune)'
    'tag:Crear una etiqueta de git {name}--v{version} para una versión del plugin'
    'help:Mostrar ayuda'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'comandos de plugin' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '--strict[Tratar las advertencias como errores (salida 1)]' \
            '--json[Mostrar el informe de validación como JSON (mismos códigos de salida)]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ámbito de instalación]:scope:(user project local)' \
            '*--config[Definir una opción userConfig declarada en el manifiesto del plugin (repetible)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[Aceptar el comando declarado por el marketplace que se muestra sin pedir confirmación]' \
            '--json[Mostrar una línea de resultado legible por máquina en lugar del mensaje para humanos]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ámbito de instalación]:scope:(user project local)' \
            '--keep-data[Conservar el directorio de datos persistentes del plugin]' \
            '--prune[Eliminar también las dependencias instaladas automáticamente que ya no se necesitan]' \
            '(-y --yes)'{-y,--yes}'[Omitir la confirmación de --prune]' \
            '--json[Mostrar una línea de resultado legible por máquina en lugar del mensaje para humanos (no con --prune)]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ámbito de instalación]:scope:(user project local)' \
            '--json[Mostrar una línea de resultado legible por máquina en lugar del mensaje para humanos]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Desactivar todos los plugins activados]' \
            '(-s --scope)'{-s,--scope}'[Ámbito de instalación]:scope:(user project local)' \
            '--json[Mostrar una línea de resultado legible por máquina en lugar del mensaje para humanos]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ámbito de instalación]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Aceptar el comando declarado por el marketplace que se muestra sin pedir confirmación]' \
            '--json[Mostrar una línea de resultado legible por máquina en lugar del mensaje para humanos]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Salida en JSON]' \
            '--available[Incluir los plugins disponibles en los marketplaces (requiere --json)]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ámbito en el que limpiar]:scope:(user project local)' \
            '--dry-run[Listar lo que se eliminaría sin eliminar nada]' \
            '(-y --yes)'{-y,--yes}'[Omitir la pregunta de confirmación]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Descripción del manifiesto]:text:' \
            '--author[Nombre del autor (predeterminado: git config user.name)]:name:' \
            '--author-email[Correo del autor (predeterminado: git config user.email)]:email:' \
            '--with[Componentes que también se generarán]:components:' \
            '(-f --force)'{-f,--force}'[Sobrescribir un .claude-plugin/ existente en el destino]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Filtrar casos por glob de nombre]:glob:' \
            '*--tag[Filtrar casos por etiqueta (repetible)]:tag:' \
            '--runs[Sobrescribir las ejecuciones por caso (predeterminado: case.runs, si no 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Ejecutar hasta n agentes a la vez (1-8; predeterminado 1)]:n:' \
            '--model[Sobrescribir el modelo para todos los casos]:model:_claude_model_names' \
            '--judge-model[Sobrescribir el modelo evaluador LLM (predeterminado: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Límite máximo de coste; abortar e informar resultados parciales si se alcanza (salida 2)]:usd:' \
            '--output-dir[Directorio para aggregate-result.json]:dir:_directories' \
            '--eval-dir[Nombre del directorio (dentro del plugin) que contiene los casos de evaluación]:dir:' \
            '--json[Mostrar el resultado completo de la ejecución como JSON en stdout, o escribirlo en este archivo .json]::path:_files' \
            '--threshold[Salir con 1 si la puntuación de algún caso está por debajo de este umbral (predeterminado: 1.0)]:threshold:' \
            '*--allow-tools[Autorización del operador para herramientas restringidas (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Ejecutar el scaffold_script de cada caso (ejecuta bash del autor con tu usuario; desactivado por defecto)]' \
            '(--scaffold)--no-scaffold[Omitir explícitamente scaffold_script]' \
            '--trust-plugin[Declarar que confías en este plugin y su suite de evaluación, omitiendo la pregunta de confianza de la primera ejecución (para CI)]' \
            '--ablation[Ejecutar también una línea base sin plugin e informar la diferencia de puntuación]:mode:(none with-without)' \
            '--mocks[Sustitutos simulados de los servidores MCP, desde <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Con --mocks record: iniciar también los procesos reales de los servidores MCP que no tienen simulación]' \
            '--keep-temp[Conservar los directorios de scaffold para depuración]' \
            '--verbose[Registrar eventos de traza por mensaje en el registro de depuración]' \
            '--report[Escribir el informe HTML autocontenido en esta ruta en lugar del directorio de resultados]:path:_files' \
            '(--no-publish)--publish-report[Exigir también la publicación del informe en claude.ai]' \
            '(--publish-report)--no-publish[Mantener el informe HTML solo en local; no publicarlo en claude.ai]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Enviar la etiqueta a --remote tras crearla]' \
            '--dry-run[Mostrar lo que se etiquetaría sin crear la etiqueta]' \
            '(-f --force)'{-f,--force}'[Omitir las comprobaciones de árbol de trabajo sucio y de etiqueta ya existente]' \
            '(-m --message)'{-m,--message}'[Mensaje de anotación de la etiqueta (usar %s para la versión)]:msg:' \
            '--remote[Remoto al que enviar con --push]:name:' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '::path:_files'
          ;;
      esac
      ;;
  esac
}

_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Agregar un marketplace desde URL, ruta o repositorio de GitHub'
    'list:Listar marketplaces configurados'
    'remove:Eliminar un marketplace configurado'
    'rm:Eliminar un marketplace configurado (alias de remove)'
    'update:Actualizar marketplace desde la fuente - actualizar todos si no se especifica nombre'
    'help:Mostrar ayuda'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'comandos de marketplace' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '--sparse[Limitar el checkout a directorios concretos mediante git sparse-checkout (para monorepos)]:paths:' \
            '--scope[Dónde declarar el marketplace]:scope:(user project local)' \
            '--claudeai[Añadir el marketplace con este nombre que claude.ai aloja para ti]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Salida en JSON]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Eliminar la declaración del marketplace de un ámbito de configuración concreto (omitir para eliminarla de todos)]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}

_claude_install() {
  _arguments \
    '--force[Forzar instalación incluso si ya está instalado]' \
    '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
    '::target:(stable latest)'
}

_claude_agents() {
  _arguments \
    '*--add-dir[Directorio adicional para permitir acceso de herramientas en sesiones despachadas]:directory:_directories' \
    '--agent[Agente predeterminado para sesiones despachadas desde la vista de agentes]:agent:_claude_agent_names' \
    '--all[Con --json: incluir también sesiones en segundo plano completadas]' \
    '--allow-dangerously-skip-permissions[Hacer disponible el modo de omisión de permisos para sesiones despachadas]' \
    '--cwd[Mostrar solo sesiones en segundo plano iniciadas bajo la ruta]:path:_directories' \
    '--dangerously-skip-permissions[Alias de --permission-mode bypassPermissions]' \
    '--effort[Nivel de esfuerzo predeterminado para sesiones despachadas]:level:(low medium high xhigh max)' \
    '--json[Imprimir sesiones activas como un array JSON y salir]' \
    '*--mcp-config[Configuración de servidor MCP a aplicar a las sesiones despachadas]:config:' \
    '--model[Modelo predeterminado para sesiones despachadas desde la vista de agentes]:model:_claude_model_names' \
    '--permission-mode[Modo de permisos predeterminado para sesiones despachadas]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Cargar plugins desde el directorio para la vista de agentes y las sesiones despachadas]:path:_directories' \
    '--setting-sources[Lista separada por comas de fuentes de configuración a cargar (user, project, local)]:sources:' \
    '--settings[Archivo de configuración o cadena JSON a aplicar]:file-or-json:_files' \
    '--strict-mcp-config[Usar solo servidores MCP de --mcp-config en las sesiones despachadas]' \
    '--restricted[Iniciar las sesiones despachadas en modo restringido]' \
    '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Iniciar sesión en tu cuenta de Anthropic'
    'logout:Cerrar sesión de tu cuenta de Anthropic'
    'status:Mostrar el estado de autenticación'
    'help:Mostrar ayuda'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'comandos de auth' auth_commands
      ;;
    args)
      case $words[1] in
        login)
          _arguments \
            '--email[Rellenar previamente el correo en la página de inicio de sesión]:email:' \
            '--sso[Forzar el flujo de inicio de sesión SSO]' \
            '(--claudeai)--console[Usar Anthropic Console (facturación por uso de API) en lugar de la suscripción a Claude]' \
            '(--console)--claudeai[Usar la suscripción a Claude (predeterminado)]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]'
          ;;
        status)
          _arguments \
            '(--text)--json[Salida en JSON (predeterminado)]' \
            '(--json)--text[Salida como texto legible]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Imprimir la configuración efectiva del modo automático como JSON'
    'critique:Obtener retroalimentación de IA sobre tus reglas personalizadas del modo automático'
    'defaults:Imprimir las reglas predeterminadas del modo automático como JSON'
    'reset:Restablecer la configuración del modo automático a los valores predeterminados de fábrica'
    'help:Mostrar ayuda'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'comandos de auto-mode' auto_mode_commands
      ;;
    args)
      case $words[1] in
        critique)
          _arguments \
            '--model[Sobrescribir el modelo que se usa]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]'
          ;;
        defaults)
          _arguments \
            '--label[Mostrar solo las reglas cuya etiqueta empiece por este prefijo (sin distinguir mayúsculas)]:prefix:' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Omitir la pregunta de confirmación]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]'
          ;;
        config)
          _arguments \
            '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Ruta al archivo de configuración YAML de la puerta de enlace]:path:_files' \
    '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Eliminar todo el estado de Claude Code de un proyecto (transcripciones, tareas, historial de archivos, entrada de configuración)'
    'help:Mostrar ayuda'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'comandos de project' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '--dry-run[Listar lo que se eliminaría sin eliminar nada]' \
            '(-y --yes)'{-y,--yes}'[Omitir la pregunta de confirmación]' \
            '(-i --interactive)'{-i,--interactive}'[Preguntar por cada elemento antes de eliminar]' \
            '(1)--all[Purgar el estado de todos los proyectos (incompatible con una ruta)]' \
            '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Imprimir el payload bruto de bugs.json en lugar de los hallazgos formateados]' \
    '--timeout[Minutos máximos a esperar a que finalice la revisión (predeterminado: 45)]:minutes:' \
    '(--no-post)--post[Publicar los hallazgos de la revisión terminada en el PR como tú (solo destinos PR; un comentario normal, no una review)]' \
    '(--post)--no-post[No publicar los hallazgos en el PR (predeterminado)]' \
    '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Reiniciar todas las sesiones en segundo plano en ejecución]' \
    '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Descartar también los commits sin enviar y los cambios sin confirmar del worktree (pasar el commit@worktree-id que informó un claude rm anterior)]:commit@worktree-id:' \
    '--force-remove-worktree[Eliminar el directorio del worktree aunque el hook WorktreeRemove o git no pudieran quitarlo (pasar el worktree-id que informó un claude rm anterior)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Mostrar lo que se importaría sin escribir nada]' \
    '--yes[Omitir el selector interactivo (en entornos sin interfaz, pasar --yes=<digest> de la vista previa de /import)]' \
    '(-h --help)'{-h,--help}'[Mostrar ayuda del comando]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
