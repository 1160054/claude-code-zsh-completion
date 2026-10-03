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
    'mcp:Διαμόρφωση και διαχείριση διακομιστών MCP'
    'plugin:Διαχείριση προσθέτων Claude Code'
    'agents:Διαχείριση πρακτόρων παρασκηνίου'
    'attach:Άνοιγμα συνεδρίας παρασκηνίου σε αυτό το τερματικό'
    'logs:Εκτύπωση της πρόσφατης εξόδου τερματικού μιας συνεδρίας παρασκηνίου'
    'stop:Διακοπή συνεδρίας παρασκηνίου (η συνομιλία της διατηρείται)'
    'respawn:Επανεκκίνηση συνεδρίας παρασκηνίου ώστε να εκτελεί την τρέχουσα έκδοση του Claude Code'
    'rm:Διαγραφή συνεδρίας παρασκηνίου, καθώς και του worktree της όταν αυτό είναι ασφαλές'
    'auth:Διαχείριση ελέγχου ταυτότητας'
    'auto-mode:Επιθεώρηση ή επαναφορά διαμόρφωσης ταξινομητή αυτόματης λειτουργίας'
    'gateway:Εκτέλεση της εταιρικής πύλης ελέγχου ταυτότητας/τηλεμετρίας'
    'import:Εισαγωγή διαμόρφωσης από άλλον πράκτορα προγραμματισμού AI στο Claude Code'
    'project:Διαχείριση κατάστασης έργου Claude Code'
    'ultrareview:Εκτέλεση αξιολόγησης κώδικα πολλαπλών πρακτόρων φιλοξενούμενης στο cloud και εκτύπωση των ευρημάτων'
    'setup-token:Ρύθμιση μακροπρόθεσμου διακριτικού ελέγχου ταυτότητας (απαιτεί συνδρομή Claude)'
    'doctor:Έλεγχος υγείας για το αυτόματο ενημερωτικό του Claude Code'
    'update:Έλεγχος και εγκατάσταση ενημερώσεων'
    'install:Εγκατάσταση εγγενούς έκδοσης Claude Code'
  )

  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Ενεργοποίηση λειτουργίας αποσφαλμάτωσης με προαιρετικό φιλτράρισμα κατηγοριών (π.χ. "api,hooks" ή "!statsig,!file")]:filter:'
    '--verbose[Παράκαμψη ρύθμισης λεπτομερούς λειτουργίας από το αρχείο διαμόρφωσης]'
    '(-p --print)'{-p,--print}'[Εκτύπωση απάντησης και έξοδος (για χρήση με pipes). Σημείωση: χρησιμοποιήστε μόνο σε αξιόπιστους καταλόγους]'
    '--output-format[Μορφή εξόδου (με --print): "text" (προεπιλογή), "json" (μεμονωμένο αποτέλεσμα), ή "stream-json" (ροή σε πραγματικό χρόνο)]:format:(text json stream-json)'
    '--json-schema[Σχήμα JSON για επικύρωση δομημένης εξόδου]:schema:'
    '--include-partial-messages[Συμπερίληψη τμημάτων μερικών μηνυμάτων καθώς φτάνουν (με --print και --output-format=stream-json)]'
    '--input-format[Μορφή εισόδου (με --print): "text" (προεπιλογή) ή "stream-json" (είσοδος ροής σε πραγματικό χρόνο)]:format:(text stream-json)'
    '--mcp-debug[\[Παρωχημένο. Χρησιμοποιήστε --debug αντί αυτού\] Ενεργοποίηση λειτουργίας αποσφαλμάτωσης MCP (εμφανίζει σφάλματα διακομιστή MCP)]'
    '--dangerously-skip-permissions[Παράκαμψη όλων των ελέγχων αδειών. Συνιστάται μόνο για απομονωμένα περιβάλλοντα χωρίς πρόσβαση στο διαδίκτυο]'
    '--allow-dangerously-skip-permissions[Ενεργοποίηση επιλογής παράκαμψης ελέγχων αδειών χωρίς ενεργοποίηση από προεπιλογή]'
    '--restricted[Περιορισμένη λειτουργία: αφαίρεση των εργαλείων που εκτελούν εντολές ή κώδικα και του WebFetch, αγνόηση των ρυθμίσεων user/project/local και περιορισμός των εργαλείων αρχείων στους καταλόγους εργασίας]'
    '--max-budget-usd[Μέγιστο ποσό σε δολάρια για δαπάνη σε κλήσεις API (μόνο --print)]:amount:'
    '--replay-user-messages[Επαναποστολή μηνυμάτων χρήστη από stdin σε stdout για επιβεβαίωση]'
    '--allowed-tools[Λίστα διαχωρισμένη με κόμματα ή κενά με ονόματα επιτρεπόμενων εργαλείων (π.χ. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Λίστα διαχωρισμένη με κόμματα ή κενά με ονόματα επιτρεπόμενων εργαλείων (μορφή camelCase)]:tools:'
    '--tools[Καθορισμός λίστας διαθέσιμων εργαλείων από το ενσωματωμένο σύνολο. Μόνο λειτουργία εκτύπωσης]:tools:'
    '--disallowed-tools[Λίστα διαχωρισμένη με κόμματα ή κενά με ονόματα μη επιτρεπόμενων εργαλείων (π.χ. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Λίστα διαχωρισμένη με κόμματα ή κενά με ονόματα μη επιτρεπόμενων εργαλείων (μορφή camelCase)]:tools:'
    '--mcp-config[Φόρτωση διακομιστών MCP από αρχείο JSON ή συμβολοσειρά (διαχωρισμένα με κενά)]:configs:'
    '--system-prompt[Προτροπή συστήματος για χρήση στη συνεδρία]:prompt:'
    '--system-prompt-file[Ανάγνωση προτροπής συστήματος από αρχείο]:file:_files'
    '--append-system-prompt[Προσάρτηση προτροπής συστήματος στην προεπιλεγμένη προτροπή συστήματος]:prompt:'
    '--append-system-prompt-file[Ανάγνωση προτροπής συστήματος από αρχείο και προσάρτηση στην προεπιλεγμένη προτροπή συστήματος]:file:_files'
    '--system-prompt-snapshot[Καταγραφή της προτροπής συστήματος μία φορά ανά συνομιλία και αυτούσια επαναχρησιμοποίησή της σε κάθε αίτημα και συνέχιση (on, η προεπιλογή) ή εκ νέου απόδοσή της σε κάθε αίτημα (off)]:mode:(on off)'
    '--permission-mode[Λειτουργία αδειών για χρήση στη συνεδρία]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Ποιος απαντά στις προτροπές αδειών με --print: "host" (η εφαρμογή-ξενιστής του SDK ή το --permission-prompt-tool) ή "none" (οτιδήποτε θα εμφάνιζε προτροπή απορρίπτεται)]:target:(host none)'
    '--permission-prompt-tool[Εργαλείο MCP για χρήση στις προτροπές αδειών (μόνο --print)]:tool:'
    '(-c --continue)'{-c,--continue}'[Συνέχιση της πιο πρόσφατης συνομιλίας]'
    '(-r --resume)'{-r,--resume}'[Συνέχιση συνομιλίας - καθορίστε αναγνωριστικό συνεδρίας ή επιλέξτε διαδραστικά]:sessionId:_claude_sessions'
    '--fork-session[Δημιουργία νέου αναγνωριστικού συνεδρίας αντί επαναχρησιμοποίησης του αρχικού κατά τη συνέχιση (με --resume ή --continue)]'
    '--no-session-persistence[Απενεργοποίηση διατήρησης συνεδρίας - οι συνεδρίες δεν θα αποθηκεύονται (μόνο --print)]'
    '--model[Μοντέλο για τρέχουσα συνεδρία. Καθορίστε ψευδώνυμο για το πιο πρόσφατο μοντέλο (π.χ. '\''sonnet'\'' ή '\''opus'\'')]:model:_claude_model_names'
    '--agent[Πράκτορας για την τρέχουσα συνεδρία. Παρακάμπτει τη ρύθμιση '\''agent'\'']:agent:_claude_agent_names'
    '--betas[Κεφαλίδες beta για συμπερίληψη σε αιτήματα API (μόνο χρήστες κλειδιού API)]:betas:'
    '--fallback-model[Ενεργοποίηση αυτόματης εναλλακτικής λύσης σε καθορισμένο μοντέλο όταν το προεπιλεγμένο μοντέλο είναι υπερφορτωμένο (μόνο --print)]:model:_claude_model_names'
    '--settings[Διαδρομή σε αρχείο JSON ρυθμίσεων ή συμβολοσειρά JSON για φόρτωση πρόσθετων ρυθμίσεων]:file-or-json:_files'
    '--add-dir[Πρόσθετοι κατάλογοι για επιτρεπόμενη πρόσβαση εργαλείων]:directories:_directories'
    '--ide[Αυτόματη σύνδεση σε IDE κατά την εκκίνηση εάν είναι διαθέσιμο ακριβώς ένα έγκυρο IDE]'
    '--desktop[Άνοιγμα στην εφαρμογή Claude Desktop αντί για το τερματικό (με --continue ή --resume <id> για επιλογή της συνεδρίας)]'
    '--strict-mcp-config[Χρήση μόνο διακομιστών MCP από --mcp-config και αγνόηση όλων των άλλων ρυθμίσεων MCP]'
    '--session-id[Συγκεκριμένο αναγνωριστικό συνεδρίας για χρήση στη συνομιλία (πρέπει να είναι έγκυρο UUID)]:uuid:'
    '--agents[Αντικείμενο JSON που ορίζει προσαρμοσμένους πράκτορες]:json:'
    '--setting-sources[Λίστα διαχωρισμένη με κόμματα από πηγές ρυθμίσεων για φόρτωση (user, project, local)]:sources:'
    '--plugin-dir[Κατάλογος για φόρτωση προσθέτων μόνο για αυτή τη συνεδρία (επαναλαμβανόμενο)]:paths:_directories'
    '--disable-slash-commands[Απενεργοποίηση όλων των εντολών slash]'
    '(--bg --background)'{--bg,--background}'[Εκκίνηση της συνεδρίας ως πράκτορας παρασκηνίου και άμεση επιστροφή]'
    '(-w --worktree)'{-w,--worktree}'[Δημιουργία νέου git worktree για αυτή τη συνεδρία (προαιρετικά καθορίστε όνομα)]::name:'
    '--tmux=-[Δημιουργία συνεδρίας tmux για το worktree (απαιτεί --worktree). Χρησιμοποιεί εγγενή πλαίσια (panes) του iTerm2 όταν είναι διαθέσιμα· --tmux=classic για παραδοσιακό tmux]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Ορισμός εμφανιζόμενου ονόματος για αυτή τη συνεδρία]:name:'
    '--effort[Επίπεδο προσπάθειας για την τρέχουσα συνεδρία]:level:(low medium high xhigh max)'
    '--autocompact[Μέγεθος παραθύρου αυτόματης συμπύκνωσης (auto, ή 100k-1M tokens)]:size:(auto)'
    '--debug-file[Εγγραφή αρχείων καταγραφής αποσφαλμάτωσης σε συγκεκριμένη διαδρομή αρχείου (ενεργοποιεί έμμεσα τη λειτουργία αποσφαλμάτωσης)]:path:_files'
    '--from-pr[Συνέχιση συνεδρίας συνδεδεμένης με PR βάσει αριθμού/URL, ή άνοιγμα διαδραστικού επιλογέα]::value:'
    '--teleport[Συνέχιση συνεδρίας teleport, προαιρετικά καθορίστε αναγνωριστικό συνεδρίας]::session:'
    '--cloud[Δημιουργία συνεδρίας cloud με τη δοσμένη περιγραφή ή σύνδεση σε υπάρχουσα βάσει αναγνωριστικού συνεδρίας ή URL claude.ai/code]::description-or-session:'
    '--environment[Δημιουργία νέας συνεδρίας cloud που εκτελείται στο δοσμένο αυτοφιλοξενούμενο περιβάλλον (ccpool_...)]:environment_id:'
    '--remote-control[Εκκίνηση διαδραστικής συνεδρίας με ενεργοποιημένο τον Απομακρυσμένο Έλεγχο (προαιρετικά με όνομα)]::name:'
    '--remote-control-session-name-prefix[Πρόθεμα για αυτόματα δημιουργούμενα ονόματα συνεδριών Απομακρυσμένου Ελέγχου]:prefix:'
    '--chrome[Ενεργοποίηση ενσωμάτωσης Claude στο Chrome]'
    '--no-chrome[Απενεργοποίηση ενσωμάτωσης Claude στο Chrome]'
    '--plugin-url[Λήψη .zip προσθέτου από URL μόνο για αυτή τη συνεδρία (επαναλαμβανόμενο)]:url:'
    '--file[Πόροι αρχείων για λήψη κατά την εκκίνηση (μορφή: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Ενεργοποίηση προτάσεων προτροπής (εκπέμπει μια προβλεπόμενη επόμενη προτροπή σε λειτουργία print/SDK)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Προώθηση κειμένου υποπράκτορα και μπλοκ σκέψης ως μηνύματα (με --print και stream-json)]'
    '--include-hook-events[Συμπερίληψη όλων των συμβάντων κύκλου ζωής hook στη ροή εξόδου (με stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Μετακίνηση ενοτήτων ανά μηχάνημα στο πρώτο μήνυμα χρήστη για βελτίωση επαναχρησιμοποίησης της κρυφής μνήμης προτροπής]'
    '--brief[Ενεργοποίηση εργαλείου SendUserMessage για επικοινωνία πράκτορα-προς-χρήστη]'
    '--safe-mode[Εκκίνηση με όλες τις προσαρμογές απενεργοποιημένες (χρήσιμο για αντιμετώπιση προβλημάτων κατεστραμμένης διαμόρφωσης)]'
    '--bare[Ελάχιστη λειτουργία: παράλειψη hooks, LSP, συγχρονισμού προσθέτων, απόδοσης, αυτόματης μνήμης και αυτόματης ανακάλυψης CLAUDE.md]'
    '--ax-screen-reader[Απόδοση εξόδου φιλικής προς αναγνώστες οθόνης (επίπεδο κείμενο, χωρίς διακοσμητικά περιγράμματα ή κινούμενα σχέδια)]'
    '(-v --version)'{-v,--version}'[Εμφάνιση αριθμού έκδοσης]'
    '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]'
  )

  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'claude commands' main_commands
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
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]' \
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
          _message "χωρίς ορίσματα"
          ;;
      esac
      ;;
  esac
}

_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Εκκίνηση διακομιστή MCP του Claude Code'
    'add:Προσθήκη διακομιστή MCP στο Claude Code'
    'remove:Αφαίρεση διακομιστή MCP'
    'list:Λίστα διαμορφωμένων διακομιστών MCP'
    'get:Λήψη λεπτομερειών διακομιστή MCP'
    'add-json:Προσθήκη διακομιστή MCP (stdio ή SSE) με συμβολοσειρά JSON'
    'add-from-claude-desktop:Εισαγωγή διακομιστών MCP από το Claude Desktop (μόνο Mac και WSL)'
    'reset-project-choices:Επαναφορά όλων των εγκεκριμένων/απορριφθέντων διακομιστών εμβέλειας έργου (.mcp.json) σε αυτό το έργο'
    'login:Έλεγχος ταυτότητας με διακομιστή MCP (HTTP, SSE ή σύνδεσμος claude.ai)'
    'logout:Εκκαθάριση αποθηκευμένων διαπιστευτηρίων OAuth για διακομιστή MCP'
    'help:Εμφάνιση βοήθειας'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'mcp commands' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Ενεργοποίηση λειτουργίας αποσφαλμάτωσης]' \
            '--verbose[Παράκαμψη ρύθμισης λεπτομερούς λειτουργίας από το αρχείο διαμόρφωσης]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Εμβέλεια διαμόρφωσης (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Τύπος μεταφοράς (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Ορισμός μεταβλητής περιβάλλοντος (π.χ. -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Ορισμός κεφαλίδας WebSocket]:header:' \
            '--client-id[Αναγνωριστικό πελάτη OAuth για διακομιστές HTTP/SSE]:clientId:' \
            '--client-secret[Προτροπή για το μυστικό πελάτη OAuth (ή ορίστε τη μεταβλητή περιβάλλοντος MCP_CLIENT_SECRET)]' \
            '--callback-port[Σταθερή θύρα για την επανάκληση OAuth (για διακομιστές που απαιτούν προκαταχωρημένα URI ανακατεύθυνσης)]:port:' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Εμβέλεια διαμόρφωσης (local, user, project) - αφαίρεση από υπάρχουσα εμβέλεια εάν δεν καθοριστεί]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Εμβέλεια διαμόρφωσης (local, user, project)]:scope:(local user project)' \
            '--client-secret[Προτροπή για το μυστικό πελάτη OAuth (ή ορίστε τη μεταβλητή περιβάλλοντος MCP_CLIENT_SECRET)]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Εμβέλεια διαμόρφωσης (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]'
          ;;
        login)
          _arguments \
            '--no-browser[Εκτύπωση του URL εξουσιοδότησης αντί για άνοιγμα προγράμματος περιήγησης (για συνεδρίες SSH/χωρίς γραφικό περιβάλλον)]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:name:_claude_mcp_servers'
          ;;
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Επικύρωση προσθέτου ή δήλωσης αγοράς'
    'marketplace:Διαχείριση αγορών Claude Code'
    'list:Λίστα εγκατεστημένων προσθέτων'
    'details:Εμφάνιση απογραφής στοιχείων και προβλεπόμενου κόστους token για ένα πρόσθετο'
    'configure:Εμφάνιση των επιλογών ενός προσθέτου και ποιες δεν έχουν οριστεί, ή αποθήκευση τιμών από stdin'
    'install:Εγκατάσταση προσθέτου από διαθέσιμες αγορές'
    'i:Εγκατάσταση προσθέτου από διαθέσιμες αγορές (σύντομη μορφή του install)'
    'init:Δημιουργία σκελετού νέου προσθέτου (φορτώνεται αυτόματα στην επόμενη συνεδρία)'
    'new:Δημιουργία σκελετού νέου προσθέτου (ψευδώνυμο του init)'
    'uninstall:Απεγκατάσταση εγκατεστημένου προσθέτου'
    'remove:Απεγκατάσταση εγκατεστημένου προσθέτου (ψευδώνυμο του uninstall)'
    'enable:Ενεργοποίηση απενεργοποιημένου προσθέτου'
    'disable:Απενεργοποίηση ενεργοποιημένου προσθέτου'
    'update:Ενημέρωση προσθέτου στην πιο πρόσφατη έκδοση'
    'eval:Εκτέλεση περιπτώσεων eval σε ένα πρόσθετο και αναφορά βαθμολογημένων αποτελεσμάτων'
    'prune:Αφαίρεση αυτόματα εγκατεστημένων εξαρτήσεων που δεν χρειάζονται πλέον'
    'autoremove:Αφαίρεση αυτόματα εγκατεστημένων εξαρτήσεων που δεν χρειάζονται πλέον (ψευδώνυμο του prune)'
    'tag:Δημιουργία git tag {name}--v{version} για κυκλοφορία προσθέτου'
    'test:Εκτέλεση των δοκιμών ενός mod'
    'help:Εμφάνιση βοήθειας'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'plugin commands' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '--strict[Αντιμετώπιση των προειδοποιήσεων ως σφαλμάτων (κωδικός εξόδου 1)]' \
            '--json[Έξοδος της αναφοράς επικύρωσης ως JSON (ίδιοι κωδικοί εξόδου)]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Εμβέλεια εγκατάστασης]:scope:(user project local)' \
            '*--config[Ορισμός επιλογής userConfig που δηλώνεται στο manifest του προσθέτου (επαναλαμβανόμενο)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[Αποδοχή της εμφανιζόμενης εντολής που δηλώνεται από την αγορά χωρίς την προτροπή επιβεβαίωσης]' \
            '--json[Εκτύπωση μίας γραμμής αποτελέσματος αναγνώσιμης από μηχανή αντί για το μήνυμα για ανθρώπους]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Εμβέλεια εγκατάστασης]:scope:(user project local)' \
            '--keep-data[Διατήρηση του καταλόγου μόνιμων δεδομένων του προσθέτου]' \
            '--prune[Αφαίρεση επίσης αυτόματα εγκατεστημένων εξαρτήσεων που δεν χρειάζονται πλέον]' \
            '(-y --yes)'{-y,--yes}'[Παράλειψη της προτροπής επιβεβαίωσης του --prune]' \
            '--json[Εκτύπωση μίας γραμμής αποτελέσματος αναγνώσιμης από μηχανή αντί για το μήνυμα για ανθρώπους (όχι με --prune)]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Εμβέλεια εγκατάστασης]:scope:(user project local)' \
            '--json[Εκτύπωση μίας γραμμής αποτελέσματος αναγνώσιμης από μηχανή αντί για το μήνυμα για ανθρώπους]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Απενεργοποίηση όλων των ενεργοποιημένων προσθέτων]' \
            '(-s --scope)'{-s,--scope}'[Εμβέλεια εγκατάστασης]:scope:(user project local)' \
            '--json[Εκτύπωση μίας γραμμής αποτελέσματος αναγνώσιμης από μηχανή αντί για το μήνυμα για ανθρώπους]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Εμβέλεια εγκατάστασης]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Αποδοχή της εμφανιζόμενης εντολής που δηλώνεται από την αγορά χωρίς την προτροπή επιβεβαίωσης]' \
            '--json[Εκτύπωση μίας γραμμής αποτελέσματος αναγνώσιμης από μηχανή αντί για το μήνυμα για ανθρώπους]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Έξοδος ως JSON]' \
            '--available[Συμπερίληψη διαθέσιμων προσθέτων από αγορές (απαιτεί --json)]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Εκκαθάριση στην εμβέλεια]:scope:(user project local)' \
            '--dry-run[Λίστα όσων θα αφαιρούνταν χωρίς αφαίρεση]' \
            '(-y --yes)'{-y,--yes}'[Παράλειψη της προτροπής επιβεβαίωσης]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]'
          ;;
        configure)
          _arguments \
            '--json[Έξοδος ως JSON]' \
            '--values-stdin[Ανάγνωση τιμών επιλογών από stdin ως αντικείμενο JSON με συμβολοσειρές μίας γραμμής· οι επιλογές που παραλείπονται διατηρούν τις τιμές τους]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Περιγραφή manifest]:text:' \
            '--author[Όνομα συντάκτη (προεπιλογή: git config user.name)]:name:' \
            '--author-email[Email συντάκτη (προεπιλογή: git config user.email)]:email:' \
            '--with[Στοιχεία για τα οποία θα δημιουργηθεί επίσης σκελετός]:components:' \
            '(-f --force)'{-f,--force}'[Αντικατάσταση υπάρχοντος .claude-plugin/ στον προορισμό]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Φιλτράρισμα περιπτώσεων βάσει μοτίβου glob ονόματος]:glob:' \
            '*--tag[Φιλτράρισμα περιπτώσεων βάσει ετικέτας (επαναλαμβανόμενο)]:tag:' \
            '--runs[Παράκαμψη του αριθμού εκτελέσεων ανά περίπτωση (προεπιλογή: case.runs, αλλιώς 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Ταυτόχρονη εκτέλεση έως n εκτελέσεων πράκτορα (1-8· προεπιλογή 1)]:n:' \
            '--model[Παράκαμψη μοντέλου για όλες τις περιπτώσεις]:model:_claude_model_names' \
            '--judge-model[Παράκαμψη μοντέλου βαθμολογητή LLM (προεπιλογή: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Αυστηρό ανώτατο όριο κόστους· εάν επιτευχθεί, διακοπή και αναφορά μερικών αποτελεσμάτων (κωδικός εξόδου 2)]:usd:' \
            '--output-dir[Κατάλογος για το aggregate-result.json]:dir:_directories' \
            '--eval-dir[Όνομα καταλόγου (κάτω από το πρόσθετο) που περιέχει τις περιπτώσεις eval]:dir:' \
            '--json[Εκτύπωση του πλήρους αποτελέσματος εκτέλεσης ως JSON στο stdout ή εγγραφή του σε αυτό το αρχείο .json]::path:_files' \
            '--threshold[Έξοδος με κωδικό εξόδου 1 εάν η βαθμολογία οποιασδήποτε περίπτωσης είναι κάτω από αυτό το όριο (προεπιλογή: 1.0)]:threshold:' \
            '*--allow-tools[Παραχώρηση από τον χειριστή για εργαλεία με περιορισμένη πρόσβαση (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Εκτέλεση του scaffold_script κάθε περίπτωσης (εκτελεί bash που παρέχεται από τον συντάκτη με τον λογαριασμό σας· απενεργοποιημένο από προεπιλογή)]' \
            '(--scaffold)--no-scaffold[Ρητή παράλειψη του scaffold_script]' \
            '--trust-plugin[Δήλωση ότι εμπιστεύεστε αυτό το πρόσθετο και τη σουίτα eval του, με παράλειψη της προτροπής εμπιστοσύνης πρώτης εκτέλεσης (για CI)]' \
            '--ablation[Εκτέλεση ομάδας σύγκρισης αναφοράς χωρίς πρόσθετο και αναφορά της διαφοράς βαθμολογίας]:mode:(none with-without)' \
            '--mocks[Εικονικά υποκατάστατα για διακομιστές MCP, από το <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Με --mocks record: εκκίνηση επίσης των πραγματικών διεργασιών διακομιστών MCP που δεν έχουν εικονικό υποκατάστατο]' \
            '--keep-temp[Διατήρηση καταλόγων σκελετού για αποσφαλμάτωση]' \
            '--verbose[Καταγραφή συμβάντων ιχνηλάτησης ανά μήνυμα στο αρχείο καταγραφής αποσφαλμάτωσης]' \
            '--report[Εγγραφή της αυτόνομης αναφοράς HTML σε αυτή τη διαδρομή αντί για τον κατάλογο αποτελεσμάτων]:path:_files' \
            '(--no-publish)--publish-report[Απαίτηση επίσης δημοσίευσης της αναφοράς στο claude.ai]' \
            '(--publish-report)--no-publish[Διατήρηση της αναφοράς HTML μόνο τοπικά· παράλειψη δημοσίευσής της στο claude.ai]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Αποστολή (push) του tag στο --remote μετά τη δημιουργία του]' \
            '--dry-run[Εκτύπωση όσων θα λάμβαναν tag χωρίς δημιουργία του]' \
            '(-f --force)'{-f,--force}'[Παράλειψη των ελέγχων για μη καθαρό δέντρο εργασίας και για ήδη υπάρχον tag]' \
            '(-m --message)'{-m,--message}'[Μήνυμα σχολιασμού tag (χρησιμοποιήστε %s για την έκδοση)]:msg:' \
            '--remote[Απομακρυσμένο αποθετήριο για αποστολή με --push]:name:' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '::dir:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Προσθήκη αγοράς από URL, διαδρομή ή αποθετήριο GitHub'
    'list:Λίστα διαμορφωμένων αγορών'
    'remove:Αφαίρεση διαμορφωμένης αγοράς'
    'rm:Αφαίρεση διαμορφωμένης αγοράς (ψευδώνυμο του remove)'
    'update:Ενημέρωση αγοράς από την πηγή - ενημέρωση όλων εάν δεν καθοριστεί όνομα'
    'help:Εμφάνιση βοήθειας'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'marketplace commands' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '--sparse[Περιορισμός του checkout σε συγκεκριμένους καταλόγους μέσω git sparse-checkout (για monorepos)]:paths:' \
            '--scope[Πού θα δηλωθεί η αγορά]:scope:(user project local)' \
            '--claudeai[Προσθήκη της αγοράς με αυτό το όνομα που φιλοξενεί για εσάς το claude.ai]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Έξοδος ως JSON]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Αφαίρεση της δήλωσης αγοράς από συγκεκριμένη εμβέλεια ρυθμίσεων (παραλείψτε για αφαίρεση από κάθε εμβέλεια)]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}

_claude_install() {
  _arguments \
    '--force[Εξαναγκασμός εγκατάστασης ακόμα κι αν είναι ήδη εγκατεστημένο]' \
    '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
    '::target:(stable latest)'
}

_claude_agents() {
  _arguments \
    '*--add-dir[Πρόσθετος κατάλογος για επιτρεπόμενη πρόσβαση εργαλείων σε αποσταλμένες συνεδρίες]:directory:_directories' \
    '--agent[Προεπιλεγμένος πράκτορας για συνεδρίες που αποστέλλονται από την προβολή πρακτόρων]:agent:_claude_agent_names' \
    '--all[Με --json: συμπερίληψη επίσης ολοκληρωμένων συνεδριών παρασκηνίου]' \
    '--allow-dangerously-skip-permissions[Διαθεσιμότητα λειτουργίας παράκαμψης αδειών σε αποσταλμένες συνεδρίες]' \
    '--cwd[Εμφάνιση μόνο συνεδριών παρασκηνίου που ξεκίνησαν κάτω από τη διαδρομή]:path:_directories' \
    '--dangerously-skip-permissions[Ψευδώνυμο για --permission-mode bypassPermissions]' \
    '--effort[Προεπιλεγμένο επίπεδο προσπάθειας για αποσταλμένες συνεδρίες]:level:(low medium high xhigh max)' \
    '--json[Εκτύπωση ενεργών συνεδριών ως πίνακας JSON και έξοδος]' \
    '*--mcp-config[Διαμόρφωση διακομιστή MCP για εφαρμογή σε αποσταλμένες συνεδρίες]:config:' \
    '--model[Προεπιλεγμένο μοντέλο για συνεδρίες που αποστέλλονται από την προβολή πρακτόρων]:model:_claude_model_names' \
    '--permission-mode[Προεπιλεγμένη λειτουργία αδειών για αποσταλμένες συνεδρίες]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Φόρτωση προσθέτων από κατάλογο για την προβολή πρακτόρων και αποσταλμένες συνεδρίες]:path:_directories' \
    '--setting-sources[Λίστα διαχωρισμένη με κόμματα από πηγές ρυθμίσεων για φόρτωση (user, project, local)]:sources:' \
    '--settings[Αρχείο ρυθμίσεων ή συμβολοσειρά JSON για εφαρμογή]:file-or-json:_files' \
    '--strict-mcp-config[Χρήση μόνο διακομιστών MCP από --mcp-config σε αποσταλμένες συνεδρίες]' \
    '--restricted[Εκκίνηση αποσταλμένων συνεδριών σε περιορισμένη λειτουργία]' \
    '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Σύνδεση στον λογαριασμό σας Anthropic'
    'logout:Αποσύνδεση από τον λογαριασμό σας Anthropic'
    'status:Εμφάνιση κατάστασης ελέγχου ταυτότητας'
    'help:Εμφάνιση βοήθειας'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'auth commands' auth_commands
      ;;
    args)
      case $words[1] in
        login)
          _arguments \
            '--email[Προσυμπλήρωση διεύθυνσης email στη σελίδα σύνδεσης]:email:' \
            '--sso[Εξαναγκασμός ροής σύνδεσης SSO]' \
            '(--claudeai)--console[Χρήση του Anthropic Console (χρέωση βάσει χρήσης API) αντί για συνδρομή Claude]' \
            '(--console)--claudeai[Χρήση συνδρομής Claude (προεπιλογή)]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]'
          ;;
        status)
          _arguments \
            '(--text)--json[Έξοδος ως JSON (προεπιλογή)]' \
            '(--json)--text[Έξοδος ως κείμενο αναγνώσιμο από ανθρώπους]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Εκτύπωση της ισχύουσας διαμόρφωσης αυτόματης λειτουργίας ως JSON'
    'critique:Λήψη σχολίων AI για τους προσαρμοσμένους κανόνες αυτόματης λειτουργίας σας'
    'defaults:Εκτύπωση των προεπιλεγμένων κανόνων αυτόματης λειτουργίας ως JSON'
    'reset:Επαναφορά διαμόρφωσης αυτόματης λειτουργίας στις προεπιλογές αποστολής'
    'help:Εμφάνιση βοήθειας'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'auto-mode commands' auto_mode_commands
      ;;
    args)
      case $words[1] in
        critique)
          _arguments \
            '--model[Παράκαμψη του μοντέλου που χρησιμοποιείται]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]'
          ;;
        defaults)
          _arguments \
            '--label[Εμφάνιση μόνο κανόνων των οποίων η ετικέτα ξεκινά με αυτό το πρόθεμα (χωρίς διάκριση πεζών-κεφαλαίων)]:prefix:' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Παράλειψη της προτροπής επιβεβαίωσης]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]'
          ;;
        config)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Διαδρομή σε διαμόρφωση YAML πύλης]:path:_files' \
    '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Διαγραφή όλης της κατάστασης Claude Code για ένα έργο (απομαγνητοφωνήσεις, εργασίες, ιστορικό αρχείων, καταχώρηση διαμόρφωσης)'
    'help:Εμφάνιση βοήθειας'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'project commands' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '--dry-run[Λίστα όσων θα διαγράφονταν χωρίς να διαγραφεί τίποτα]' \
            '(-y --yes)'{-y,--yes}'[Παράλειψη της προτροπής επιβεβαίωσης]' \
            '(-i --interactive)'{-i,--interactive}'[Προτροπή για κάθε στοιχείο πριν από τη διαγραφή]' \
            '(1)--all[Διαγραφή κατάστασης για κάθε έργο (αμοιβαία αποκλειόμενο με διαδρομή)]' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Εκτύπωση του ακατέργαστου φορτίου bugs.json αντί για μορφοποιημένα ευρήματα]' \
    '--timeout[Μέγιστα λεπτά αναμονής για την ολοκλήρωση της αξιολόγησης (προεπιλογή: 45)]:minutes:' \
    '(--no-post)--post[Δημοσίευση των ευρημάτων της ολοκληρωμένης αξιολόγησης στο PR με τον λογαριασμό σας (μόνο για στόχους PR· ένα απλό σχόλιο, όχι αξιολόγηση)]' \
    '(--post)--no-post[Μη δημοσίευση των ευρημάτων στο PR (η προεπιλογή)]' \
    '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Επανεκκίνηση κάθε εκτελούμενης συνεδρίας παρασκηνίου]' \
    '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Απόρριψη επίσης των μη απεσταλμένων commits και των μη δεσμευμένων αλλαγών του worktree (δώστε το commit@worktree-id που ανέφερε προηγούμενο claude rm)]:commit@worktree-id:' \
    '--force-remove-worktree[Διαγραφή του καταλόγου worktree ακόμα κι αν το hook WorktreeRemove ή το git δεν μπόρεσε να τον αφαιρέσει (δώστε το worktree-id που ανέφερε προηγούμενο claude rm)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Εμφάνιση όσων θα εισάγονταν χωρίς να γραφτεί τίποτα]' \
    '--yes[Παράλειψη του διαδραστικού επιλογέα (σε περιβάλλοντα χωρίς γραφικό περιβάλλον, δώστε --yes=<digest> από την προεπισκόπηση του /import)]' \
    '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
