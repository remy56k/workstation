#!/usr/bin/env bash
# Menu de sélection d'hôtes SSH via fzf (style complet + aperçu commande/options à droite).
# Utilisable avec tmux display-popup.
#
# Variables d'environnement :
#   SSH_CONFIG      chemin du fichier de config SSH (défaut: ~/.ssh/config)
#   SSH_MENU_DEBUG  1 pour activer la trace (set -x) et les logs
#   SSH_MENU_LOG    fichier de log en mode debug (défaut: /tmp/ssh-hosts-menu.log)

set -uo pipefail

DEBUG="${SSH_MENU_DEBUG:-0}"
LOG_FILE="${SSH_MENU_LOG:-${TMPDIR:-/tmp}/ssh-hosts-menu.log}"

log() {
  [[ "$DEBUG" == 1 ]] || return 0
  printf '%(%F %T)T [%d] %s\n' -1 "$$" "$*" >>"$LOG_FILE"
}

die() {
  printf 'ssh-hosts: %s\n' "$*" >&2
  log "ERREUR: $*"
  # Dans un popup tmux, laisser le temps de lire le message avant la fermeture.
  if [[ -n "${TMUX:-}" && -t 0 && -t 1 ]]; then
    read -rsn1 -p 'Appuyez sur une touche pour fermer…'
  fi
  exit 1
}

if [[ "$DEBUG" == 1 ]]; then
  exec {xtrace_fd}>>"$LOG_FILE"
  export BASH_XTRACEFD="$xtrace_fd"
  PS4='+ [${BASH_SOURCE##*/}:${LINENO}] '
  set -x
  trap 'log "commande en échec (rc=$?) ligne $LINENO: $BASH_COMMAND"' ERR
fi

CONFIG="${SSH_CONFIG:-$HOME/.ssh/config}"
[[ -r "$CONFIG" ]] || die "Config SSH introuvable ou illisible: $CONFIG"

SSH_CMD=(ssh)

SCRIPT="${BASH_SOURCE[0]}"
[[ "$SCRIPT" != /* ]] && SCRIPT="$PWD/$SCRIPT"

_ssh_menu_host_from_line() {
  local line selected="$1"
  line="${selected#*  }"
  [[ "$line" == "$selected" ]] && line="$selected"
  line="${line%% (*}"
  echo "${line//$'\r'/}"
}

# Liste les entrées "groupe<TAB>hôte<TAB>user<TAB>hostname" puis les met en forme.
# Les champs sont séparés par des tabulations pour supporter les groupes multi-mots.
_list_hosts() {
  awk '
    BEGIN { user = "-"; hostname = "-"; group = "" }
    # host_group est figé à la lecture de la ligne Host : un commentaire
    # rencontré ensuite (groupe suivant) ne doit pas s affecter au bloc courant.
    function flush_hosts(   n, i, a) {
      if (hosts == "") return
      n = split(hosts, a, " ")
      for (i = 1; i <= n; i++)
        if (a[i] != "" && a[i] !~ /[*?]/)
          print host_group "\t" a[i] "\t" user "\t" hostname
    }
    # Config éditée sous Windows : retirer le CR final (CRLF) avant analyse.
    { sub(/\r$/, "") }
    /^[[:space:]]*#/ {
      group = $0
      sub(/^[[:space:]]*#+[[:space:]]*/, "", group)
      gsub(/[[:space:]]+/, " ", group)
      sub(/[[:space:]]+$/, "", group)
      next
    }
    tolower($1) == "host" {
      flush_hosts()
      host_group = group
      hosts = ""
      for (i = 2; i <= NF; i++) if ($i !~ /[*?]/) hosts = hosts $i " "
      user = "-"; hostname = "-"
      next
    }
    tolower($1) == "user"     { user = $2; next }
    tolower($1) == "hostname" { hostname = $2; next }
    END { flush_hosts() }
  ' "$CONFIG" | awk -F '\t' '
    $1 != "" { print $1 "  " $2 " (" $3 "@" $4 ")"; next }
    { print $2 " (" $3 "@" $4 ")" }
  '
}

# Liste les entrées (rechargement ctrl-r).
if [[ "${1:-}" == "--list-hosts" ]]; then
  _list_hosts
  exit 0
fi

if [[ "${1:-}" == "--header-line" ]]; then
  shift
  selected="$*"
  host="$(_ssh_menu_host_from_line "$selected")"
  if [[ -z "$host" ]]; then
    exit 0
  fi

  # Résumé visuel pour la zone bleue de gauche.
  awk -v target="$host" '
    function host_matches(line,   n, i, parts) {
      n = split(line, parts, /[[:space:]]+/)
      for (i = 1; i <= n; i++)
        if (parts[i] == target) return 1
      return 0
    }

    function is_ipv4(ip,   n, a, i) {
      n = split(ip, a, ".")
      if (n != 4) return 0
      for (i = 1; i <= 4; i++) {
        if (a[i] !~ /^[0-9]+$/) return 0
        if (a[i] < 0 || a[i] > 255) return 0
      }
      return 1
    }

    function is_private_ipv4(ip,   a, oct2) {
      if (!is_ipv4(ip)) return 0
      split(ip, a, ".")
      oct2 = a[2]
      if (a[1] == 10) return 1
      if (a[1] == 127) return 1
      if (a[1] == 169 && oct2 == 254) return 1
      if (a[1] == 192 && oct2 == 168) return 1
      if (a[1] == 172 && oct2 >= 16 && oct2 <= 31) return 1
      return 0
    }

    function emit_summary(   status, label) {
      status = ""
      if (has_proxyjump) status = status " 🪜 ProxyJump"
      if (has_forward)   status = status " ↔️ PortForward"
      if (has_root)      status = status " 👑 ROOT"

      if (hostname != "") {
        if (is_ipv4(hostname)) {
          label = is_private_ipv4(hostname) ? "🏠 IP privée" : "🌍 IP publique"
        } else {
          label = "🌐 HostName"
        }
        status = status " " label
      }

      done = 1
      print status
      exit
    }

    { sub(/\r$/, "") }

    tolower($1) == "host" {
      if (printing) emit_summary()
      if (host_matches($0)) {
        printing = 1
      }
      next
    }

    printing {
      key = tolower($1)
      if (key == "proxyjump") has_proxyjump = 1
      if (key == "localforward" || key == "remoteforward" || key == "dynamicforward") has_forward = 1
      if (key == "user" && $2 == "root") has_root = 1
      if (key == "hostname") hostname = $2
    }

    END {
      if (printing && !done) emit_summary()
    }
  ' "$CONFIG"
  exit 0
fi

if [[ "${1:-}" == "--preview-line" ]]; then
  shift
  selected="$*"
  host="$(_ssh_menu_host_from_line "$selected")"
  if [[ -z "$host" ]]; then
    exit 0
  fi

  # Affiche uniquement le bloc Host tel qu'il est écrit dans le fichier SSH.
  awk -v target="$host" '
    function host_matches(line,   n, i, parts) {
      n = split(line, parts, /[[:space:]]+/)
      for (i = 1; i <= n; i++)
        if (parts[i] == target) return 1
      return 0
    }

    { sub(/\r$/, "") }

    tolower($1) == "host" {
      if (printing) exit
      if (host_matches($0)) {
        printing = 1
        print
      }
      next
    }

    printing {
      if ($0 ~ /^[[:space:]]*#/) next
      print
    }
  ' "$CONFIG"
  exit 0
fi

command -v fzf >/dev/null 2>&1 || die "fzf est requis mais introuvable dans le PATH"

list_for_fzf=$(_list_hosts)
[[ -n "$list_for_fzf" ]] || die "Aucun hôte trouvé dans $CONFIG"
log "config=$CONFIG, $(wc -l <<<"$list_for_fzf") hôte(s) listé(s)"

SCRIPT_Q=$(printf '%q' "$SCRIPT")
CONFIG_Q=$(printf '%q' "$CONFIG")
# Aperçu : fzf remplace {} par la ligne courante déjà single-quotée, on la
# passe donc telle quelle en argument (pas de heredoc : il conserverait les
# quotes ajoutées par fzf et casserait l'extraction de l'hôte).
# SSH_CONFIG est propagé explicitement : les sous-commandes ne doivent pas
# dépendre d'un export fait (ou non) par l'appelant.
PREVIEW_CMD="SSH_CONFIG=$CONFIG_Q bash $SCRIPT_Q --preview-line {}"
# En-tête bleu à gauche : résumé visuel avec emojis.
HEADER_CMD="SSH_CONFIG=$CONFIG_Q bash $SCRIPT_Q --header-line {}"

reload_cmd="SSH_CONFIG=$CONFIG_Q bash $SCRIPT_Q --list-hosts"

selected=$(
  printf '%s\n' "$list_for_fzf" | fzf \
    --style full \
    --height 85% \
    --layout reverse \
    --border --padding 1,2 \
    --border-label ' SSH ' \
    --input-label ' Recherche ' \
    --header-label ' Hôte ' \
    --list-label ' Hôtes ' \
    --preview-label ' Commande & options ' \
    --preview-window 'right:55%:wrap' \
    --preview "$PREVIEW_CMD" \
    --bind 'result:transform-list-label:
      if [[ -z $FZF_QUERY ]]; then
        echo " $FZF_MATCH_COUNT hôtes "
      else
        echo " $FZF_MATCH_COUNT correspondance(s) pour [$FZF_QUERY] "
      fi
      ' \
    --bind 'focus:transform-preview-label:[[ -n {} ]] && printf " Bloc SSH "' \
    --bind "focus:+transform-header:$HEADER_CMD" \
    --bind "ctrl-r:change-list-label( Rechargement )+reload($reload_cmd)" \
    --color 'border:#aaaaaa,label:#cccccc' \
    --color 'preview-border:#9999cc,preview-label:#ccccff' \
    --color 'list-border:#669966,list-label:#99cc99' \
    --color 'input-border:#996666,input-label:#ffcccc' \
    --color 'header-border:#6699cc,header-label:#99ccff' \
    --prompt 'SSH › '
)
fzf_rc=$?
case $fzf_rc in
  0) ;;
  1 | 130) exit 0 ;; # aucune correspondance / annulé (ESC, ctrl-c)
  *) die "fzf a échoué (code $fzf_rc)" ;;
esac
[[ -z "$selected" ]] && exit 0

host="$(_ssh_menu_host_from_line "$selected")"
[[ -z "$host" ]] && exit 0
log "sélection: [$selected] → hôte [$host]"

# Commande SSH correctement échappée (hôte compris).
printf -v ssh_line '%q ' "${SSH_CMD[@]}" "$host"
ssh_line="${ssh_line% }"
log "commande: $ssh_line"

if [[ -n "${TMUX:-}" ]]; then
  win_id=$(tmux new-window -P -F '#{window_id}' -n "$host" "${SHELL:-bash}") \
    || die "tmux new-window a échoué"
  # La commande est tapée mais PAS exécutée : relire/ajuster puis valider avec Entrée.
  tmux send-keys -t "$win_id" "$ssh_line ; exit"
  tmux select-window -t "$win_id"
else
  exec "${SSH_CMD[@]}" "$host"
fi
