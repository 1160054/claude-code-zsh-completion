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
    'mcp:Configurar y gestionar servidores MCP'
    'plugin:Gestionar plugins de Claude Code'
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
    '--replay-user-messages[Reenviar mensajes de usuario desde stdin en stdout para confirmación]'
    '--allowed-tools[Lista separada por comas o espacios de nombres de herramientas permitidas (ej., "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Lista separada por comas o espacios de nombres de herramientas permitidas (formato camelCase)]:tools:'
    '--tools[Especificar lista de herramientas disponibles del conjunto incorporado. Solo modo de impresión]:tools:'
    '--disallowed-tools[Lista separada por comas o espacios de nombres de herramientas no permitidas (ej., "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Lista separada por comas o espacios de nombres de herramientas no permitidas (formato camelCase)]:tools:'
    '--mcp-config[Cargar servidores MCP desde archivo JSON o cadena (separados por espacios)]:configs:'
    '--system-prompt[Prompt del sistema a usar para la sesión]:prompt:'
    '--append-system-prompt[Agregar prompt del sistema al prompt del sistema predeterminado]:prompt:'
    '--permission-mode[Modo de permisos a usar para la sesión]:mode:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Continuar la conversación más reciente]'
    '(-r --resume)'{-r,--resume}'[Reanudar una conversación - especificar ID de sesión o seleccionar interactivamente]:sessionId:_claude_sessions'
    '--fork-session[Crear nuevo ID de sesión en lugar de reutilizar el ID de sesión original al reanudar (con --resume o --continue)]'
    '--model[Modelo para la sesión actual. Especificar alias del modelo más reciente (ej., '\''sonnet'\'' o '\''opus'\'')]:model:'
    '--fallback-model[Habilitar respaldo automático al modelo especificado cuando el modelo predeterminado está sobrecargado (solo --print)]:model:'
    '--settings[Ruta al archivo JSON de configuración o cadena JSON para cargar configuración adicional]:file-or-json:_files'
    '--add-dir[Directorios adicionales para permitir acceso de herramientas]:directories:_directories'
    '--ide[Conectar automáticamente al IDE al inicio si hay exactamente un IDE válido disponible]'
    '--strict-mcp-config[Usar solo servidores MCP de --mcp-config e ignorar todas las demás configuraciones MCP]'
    '--session-id[ID de sesión específico para usar en la conversación (debe ser UUID válido)]:uuid:'
    '--agents[Objeto JSON que define agentes personalizados]:json:'
    '--setting-sources[Lista separada por comas de fuentes de configuración a cargar (user, project, local)]:sources:'
    '--plugin-dir[Directorio desde el cual cargar plugins solo para esta sesión (repetible)]:paths:_directories'
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
      esac
      ;;
  esac
}
_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Validar un plugin o manifiesto de marketplace'
    'marketplace:Gestionar marketplaces de Claude Code'
    'install:Instalar un plugin desde marketplaces disponibles'
    'i:Instalar un plugin desde marketplaces disponibles (abreviatura de install)'
    'uninstall:Desinstalar un plugin instalado'
    'remove:Desinstalar un plugin instalado (alias de uninstall)'
    'enable:Habilitar un plugin deshabilitado'
    'disable:Deshabilitar un plugin habilitado'
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
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:plugin:_claude_installed_plugins'
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
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]'
          ;;
        remove|rm)
          _arguments \
            '(-h --help)'{-h,--help}'[Mostrar ayuda]' \
            '1:name:_claude_mcp_servers'
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
(( $+_comps[claude] )) || compdef _claude claude
