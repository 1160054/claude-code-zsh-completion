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
    'mcp:Konfigurasi dan urus pelayan MCP'
    'plugin:Urus plugin Claude Code'
    'agents:Urus agen latar belakang'
    'attach:Buka sesi latar belakang dalam terminal ini'
    'logs:Cetak output terminal terkini bagi sesi latar belakang'
    'stop:Hentikan sesi latar belakang (perbualannya disimpan)'
    'respawn:Mulakan semula sesi latar belakang supaya ia menjalankan versi Claude Code semasa'
    'rm:Padam sesi latar belakang, dan worktreenya apabila selamat berbuat demikian'
    'auth:Urus pengesahan'
    'auto-mode:Periksa atau set semula konfigurasi pengelas mod auto'
    'gateway:Jalankan get laluan pengesahan/telemetri perusahaan'
    'import:Import konfigurasi dari agen pengekodan AI lain ke dalam Claude Code'
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
    '--restricted[Mod terhad: buang alat yang menjalankan arahan atau kod serta WebFetch, abaikan tetapan user/project/local, dan hadkan alat fail kepada direktori kerja]'
    '--max-budget-usd[Jumlah dolar maksimum untuk dibelanjakan pada panggilan API (--print sahaja)]:amount:'
    '--replay-user-messages[Hantar semula mesej pengguna dari stdin pada stdout untuk pengesahan]'
    '--allowed-tools[Senarai nama alat yang dibenarkan dipisahkan koma atau ruang (contoh: "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Senarai nama alat yang dibenarkan dipisahkan koma atau ruang (format camelCase)]:tools:'
    '--tools[Tentukan senarai alat tersedia dari set terbina dalam. Mod cetak sahaja]:tools:'
    '--disallowed-tools[Senarai nama alat yang tidak dibenarkan dipisahkan koma atau ruang (contoh: "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Senarai nama alat yang tidak dibenarkan dipisahkan koma atau ruang (format camelCase)]:tools:'
    '--mcp-config[Muatkan pelayan MCP dari fail JSON atau rentetan (dipisahkan ruang)]:configs:'
    '--system-prompt[Prompt sistem untuk digunakan untuk sesi]:prompt:'
    '--system-prompt-file[Baca prompt sistem dari fail]:file:_files'
    '--append-system-prompt[Tambahkan prompt sistem kepada prompt sistem lalai]:prompt:'
    '--append-system-prompt-file[Baca prompt sistem dari fail dan tambahkan kepada prompt sistem lalai]:file:_files'
    '--system-prompt-snapshot[Rekod prompt sistem sekali bagi setiap perbualan dan guna semula sebiji-sebiji pada setiap permintaan dan sambung semula (on, lalai) atau jana semula pada setiap permintaan (off)]:mode:(on off)'
    '--permission-mode[Mod kebenaran untuk digunakan untuk sesi]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Siapa yang menjawab prompt kebenaran dengan --print: "host" (hos SDK atau --permission-prompt-tool) atau "none" (apa-apa yang akan memaparkan prompt ditolak)]:target:(host none)'
    '--permission-prompt-tool[Alat MCP untuk digunakan bagi prompt kebenaran (--print sahaja)]:tool:'
    '(-c --continue)'{-c,--continue}'[Teruskan perbualan terkini]'
    '(-r --resume)'{-r,--resume}'[Sambung semula perbualan - nyatakan ID sesi atau pilih secara interaktif]:sessionId:_claude_sessions'
    '--fork-session[Cipta ID sesi baharu daripada menggunakan semula ID sesi asal semasa menyambung semula (dengan --resume atau --continue)]'
    '--no-session-persistence[Lumpuhkan kegigihan sesi - sesi tidak akan disimpan (--print sahaja)]'
    '--model[Model untuk sesi semasa. Nyatakan alias untuk model terkini (contoh: '\''sonnet'\'' atau '\''opus'\'')]:model:_claude_model_names'
    '--agent[Agen untuk sesi semasa. Mengatasi tetapan '\''agent'\'']:agent:_claude_agent_names'
    '--betas[Header beta untuk disertakan dalam permintaan API (pengguna kunci API sahaja)]:betas:'
    '--fallback-model[Aktifkan penggantian automatik kepada model yang dinyatakan apabila model lalai terlebih muatan (--print sahaja)]:model:_claude_model_names'
    '--settings[Laluan ke fail JSON tetapan atau rentetan JSON untuk memuatkan tetapan tambahan]:file-or-json:_files'
    '--add-dir[Direktori tambahan untuk membenarkan akses alat]:directories:_directories'
    '--ide[Auto-sambung ke IDE semasa permulaan jika tepat satu IDE sah tersedia]'
    '--desktop[Buka dalam aplikasi Claude Desktop dan bukan terminal (dengan --continue atau --resume <id> untuk memilih sesi)]'
    '--strict-mcp-config[Gunakan hanya pelayan MCP dari --mcp-config dan abaikan semua tetapan MCP lain]'
    '--session-id[ID sesi khusus untuk digunakan untuk perbualan (mesti UUID sah)]:uuid:'
    '--agents[Objek JSON yang menentukan agen tersuai]:json:'
    '--setting-sources[Senarai sumber tetapan yang dipisahkan koma untuk dimuatkan (user, project, local)]:sources:'
    '--plugin-dir[Direktori untuk memuatkan plugin untuk sesi ini sahaja (boleh diulang)]:paths:_directories'
    '--disable-slash-commands[Lumpuhkan semua arahan slash]'
    '(--bg --background)'{--bg,--background}'[Mulakan sesi sebagai agen latar belakang dan kembali serta-merta]'
    '(-w --worktree)'{-w,--worktree}'[Cipta worktree git baharu untuk sesi ini (nyatakan nama secara pilihan)]::name:'
    '--tmux=-[Cipta sesi tmux untuk worktree (memerlukan --worktree). Menggunakan anak tetingkap asli iTerm2 jika tersedia; --tmux=classic untuk tmux tradisional]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Tetapkan nama paparan untuk sesi ini]:name:'
    '--effort[Tahap usaha untuk sesi semasa]:level:(low medium high xhigh max)'
    '--autocompact[Saiz tetingkap auto-padat (auto, atau 100k-1M token)]:size:(auto)'
    '--debug-file[Tulis log nyahpepijat ke laluan fail tertentu (mengaktifkan mod nyahpepijat secara tersirat)]:path:_files'
    '--from-pr[Sambung semula sesi yang dipautkan ke PR mengikut nombor/URL, atau buka pemilih interaktif]::value:'
    '--teleport[Sambung semula sesi teleport, nyatakan ID sesi secara pilihan]::session:'
    '--cloud[Cipta sesi awan dengan penerangan yang diberikan, atau lampirkan ke sesi sedia ada mengikut ID sesi atau URL claude.ai/code]::description-or-session:'
    '--environment[Cipta sesi awan baharu yang berjalan pada persekitaran hos sendiri yang diberikan (ccpool_...)]:environment_id:'
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
        attach|logs|stop|kill)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]' \
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
            '--client-id[ID klien OAuth untuk pelayan HTTP/SSE]:clientId:' \
            '--client-secret[Minta rahsia klien OAuth (atau tetapkan pembolehubah persekitaran MCP_CLIENT_SECRET)]' \
            '--callback-port[Port tetap untuk panggilan balik OAuth (untuk pelayan yang memerlukan URI ubah hala yang didaftarkan terlebih dahulu)]:port:' \
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
            '--client-secret[Minta rahsia klien OAuth (atau tetapkan pembolehubah persekitaran MCP_CLIENT_SECRET)]' \
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
        login)
          _arguments \
            '--no-browser[Cetak URL kebenaran dan bukan membuka pelayar (untuk sesi SSH/tanpa kepala)]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
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
    'configure:Tunjukkan pilihan plugin dan yang belum ditetapkan, atau simpan nilai dari stdin'
    'install:Pasang plugin dari pasaran tersedia'
    'i:Pasang plugin dari pasaran tersedia (ringkas untuk install)'
    'init:Rangka plugin baharu (auto-muat sesi seterusnya)'
    'new:Rangka plugin baharu (alias untuk init)'
    'uninstall:Nyahpasang plugin terpasang'
    'remove:Nyahpasang plugin terpasang (alias untuk uninstall)'
    'enable:Aktifkan plugin yang dilumpuhkan'
    'disable:Lumpuhkan plugin yang diaktifkan'
    'update:Kemas kini plugin ke versi terkini'
    'eval:Jalankan kes eval terhadap plugin dan laporkan hasil yang dijaringkan'
    'prune:Buang kebergantungan auto-terpasang yang tidak lagi diperlukan'
    'autoremove:Buang kebergantungan auto-terpasang yang tidak lagi diperlukan (alias untuk prune)'
    'tag:Cipta tag git {name}--v{version} untuk keluaran plugin'
    'test:Jalankan ujian mod'
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
            '--strict[Anggap amaran sebagai ralat (kod keluar 1)]' \
            '--json[Keluarkan laporan pengesahan sebagai JSON (kod keluar yang sama)]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Skop pemasangan]:scope:(user project local)' \
            '*--config[Tetapkan pilihan userConfig yang diisytiharkan dalam manifes plugin (boleh diulang)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[Terima arahan yang diisytiharkan pasaran yang dipaparkan tanpa prompt pengesahan]' \
            '--json[Cetak satu baris hasil boleh dibaca mesin dan bukan mesej untuk manusia]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Skop pemasangan]:scope:(user project local)' \
            '--keep-data[Kekalkan direktori data kekal plugin]' \
            '--prune[Turut buang kebergantungan auto-terpasang yang tidak lagi diperlukan]' \
            '(-y --yes)'{-y,--yes}'[Langkau prompt pengesahan --prune]' \
            '--json[Cetak satu baris hasil boleh dibaca mesin dan bukan mesej untuk manusia (bukan dengan --prune)]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Skop pemasangan]:scope:(user project local)' \
            '--json[Cetak satu baris hasil boleh dibaca mesin dan bukan mesej untuk manusia]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Lumpuhkan semua plugin yang diaktifkan]' \
            '(-s --scope)'{-s,--scope}'[Skop pemasangan]:scope:(user project local)' \
            '--json[Cetak satu baris hasil boleh dibaca mesin dan bukan mesej untuk manusia]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Skop pemasangan]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Terima arahan yang diisytiharkan pasaran yang dipaparkan tanpa prompt pengesahan]' \
            '--json[Cetak satu baris hasil boleh dibaca mesin dan bukan mesej untuk manusia]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Keluarkan sebagai JSON]' \
            '--available[Sertakan plugin tersedia dari pasaran (memerlukan --json)]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Pangkas pada skop]:scope:(user project local)' \
            '--dry-run[Senaraikan apa yang akan dibuang tanpa membuangnya]' \
            '(-y --yes)'{-y,--yes}'[Langkau prompt pengesahan]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]'
          ;;
        configure)
          _arguments \
            '--json[Keluarkan sebagai JSON]' \
            '--values-stdin[Baca nilai pilihan dari stdin sebagai objek JSON rentetan satu baris; pilihan yang tidak disertakan mengekalkan nilainya]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Penerangan manifes]:text:' \
            '--author[Nama pengarang (lalai: git config user.name)]:name:' \
            '--author-email[E-mel pengarang (lalai: git config user.email)]:email:' \
            '--with[Komponen untuk turut dirangka]:components:' \
            '(-f --force)'{-f,--force}'[Tulis ganti .claude-plugin/ sedia ada pada sasaran]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Tapis kes mengikut glob nama]:glob:' \
            '*--tag[Tapis kes mengikut tag (boleh diulang)]:tag:' \
            '--runs[Ganti bilangan larian setiap kes (lalai: case.runs, jika tiada 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Jalankan sehingga n larian agen serentak (1-8; lalai 1)]:n:' \
            '--model[Ganti model untuk semua kes]:model:_claude_model_names' \
            '--judge-model[Ganti model penilai LLM (lalai: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Had kos mutlak; batalkan dan laporkan hasil separa jika dicapai (kod keluar 2)]:usd:' \
            '--output-dir[Direktori untuk aggregate-result.json]:dir:_directories' \
            '--eval-dir[Nama direktori (di bawah plugin) yang menyimpan kes eval]:dir:' \
            '--json[Cetak hasil larian penuh sebagai JSON ke stdout, atau tulis ke fail .json ini]::path:_files' \
            '--threshold[Keluar dengan kod keluar 1 jika mana-mana skor kes di bawah ambang ini (lalai: 1.0)]:threshold:' \
            '*--allow-tools[Pemberian kebenaran pengendali untuk alat berpagar (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Jalankan scaffold_script setiap kes (menjalankan bash yang dibekalkan pengarang atas nama anda; dimatikan secara lalai)]' \
            '(--scaffold)--no-scaffold[Langkau scaffold_script secara eksplisit]' \
            '--trust-plugin[Tegaskan bahawa anda mempercayai plugin ini dan suite evalnya, melangkau prompt kepercayaan larian pertama (untuk CI)]' \
            '--ablation[Jalankan kumpulan kawalan garis dasar tanpa plugin dan laporkan perbezaan skor]:mode:(none with-without)' \
            '--mocks[Pengganti olok-olok untuk pelayan MCP, dari <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Dengan --mocks record: turut mulakan proses pelayan MCP sebenar yang tiada olok-olok]' \
            '--keep-temp[Kekalkan direktori rangka untuk nyahpepijat]' \
            '--verbose[Log peristiwa jejak setiap mesej ke log nyahpepijat]' \
            '--report[Tulis laporan HTML serba lengkap ke laluan ini dan bukan direktori hasil]:path:_files' \
            '(--no-publish)--publish-report[Turut wajibkan penerbitan laporan ke claude.ai]' \
            '(--publish-report)--no-publish[Simpan laporan HTML secara setempat sahaja; langkau penerbitannya ke claude.ai]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Tolak tag ke --remote selepas menciptanya]' \
            '--dry-run[Cetak apa yang akan ditag tanpa menciptanya]' \
            '(-f --force)'{-f,--force}'[Langkau pemeriksaan pepohon kerja kotor dan tag sudah wujud]' \
            '(-m --message)'{-m,--message}'[Mesej anotasi tag (gunakan %s untuk versi)]:msg:' \
            '--remote[Remote untuk ditolak dengan --push]:name:' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '::dir:_directories'
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
            '--sparse[Hadkan checkout kepada direktori tertentu melalui git sparse-checkout (untuk monorepo)]:paths:' \
            '--scope[Tempat untuk mengisytiharkan pasaran]:scope:(user project local)' \
            '--claudeai[Tambah pasaran dengan nama ini yang dihoskan oleh claude.ai untuk anda]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Keluarkan sebagai JSON]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Buang pengisytiharan pasaran dari skop tetapan tertentu (jangan nyatakan untuk membuangnya dari setiap skop)]:scope:(user project local)' \
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
    '--agent[Agen lalai untuk sesi yang dihantar dari paparan agen]:agent:_claude_agent_names' \
    '--all[Dengan --json: turut sertakan sesi latar belakang yang selesai]' \
    '--allow-dangerously-skip-permissions[Sediakan mod langkau-kebenaran kepada sesi yang dihantar]' \
    '--cwd[Tunjukkan hanya sesi latar belakang yang dimulakan di bawah laluan]:path:_directories' \
    '--dangerously-skip-permissions[Alias untuk --permission-mode bypassPermissions]' \
    '--effort[Tahap usaha lalai untuk sesi yang dihantar]:level:(low medium high xhigh max)' \
    '--json[Cetak sesi aktif sebagai tatasusunan JSON dan keluar]' \
    '*--mcp-config[Konfigurasi pelayan MCP untuk digunakan pada sesi yang dihantar]:config:' \
    '--model[Model lalai untuk sesi yang dihantar dari paparan agen]:model:_claude_model_names' \
    '--permission-mode[Mod kebenaran lalai untuk sesi yang dihantar]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Muatkan plugin dari direktori untuk paparan agen dan sesi yang dihantar]:path:_directories' \
    '--setting-sources[Senarai sumber tetapan yang dipisahkan koma untuk dimuatkan (user, project, local)]:sources:' \
    '--settings[Fail tetapan atau rentetan JSON untuk digunakan]:file-or-json:_files' \
    '--strict-mcp-config[Gunakan hanya pelayan MCP dari --mcp-config dalam sesi yang dihantar]' \
    '--restricted[Mulakan sesi yang dihantar dalam mod terhad]' \
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
        login)
          _arguments \
            '--email[Pra-isi alamat e-mel pada halaman log masuk]:email:' \
            '--sso[Paksa aliran log masuk SSO]' \
            '(--claudeai)--console[Gunakan Anthropic Console (pengebilan penggunaan API) dan bukan langganan Claude]' \
            '(--console)--claudeai[Gunakan langganan Claude (lalai)]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]'
          ;;
        status)
          _arguments \
            '(--text)--json[Keluarkan sebagai JSON (lalai)]' \
            '(--json)--text[Keluarkan sebagai teks boleh dibaca manusia]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]'
          ;;
        logout)
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
        critique)
          _arguments \
            '--model[Ganti model yang digunakan]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]'
          ;;
        defaults)
          _arguments \
            '--label[Tunjukkan hanya peraturan yang labelnya bermula dengan awalan ini (tidak peka huruf besar/kecil)]:prefix:' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Langkau prompt pengesahan]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]'
          ;;
        config)
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
            '--dry-run[Senaraikan apa yang akan dipadam tanpa memadam apa-apa]' \
            '(-y --yes)'{-y,--yes}'[Langkau prompt pengesahan]' \
            '(-i --interactive)'{-i,--interactive}'[Minta pengesahan bagi setiap item sebelum memadam]' \
            '(1)--all[Padam keadaan untuk setiap projek (saling eksklusif dengan laluan)]' \
            '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Cetak muatan bugs.json mentah dan bukan penemuan berformat]' \
    '--timeout[Minit maksimum untuk menunggu semakan selesai (lalai: 45)]:minutes:' \
    '(--no-post)--post[Siarkan penemuan semakan yang selesai ke PR atas nama anda (sasaran PR sahaja; satu komen biasa, bukan semakan)]' \
    '(--post)--no-post[Jangan siarkan penemuan ke PR (lalai)]' \
    '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Mulakan semula setiap sesi latar belakang yang sedang berjalan]' \
    '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Turut buang komit yang belum ditolak dan perubahan yang belum dikomit dalam worktree (berikan commit@worktree-id yang dilaporkan oleh claude rm sebelumnya)]:commit@worktree-id:' \
    '--force-remove-worktree[Padam direktori worktree walaupun hook WorktreeRemove atau git tidak dapat membuangnya (berikan worktree-id yang dilaporkan oleh claude rm sebelumnya)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Tunjukkan apa yang akan diimport tanpa menulis apa-apa]' \
    '--yes[Langkau pemilih interaktif (pada permukaan tanpa kepala, berikan --yes=<digest> dari pratonton /import)]' \
    '(-h --help)'{-h,--help}'[Paparkan bantuan untuk arahan]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
