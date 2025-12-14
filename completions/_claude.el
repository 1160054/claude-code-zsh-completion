#compdef claude

# Dynamic completion functions
_claude_mcp_servers() {
  local servers config_file
  local -a server_list

  # Read directly from config files instead of running 'claude mcp list'
  for config_file in ~/.claude/mcp.json ~/.claude.json ~/.config/claude/mcp.json; do
    [[ -f "$config_file" ]] || continue

    # Extract server names from JSON (mcpServers section)
    servers=$(grep -oP '(?<="mcpServers":\s*\{)[^}]+' "$config_file" 2>/dev/null | \
              grep -oP '(?<=")[^"]+(?="\s*:)' 2>/dev/null)

    [[ -n "$servers" ]] && server_list+=(${(f)servers})
  done

  # Fallback to claude mcp list if config parsing fails
  if [[ ${#server_list[@]} -eq 0 ]]; then
    server_list=(${(f)"$(claude mcp list 2>/dev/null | sed -n 's/^\([^:]*\):.*/\1/p' | grep -v '^Checking')"})
  fi

  compadd -l -a server_list
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

  compadd -l -a plugins
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

  compadd -l -a sessions
}

_claude() {
  local curcontext="$curcontext" state line
  typeset -A opt_args

  local -a main_commands
  main_commands=(
    'mcp:Διαμόρφωση και διαχείριση διακομιστών MCP'
    'plugin:Διαχείριση προσθέτων Claude Code'
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
    '--mcp-debug[Παρωχημένο. Χρησιμοποιήστε --debug αντί αυτού] Ενεργοποίηση λειτουργίας αποσφαλμάτωσης MCP (εμφανίζει σφάλματα διακομιστή MCP)]'
    '--dangerously-skip-permissions[Παράκαμψη όλων των ελέγχων αδειών. Συνιστάται μόνο για απομονωμένα περιβάλλοντα χωρίς πρόσβαση στο διαδίκτυο]'
    '--allow-dangerously-skip-permissions[Ενεργοποίηση επιλογής παράκαμψης ελέγχων αδειών χωρίς ενεργοποίηση από προεπιλογή]'
    '--replay-user-messages[Επαναποστολή μηνυμάτων χρήστη από stdin σε stdout για επιβεβαίωση]'
    '--allowed-tools[Λίστα διαχωρισμένη με κόμματα ή κενά με ονόματα επιτρεπόμενων εργαλείων (π.χ. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Λίστα διαχωρισμένη με κόμματα ή κενά με ονόματα επιτρεπόμενων εργαλείων (μορφή camelCase)]:tools:'
    '--tools[Καθορισμός λίστας διαθέσιμων εργαλείων από το ενσωματωμένο σύνολο. Μόνο λειτουργία εκτύπωσης]:tools:'
    '--disallowed-tools[Λίστα διαχωρισμένη με κόμματα ή κενά με ονόματα μη επιτρεπόμενων εργαλείων (π.χ. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Λίστα διαχωρισμένη με κόμματα ή κενά με ονόματα μη επιτρεπόμενων εργαλείων (μορφή camelCase)]:tools:'
    '--mcp-config[Φόρτωση διακομιστών MCP από αρχείο JSON ή συμβολοσειρά (διαχωρισμένα με κενά)]:configs:'
    '--system-prompt[Προτροπή συστήματος για χρήση στη συνεδρία]:prompt:'
    '--append-system-prompt[Προσάρτηση προτροπής συστήματος στην προεπιλεγμένη προτροπή συστήματος]:prompt:'
    '--permission-mode[Λειτουργία αδειών για χρήση στη συνεδρία]:mode:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Συνέχιση της πιο πρόσφατης συνομιλίας]'
    '(-r --resume)'{-r,--resume}'[Συνέχιση συνομιλίας - καθορίστε αναγνωριστικό συνεδρίας ή επιλέξτε διαδραστικά]:sessionId:_claude_sessions'
    '--fork-session[Δημιουργία νέου αναγνωριστικού συνεδρίας αντί επαναχρησιμοποίησης του αρχικού κατά τη συνέχιση (με --resume ή --continue)]'
    '--model[Μοντέλο για τρέχουσα συνεδρία. Καθορίστε ψευδώνυμο για το πιο πρόσφατο μοντέλο (π.χ. '\''sonnet'\'' ή '\''opus'\'')]:model:'
    '--fallback-model[Ενεργοποίηση αυτόματης εναλλακτικής λύσης σε καθορισμένο μοντέλο όταν το προεπιλεγμένο μοντέλο είναι υπερφορτωμένο (μόνο --print)]:model:'
    '--settings[Διαδρομή σε αρχείο JSON ρυθμίσεων ή συμβολοσειρά JSON για φόρτωση πρόσθετων ρυθμίσεων]:file-or-json:_files'
    '--add-dir[Πρόσθετοι κατάλογοι για επιτρεπόμενη πρόσβαση εργαλείων]:directories:_directories'
    '--ide[Αυτόματη σύνδεση σε IDE κατά την εκκίνηση εάν είναι διαθέσιμο ακριβώς ένα έγκυρο IDE]'
    '--strict-mcp-config[Χρήση μόνο διακομιστών MCP από --mcp-config και αγνόηση όλων των άλλων ρυθμίσεων MCP]'
    '--session-id[Συγκεκριμένο αναγνωριστικό συνεδρίας για χρήση στη συνομιλία (πρέπει να είναι έγκυρο UUID)]:uuid:'
    '--agents[Αντικείμενο JSON που ορίζει προσαρμοσμένους πράκτορες]:json:'
    '--setting-sources[Λίστα διαχωρισμένη με κόμματα από πηγές ρυθμίσεων για φόρτωση (user, project, local)]:sources:'
    '--plugin-dir[Κατάλογος για φόρτωση προσθέτων μόνο για αυτή τη συνεδρία (επαναλαμβανόμενο)]:paths:_directories'
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
        setup-token|doctor|update)
          _message "no arguments"
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
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Επικύρωση προσθέτου ή δήλωσης αγοράς'
    'marketplace:Διαχείριση αγορών Claude Code'
    'install:Εγκατάσταση προσθέτου από διαθέσιμες αγορές'
    'i:Εγκατάσταση προσθέτου από διαθέσιμες αγορές (σύντομη μορφή του install)'
    'uninstall:Απεγκατάσταση εγκατεστημένου προσθέτου'
    'remove:Απεγκατάσταση εγκατεστημένου προσθέτου (ψευδώνυμο του uninstall)'
    'enable:Ενεργοποίηση απενεργοποιημένου προσθέτου'
    'disable:Απενεργοποίηση ενεργοποιημένου προσθέτου'
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
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Εμφάνιση βοήθειας]' \
            '1:plugin:_claude_installed_plugins'
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

(( $+_comps[claude] )) || compdef _claude claude
