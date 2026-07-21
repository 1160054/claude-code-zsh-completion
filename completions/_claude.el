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
    'mcp:Διαμόρφωση και διαχείριση διακομιστών MCP'
    'plugin:Διαχείριση προσθέτων Claude Code'
    'agents:Διαχείριση πρακτόρων παρασκηνίου'
    'auth:Διαχείριση ελέγχου ταυτότητας'
    'auto-mode:Επιθεώρηση ή επαναφορά διαμόρφωσης ταξινομητή αυτόματης λειτουργίας'
    'gateway:Εκτέλεση της εταιρικής πύλης ελέγχου ταυτότητας/τηλεμετρίας'
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
    '--max-budget-usd[Μέγιστο ποσό σε δολάρια για δαπάνη σε κλήσεις API (μόνο --print)]:amount:'
    '--replay-user-messages[Επαναποστολή μηνυμάτων χρήστη από stdin σε stdout για επιβεβαίωση]'
    '--allowed-tools[Λίστα διαχωρισμένη με κόμματα ή κενά με ονόματα επιτρεπόμενων εργαλείων (π.χ. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Λίστα διαχωρισμένη με κόμματα ή κενά με ονόματα επιτρεπόμενων εργαλείων (μορφή camelCase)]:tools:'
    '--tools[Καθορισμός λίστας διαθέσιμων εργαλείων από το ενσωματωμένο σύνολο. Μόνο λειτουργία εκτύπωσης]:tools:'
    '--disallowed-tools[Λίστα διαχωρισμένη με κόμματα ή κενά με ονόματα μη επιτρεπόμενων εργαλείων (π.χ. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Λίστα διαχωρισμένη με κόμματα ή κενά με ονόματα μη επιτρεπόμενων εργαλείων (μορφή camelCase)]:tools:'
    '--mcp-config[Φόρτωση διακομιστών MCP από αρχείο JSON ή συμβολοσειρά (διαχωρισμένα με κενά)]:configs:'
    '--system-prompt[Προτροπή συστήματος για χρήση στη συνεδρία]:prompt:'
    '--append-system-prompt[Προσάρτηση προτροπής συστήματος στην προεπιλεγμένη προτροπή συστήματος]:prompt:'
    '--permission-mode[Λειτουργία αδειών για χρήση στη συνεδρία]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Συνέχιση της πιο πρόσφατης συνομιλίας]'
    '(-r --resume)'{-r,--resume}'[Συνέχιση συνομιλίας - καθορίστε αναγνωριστικό συνεδρίας ή επιλέξτε διαδραστικά]:sessionId:_claude_sessions'
    '--fork-session[Δημιουργία νέου αναγνωριστικού συνεδρίας αντί επαναχρησιμοποίησης του αρχικού κατά τη συνέχιση (με --resume ή --continue)]'
    '--no-session-persistence[Απενεργοποίηση διατήρησης συνεδρίας - οι συνεδρίες δεν θα αποθηκεύονται (μόνο --print)]'
    '--model[Μοντέλο για τρέχουσα συνεδρία. Καθορίστε ψευδώνυμο για το πιο πρόσφατο μοντέλο (π.χ. '\''sonnet'\'' ή '\''opus'\'')]:model:'
    '--agent[Πράκτορας για την τρέχουσα συνεδρία. Παρακάμπτει τη ρύθμιση '\''agent'\'']:agent:'
    '--betas[Κεφαλίδες beta για συμπερίληψη σε αιτήματα API (μόνο χρήστες κλειδιού API)]:betas:'
    '--fallback-model[Ενεργοποίηση αυτόματης εναλλακτικής λύσης σε καθορισμένο μοντέλο όταν το προεπιλεγμένο μοντέλο είναι υπερφορτωμένο (μόνο --print)]:model:'
    '--settings[Διαδρομή σε αρχείο JSON ρυθμίσεων ή συμβολοσειρά JSON για φόρτωση πρόσθετων ρυθμίσεων]:file-or-json:_files'
    '--add-dir[Πρόσθετοι κατάλογοι για επιτρεπόμενη πρόσβαση εργαλείων]:directories:_directories'
    '--ide[Αυτόματη σύνδεση σε IDE κατά την εκκίνηση εάν είναι διαθέσιμο ακριβώς ένα έγκυρο IDE]'
    '--strict-mcp-config[Χρήση μόνο διακομιστών MCP από --mcp-config και αγνόηση όλων των άλλων ρυθμίσεων MCP]'
    '--session-id[Συγκεκριμένο αναγνωριστικό συνεδρίας για χρήση στη συνομιλία (πρέπει να είναι έγκυρο UUID)]:uuid:'
    '--agents[Αντικείμενο JSON που ορίζει προσαρμοσμένους πράκτορες]:json:'
    '--setting-sources[Λίστα διαχωρισμένη με κόμματα από πηγές ρυθμίσεων για φόρτωση (user, project, local)]:sources:'
    '--plugin-dir[Κατάλογος για φόρτωση προσθέτων μόνο για αυτή τη συνεδρία (επαναλαμβανόμενο)]:paths:_directories'
    '--disable-slash-commands[Απενεργοποίηση όλων των εντολών slash]'
    '(--bg --background)'{--bg,--background}'[Εκκίνηση της συνεδρίας ως πράκτορας παρασκηνίου και άμεση επιστροφή]'
    '(-w --worktree)'{-w,--worktree}'[Δημιουργία νέου git worktree για αυτή τη συνεδρία (προαιρετικά καθορίστε όνομα)]::name:'
    '--tmux[Δημιουργία συνεδρίας tmux για το worktree (απαιτεί --worktree)]'
    '(-n --name)'{-n,--name}'[Ορισμός εμφανιζόμενου ονόματος για αυτή τη συνεδρία]:name:'
    '--effort[Επίπεδο προσπάθειας για την τρέχουσα συνεδρία]:level:(low medium high xhigh max)'
    '--debug-file[Εγγραφή αρχείων καταγραφής αποσφαλμάτωσης σε συγκεκριμένη διαδρομή αρχείου (ενεργοποιεί έμμεσα τη λειτουργία αποσφαλμάτωσης)]:path:_files'
    '--from-pr[Συνέχιση συνεδρίας συνδεδεμένης με PR βάσει αριθμού/URL, ή άνοιγμα διαδραστικού επιλογέα]::value:'
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
        login|logout)
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
    'install:Εγκατάσταση προσθέτου από διαθέσιμες αγορές'
    'i:Εγκατάσταση προσθέτου από διαθέσιμες αγορές (σύντομη μορφή του install)'
    'init:Δημιουργία σκελετού νέου προσθέτου (φορτώνεται αυτόματα στην επόμενη συνεδρία)'
    'uninstall:Απεγκατάσταση εγκατεστημένου προσθέτου'
    'remove:Απεγκατάσταση εγκατεστημένου προσθέτου (ψευδώνυμο του uninstall)'
    'enable:Ενεργοποίηση απενεργοποιημένου προσθέτου'
    'disable:Απενεργοποίηση ενεργοποιημένου προσθέτου'
    'update:Ενημέρωση προσθέτου στην πιο πρόσφατη έκδοση'
    'eval:Εκτέλεση περιπτώσεων eval σε ένα πρόσθετο και αναφορά βαθμολογημένων αποτελεσμάτων'
    'prune:Αφαίρεση αυτόματα εγκατεστημένων εξαρτήσεων που δεν χρειάζονται πλέον'
    'tag:Δημιουργία git tag {name}--v{version} για κυκλοφορία προσθέτου'
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
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Εμβέλεια εγκατάστασης]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Εμβέλεια εγκατάστασης]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Εμβέλεια εγκατάστασης]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Εμβέλεια εγκατάστασης]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:path:_files'
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
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]'
          ;;
        remove|rm)
          _arguments \
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
    '--agent[Προεπιλεγμένος πράκτορας για συνεδρίες που αποστέλλονται από την προβολή πρακτόρων]:agent:' \
    '--all[Με --json: συμπερίληψη επίσης ολοκληρωμένων συνεδριών παρασκηνίου]' \
    '--allow-dangerously-skip-permissions[Διαθεσιμότητα λειτουργίας παράκαμψης αδειών σε αποσταλμένες συνεδρίες]' \
    '--cwd[Εμφάνιση μόνο συνεδριών παρασκηνίου που ξεκίνησαν κάτω από τη διαδρομή]:path:_directories' \
    '--dangerously-skip-permissions[Ψευδώνυμο για --permission-mode bypassPermissions]' \
    '--effort[Προεπιλεγμένο επίπεδο προσπάθειας για αποσταλμένες συνεδρίες]:level:(low medium high xhigh max)' \
    '--json[Εκτύπωση ενεργών συνεδριών ως πίνακας JSON και έξοδος]' \
    '*--mcp-config[Διαμόρφωση διακομιστή MCP για εφαρμογή σε αποσταλμένες συνεδρίες]:config:' \
    '--model[Προεπιλεγμένο μοντέλο για συνεδρίες που αποστέλλονται από την προβολή πρακτόρων]:model:' \
    '--permission-mode[Προεπιλεγμένη λειτουργία αδειών για αποσταλμένες συνεδρίες]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Φόρτωση προσθέτων από κατάλογο για την προβολή πρακτόρων και αποσταλμένες συνεδρίες]:path:_directories' \
    '--setting-sources[Λίστα διαχωρισμένη με κόμματα από πηγές ρυθμίσεων για φόρτωση (user, project, local)]:sources:' \
    '--settings[Αρχείο ρυθμίσεων ή συμβολοσειρά JSON για εφαρμογή]:file-or-json:_files' \
    '--strict-mcp-config[Χρήση μόνο διακομιστών MCP από --mcp-config σε αποσταλμένες συνεδρίες]' \
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
        login|logout|status)
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
        config|critique|defaults|reset)
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
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Εκτύπωση του ακατέργαστου φορτίου bugs.json αντί για μορφοποιημένα ευρήματα]' \
    '--timeout[Μέγιστα λεπτά αναμονής για την ολοκλήρωση της αξιολόγησης]:minutes:' \
    '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας για εντολή]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
