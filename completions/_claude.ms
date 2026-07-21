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
    'mcp:Konfigurasi dan urus pelayan MCP'
    'plugin:Urus plugin Claude Code'
    'agents:Urus agen latar belakang'
    'auth:Urus pengesahan'
    'auto-mode:Periksa atau set semula konfigurasi pengelas mod auto'
    'gateway:Jalankan get laluan pengesahan/telemetri perusahaan'
    'project:Urus keadaan projek Claude Code'
    'ultrareview:Jalankan semakan kod berbilang agen dihoskan awan dan cetak penemuan'
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
    '--max-budget-usd[Jumlah dolar maksimum untuk dibelanjakan pada panggilan API (--print sahaja)]:amount:'
    '--replay-user-messages[Hantar semula mesej pengguna dari stdin pada stdout untuk pengesahan]'
    '--allowed-tools[Senarai nama alat yang dibenarkan dipisahkan koma atau ruang (contoh: "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Senarai nama alat yang dibenarkan dipisahkan koma atau ruang (format camelCase)]:tools:'
    '--tools[Tentukan senarai alat tersedia dari set terbina dalam. Mod cetak sahaja]:tools:'
    '--disallowed-tools[Senarai nama alat yang tidak dibenarkan dipisahkan koma atau ruang (contoh: "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Senarai nama alat yang tidak dibenarkan dipisahkan koma atau ruang (format camelCase)]:tools:'
    '--mcp-config[Muatkan pelayan MCP dari fail JSON atau rentetan (dipisahkan ruang)]:configs:'
    '--system-prompt[Prompt sistem untuk digunakan untuk sesi]:prompt:'
    '--append-system-prompt[Tambahkan prompt sistem kepada prompt sistem lalai]:prompt:'
    '--permission-mode[Mod kebenaran untuk digunakan untuk sesi]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Teruskan perbualan terkini]'
    '(-r --resume)'{-r,--resume}'[Sambung semula perbualan - nyatakan ID sesi atau pilih secara interaktif]:sessionId:_claude_sessions'
    '--fork-session[Cipta ID sesi baharu daripada menggunakan semula ID sesi asal semasa menyambung semula (dengan --resume atau --continue)]'
    '--no-session-persistence[Lumpuhkan kegigihan sesi - sesi tidak akan disimpan (--print sahaja)]'
    '--model[Model untuk sesi semasa. Nyatakan alias untuk model terkini (contoh: '\''sonnet'\'' atau '\''opus'\'')]:model:'
    '--agent[Agen untuk sesi semasa. Mengatasi tetapan '\''agent'\'']:agent:'
    '--betas[Header beta untuk disertakan dalam permintaan API (pengguna kunci API sahaja)]:betas:'
    '--fallback-model[Aktifkan penggantian automatik kepada model yang dinyatakan apabila model lalai terlebih muatan (--print sahaja)]:model:'
    '--settings[Laluan ke fail JSON tetapan atau rentetan JSON untuk memuatkan tetapan tambahan]:file-or-json:_files'
    '--add-dir[Direktori tambahan untuk membenarkan akses alat]:directories:_directories'
    '--ide[Auto-sambung ke IDE semasa permulaan jika tepat satu IDE sah tersedia]'
    '--strict-mcp-config[Gunakan hanya pelayan MCP dari --mcp-config dan abaikan semua tetapan MCP lain]'
    '--session-id[ID sesi khusus untuk digunakan untuk perbualan (mesti UUID sah)]:uuid:'
    '--agents[Objek JSON yang menentukan agen tersuai]:json:'
    '--setting-sources[Senarai sumber tetapan yang dipisahkan koma untuk dimuatkan (user, project, local)]:sources:'
    '--plugin-dir[Direktori untuk memuatkan plugin untuk sesi ini sahaja (boleh diulang)]:paths:_directories'
    '--disable-slash-commands[Lumpuhkan semua arahan slash]'
    '(--bg --background)'{--bg,--background}'[Mulakan sesi sebagai agen latar belakang dan kembali serta-merta]'
    '(-w --worktree)'{-w,--worktree}'[Cipta worktree git baharu untuk sesi ini (nyatakan nama secara pilihan)]::name:'
    '--tmux[Cipta sesi tmux untuk worktree (memerlukan --worktree)]'
    '(-n --name)'{-n,--name}'[Tetapkan nama paparan untuk sesi ini]:name:'
    '--effort[Tahap usaha untuk sesi semasa]:level:(low medium high xhigh max)'
    '--debug-file[Tulis log nyahpepijat ke laluan fail tertentu (mengaktifkan mod nyahpepijat secara tersirat)]:path:_files'
    '--from-pr[Sambung semula sesi yang dipautkan ke PR mengikut nombor/URL, atau buka pemilih interaktif]::value:'
    '--remote-control[Mulakan sesi interaktif dengan Kawalan Jauh diaktifkan (nama secara pilihan)]::name:'
    '--remote-control-session-name-prefix[Awalan untuk nama sesi Kawalan Jauh yang dijana automatik]:prefix:'
    '--chrome[Aktifkan integrasi Claude dalam Chrome]'
    '--no-chrome[Lumpuhkan integrasi Claude dalam Chrome]'
    '--plugin-url[Ambil .zip plugin dari URL untuk sesi ini sahaja (boleh diulang)]:url:'
    '--file[Sumber fail untuk dimuat turun semasa permulaan (format: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Aktifkan cadangan prompt (mengeluarkan prompt seterusnya yang diramalkan dalam mod print/SDK)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Majukan teks subagen dan blok pemikiran sebagai mesej (dengan --print dan stream-json)]'
    '--include-hook-events[Sertakan semua peristiwa kitaran hayat hook dalam strim output (dengan stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Alihkan bahagian setiap mesin ke mesej pengguna pertama untuk meningkatkan penggunaan semula cache prompt]'
    '--brief[Aktifkan alat SendUserMessage untuk komunikasi agen-ke-pengguna]'
    '--safe-mode[Mulakan dengan semua penyesuaian dilumpuhkan (berguna untuk menyelesaikan masalah konfigurasi yang rosak)]'
    '--bare[Mod minimum: langkau hooks, LSP, penyegerakan plugin, atribusi, auto-memori, dan penemuan automatik CLAUDE.md]'
    '--ax-screen-reader[Papar output mesra pembaca skrin (teks rata, tiada sempadan atau animasi hiasan)]'
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
    'login:Sahkan dengan pelayan MCP (HTTP, SSE, atau penyambung claude.ai)'
    'logout:Kosongkan kelayakan OAuth yang disimpan untuk pelayan MCP'
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
        login|logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:name:_claude_mcp_servers'
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
    'list:Senaraikan plugin terpasang'
    'details:Tunjukkan inventori komponen dan kos token unjuran untuk plugin'
    'install:Pasang plugin dari pasaran tersedia'
    'i:Pasang plugin dari pasaran tersedia (ringkas untuk install)'
    'init:Rangka plugin baharu (auto-muat sesi seterusnya)'
    'uninstall:Nyahpasang plugin terpasang'
    'remove:Nyahpasang plugin terpasang (alias untuk uninstall)'
    'enable:Aktifkan plugin yang dilumpuhkan'
    'disable:Lumpuhkan plugin yang diaktifkan'
    'update:Kemas kini plugin ke versi terkini'
    'eval:Jalankan kes eval terhadap plugin dan laporkan hasil yang dijaringkan'
    'prune:Buang kebergantungan auto-terpasang yang tidak lagi diperlukan'
    'tag:Cipta tag git {name}--v{version} untuk keluaran plugin'
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
            '(-s --scope)'{-s,--scope}'[Skop pemasangan]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Skop pemasangan]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Skop pemasangan]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Skop pemasangan]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:path:_files'
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

_claude_agents() {
  _arguments \
    '*--add-dir[Direktori tambahan untuk membenarkan akses alat dalam sesi yang dihantar]:directory:_directories' \
    '--agent[Agen lalai untuk sesi yang dihantar dari paparan agen]:agent:' \
    '--all[Dengan --json: turut sertakan sesi latar belakang yang selesai]' \
    '--allow-dangerously-skip-permissions[Sediakan mod langkau-kebenaran kepada sesi yang dihantar]' \
    '--cwd[Tunjukkan hanya sesi latar belakang yang dimulakan di bawah laluan]:path:_directories' \
    '--dangerously-skip-permissions[Alias untuk --permission-mode bypassPermissions]' \
    '--effort[Tahap usaha lalai untuk sesi yang dihantar]:level:(low medium high xhigh max)' \
    '--json[Cetak sesi aktif sebagai tatasusunan JSON dan keluar]' \
    '*--mcp-config[Konfigurasi pelayan MCP untuk digunakan pada sesi yang dihantar]:config:' \
    '--model[Model lalai untuk sesi yang dihantar dari paparan agen]:model:' \
    '--permission-mode[Mod kebenaran lalai untuk sesi yang dihantar]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Muatkan plugin dari direktori untuk paparan agen dan sesi yang dihantar]:path:_directories' \
    '--setting-sources[Senarai sumber tetapan yang dipisahkan koma untuk dimuatkan (user, project, local)]:sources:' \
    '--settings[Fail tetapan atau rentetan JSON untuk digunakan]:file-or-json:_files' \
    '--strict-mcp-config[Gunakan hanya pelayan MCP dari --mcp-config dalam sesi yang dihantar]' \
    '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Log masuk ke akaun Anthropic anda'
    'logout:Log keluar dari akaun Anthropic anda'
    'status:Tunjukkan status pengesahan'
    'help:Paparkan bantuan'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'arahan auth' auth_commands
      ;;
    args)
      case $words[1] in
        login|logout|status)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Cetak konfigurasi mod auto berkesan sebagai JSON'
    'critique:Dapatkan maklum balas AI mengenai peraturan mod auto tersuai anda'
    'defaults:Cetak peraturan mod auto lalai sebagai JSON'
    'reset:Set semula konfigurasi mod auto kepada lalai yang dihantar'
    'help:Paparkan bantuan'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'arahan auto-mode' auto_mode_commands
      ;;
    args)
      case $words[1] in
        config|critique|defaults|reset)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Laluan ke konfigurasi YAML get laluan]:path:_files' \
    '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Padam semua keadaan Claude Code untuk projek (transkrip, tugasan, sejarah fail, entri konfigurasi)'
    'help:Paparkan bantuan'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'arahan project' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Cetak muatan bugs.json mentah dan bukan penemuan berformat]' \
    '--timeout[Minit maksimum untuk menunggu semakan selesai]:minutes:' \
    '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
