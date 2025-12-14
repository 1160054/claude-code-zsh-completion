#compdef claude
# Fungsi penyempurnaan dinamik
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
    'mcp:Konfigurasi dan urus pelayan MCP'
    'plugin:Urus plugin Claude Code'
    'setup-token:Sediakan token pengesahan jangka panjang (memerlukan langganan Claude)'
    'doctor:Pemeriksaan kesihatan untuk auto-updater Claude Code'
    'update:Semak dan pasang kemas kini'
    'install:Pasang binaan asli Claude Code'
  )
  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Aktifkan mod nyahpepijat dengan penapisan kategori pilihan (contoh: "api,hooks" atau "!statsig,!file")]:filter:'
    '--verbose[Ganti tetapan mod verbos dari fail konfigurasi]'
    '(-p --print)'{-p,--print}'[Cetak respons dan keluar (untuk digunakan dengan paip). Nota: gunakan hanya dalam direktori dipercayai]'
    '--output-format[Format output (dengan --print): "text" (lalai), "json" (hasil tunggal), atau "stream-json" (penstriman masa nyata)]:format:(text json stream-json)'
    '--json-schema[Skema JSON untuk pengesahan output berstruktur]:schema:'
    '--include-partial-messages[Sertakan serpihan mesej separa semasa tiba (dengan --print dan --output-format=stream-json)]'
    '--input-format[Format input (dengan --print): "text" (lalai) atau "stream-json" (penstriman input masa nyata)]:format:(text stream-json)'
    '--mcp-debug[\[Tidak digalakkan. Gunakan --debug sebaliknya\] Aktifkan mod nyahpepijat MCP (tunjukkan ralat pelayan MCP)]'
    '--dangerously-skip-permissions[Langkau semua pemeriksaan kebenaran. Disyorkan hanya untuk kotak pasir tanpa akses internet]'
    '--allow-dangerously-skip-permissions[Aktifkan pilihan untuk melangkau pemeriksaan kebenaran tanpa mengaktifkan secara lalai]'
    '--replay-user-messages[Hantar semula mesej pengguna dari stdin pada stdout untuk pengesahan]'
    '--allowed-tools[Senarai nama alat yang dibenarkan dipisahkan koma atau ruang (contoh: "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Senarai nama alat yang dibenarkan dipisahkan koma atau ruang (format camelCase)]:tools:'
    '--tools[Tentukan senarai alat tersedia dari set terbina dalam. Mod cetak sahaja]:tools:'
    '--disallowed-tools[Senarai nama alat yang tidak dibenarkan dipisahkan koma atau ruang (contoh: "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Senarai nama alat yang tidak dibenarkan dipisahkan koma atau ruang (format camelCase)]:tools:'
    '--mcp-config[Muatkan pelayan MCP dari fail JSON atau rentetan (dipisahkan ruang)]:configs:'
    '--system-prompt[Prompt sistem untuk digunakan untuk sesi]:prompt:'
    '--append-system-prompt[Tambahkan prompt sistem kepada prompt sistem lalai]:prompt:'
    '--permission-mode[Mod kebenaran untuk digunakan untuk sesi]:mode:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Teruskan perbualan terkini]'
    '(-r --resume)'{-r,--resume}'[Sambung semula perbualan - nyatakan ID sesi atau pilih secara interaktif]:sessionId:_claude_sessions'
    '--fork-session[Cipta ID sesi baharu daripada menggunakan semula ID sesi asal semasa menyambung semula (dengan --resume atau --continue)]'
    '--model[Model untuk sesi semasa. Nyatakan alias untuk model terkini (contoh: '\''sonnet'\'' atau '\''opus'\'')]:model:'
    '--fallback-model[Aktifkan penggantian automatik kepada model yang dinyatakan apabila model lalai terlebih muatan (--print sahaja)]:model:'
    '--settings[Laluan ke fail JSON tetapan atau rentetan JSON untuk memuatkan tetapan tambahan]:file-or-json:_files'
    '--add-dir[Direktori tambahan untuk membenarkan akses alat]:directories:_directories'
    '--ide[Auto-sambung ke IDE semasa permulaan jika tepat satu IDE sah tersedia]'
    '--strict-mcp-config[Gunakan hanya pelayan MCP dari --mcp-config dan abaikan semua tetapan MCP lain]'
    '--session-id[ID sesi khusus untuk digunakan untuk perbualan (mesti UUID sah)]:uuid:'
    '--agents[Objek JSON yang menentukan agen tersuai]:json:'
    '--setting-sources[Senarai sumber tetapan yang dipisahkan koma untuk dimuatkan (user, project, local)]:sources:'
    '--plugin-dir[Direktori untuk memuatkan plugin untuk sesi ini sahaja (boleh diulang)]:paths:_directories'
    '(-v --version)'{-v,--version}'[Keluarkan nombor versi]'
    '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]'
  )
  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'arahan claude' main_commands
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
          _message "tiada argumen"
          ;;
      esac
      ;;
  esac
}
_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Mulakan pelayan MCP Claude Code'
    'add:Tambah pelayan MCP ke Claude Code'
    'remove:Buang pelayan MCP'
    'list:Senaraikan pelayan MCP yang dikonfigurasi'
    'get:Dapatkan butiran pelayan MCP'
    'add-json:Tambah pelayan MCP (stdio atau SSE) dengan rentetan JSON'
    'add-from-claude-desktop:Import pelayan MCP dari Claude Desktop (Mac dan WSL sahaja)'
    'reset-project-choices:Set semula semua pelayan (diluluskan/ditolak) berskop projek (.mcp.json) dalam projek ini'
    'help:Paparkan bantuan'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'arahan mcp' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Aktifkan mod nyahpepijat]' \
            '--verbose[Ganti tetapan mod verbos dari fail konfigurasi]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Skop konfigurasi (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Jenis pengangkutan (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Tetapkan pembolehubah persekitaran (contoh: -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Tetapkan header WebSocket]:header:' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Skop konfigurasi (local, user, project) - buang dari skop sedia ada jika tidak dinyatakan]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Skop konfigurasi (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Skop konfigurasi (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]'
          ;;
      esac
      ;;
  esac
}
_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Sahkan plugin atau manifes pasaran'
    'marketplace:Urus pasaran Claude Code'
    'install:Pasang plugin dari pasaran tersedia'
    'i:Pasang plugin dari pasaran tersedia (ringkas untuk install)'
    'uninstall:Nyahpasang plugin terpasang'
    'remove:Nyahpasang plugin terpasang (alias untuk uninstall)'
    'enable:Aktifkan plugin yang dilumpuhkan'
    'disable:Lumpuhkan plugin yang diaktifkan'
    'help:Paparkan bantuan'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'arahan plugin' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:plugin:_claude_installed_plugins'
          ;;
      esac
      ;;
  esac
}
_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Tambah pasaran dari URL, laluan, atau repositori GitHub'
    'list:Senaraikan pasaran yang dikonfigurasi'
    'remove:Buang pasaran yang dikonfigurasi'
    'rm:Buang pasaran yang dikonfigurasi (alias untuk remove)'
    'update:Kemas kini pasaran dari sumber - kemas kini semua jika tiada nama dinyatakan'
    'help:Paparkan bantuan'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'arahan marketplace' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]'
          ;;
        remove|rm)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}
_claude_install() {
  _arguments \
    '--force[Paksa pemasangan walaupun sudah terpasang]' \
    '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
    '::target:(stable latest)'
}
(( $+_comps[claude] )) || compdef _claude claude
