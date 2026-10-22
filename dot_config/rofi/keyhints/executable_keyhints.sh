#!/usr/bin/env bash
# shellcheck shell=bash
# Fiche des raccourcis Sway, générée depuis la configuration.
# Lit les bindsym de la config principale et de tous ses include,
# dans l'ordre où Sway les charge. Les raccourcis définis sous
# ~/.config/sway (niveau utilisateur) sont marqués d'une icône.
#
# Usage : keyhints.sh [--custom] [--print]
#   --custom  n'afficher que les raccourcis perso
#   --print   écrire la fiche dans le terminal au lieu d'ouvrir Rofi
#
# Dans Rofi : taper pour filtrer.

set -euo pipefail

dir="${HOME}/.config/rofi/keyhints"
theme="${dir}/menu.rasi"
user_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/sway"

only_custom=0
print_only=0
for arg in "$@"; do
    case "$arg" in
        --custom) only_custom=1 ;;
        --print)  print_only=1 ;;
        *) printf 'Option inconnue : %s\n' "$arg" >&2; exit 2 ;;
    esac
done

# Même ordre de recherche que Sway.
main_config=""
for f in "${user_dir}/config" "${HOME}/.sway/config" /etc/sway/config; do
    if [[ -r "$f" ]]; then main_config="$f"; break; fi
done
if [[ -z "$main_config" ]]; then
    printf 'Aucune configuration Sway trouvée.\n' >&2
    exit 1
fi

read -r -d '' parser <<'AWK' || true
# Sortie : une ligne par raccourci, « texte TAB perso ».

function cmp_len(i1, v1, i2, v2) { return length(i2) - length(i1) }

# Remplace les $variables, la plus longue d'abord, comme Sway.
function expand(s,   names, n, i, name, p, out) {
    n = asorti(vars, names, "cmp_len")
    for (i = 1; i <= n; i++) {
        name = names[i]
        out = ""
        while ((p = index(s, name)) > 0) {
            out = out substr(s, 1, p - 1) vars[name]
            s = substr(s, p + length(name))
        }
        s = out s
    }
    return s
}

function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }

function unquote(s) {
    s = trim(s)
    if (s ~ /^'.*'$/ || s ~ /^".*"$/) s = substr(s, 2, length(s) - 2)
    return s
}

function current_mode(   i) {
    for (i = depth; i > 0; i--) if (kind[i] == "mode") return modename[i]
    return "default"
}

function in_other_block(   i) {
    for (i = 1; i <= depth; i++) if (kind[i] == "other") return 1
    return 0
}

function add_binding(type, key, cmd,   mode, id) {
    mode = current_mode()
    key = expand(key)
    id = mode SUBSEP type SUBSEP tolower(key)
    if (!(id in order)) { order[id] = ++count; ids[count] = id }
    B_mode[id] = mode
    B_type[id] = type
    B_key[id] = key
    B_raw[id] = cmd
    B_cmd[id] = expand(cmd)
    B_custom[id] = is_custom
    B_comment[id] = comment
    delete removed[id]
}

# Les chemins d'include passent par le shell, comme le wordexp de Sway.
function include(spec, from,   cmd, f, dir) {
    spec = unquote(spec)
    dir = from; sub(/\/[^\/]*$/, "", dir)
    if (spec !~ /^[\/$~]/) spec = dir "/" spec
    cmd = "for f in " spec "; do [ -f \"$f\" ] && printf '%s\\n' \"$f\"; done"
    while ((cmd | getline f) > 0) inc_list[++inc_n] = f
    close(cmd)
}

function parse(file,   line, buf, saved_depth, saved_custom, first, last, i) {
    if (file in parsing) return
    parsing[file] = 1
    saved_depth = depth
    saved_custom = is_custom
    is_custom = (index(file, user_dir "/") == 1)
    comment = ""
    buf = ""
    while ((getline line < file) > 0) {
        if (line ~ /\\[ \t]*$/) {
            sub(/\\[ \t]*$/, "", line)
            buf = buf line " "
            continue
        }
        line = buf line
        buf = ""
        handle(trim(line), file)
    }
    close(file)
    depth = saved_depth
    is_custom = saved_custom
    delete parsing[file]
}

function handle(line, file,   w, s, key, name, flags, type, first, last, i) {
    if (line == "") { comment = ""; return }

    if (line ~ /^#/) {
        sub(/^#+[ \t]*/, "", line)
        if (comment == "" && line != "") comment = line
        return
    }

    if (line == "}") { if (depth > 0) depth--; comment = ""; return }

    split(line, w, /[ \t]+/)

    if (line ~ /\{$/) {
        depth++
        if (w[1] == "mode") {
            name = line
            sub(/^mode[ \t]+/, "", name)
            sub(/[ \t]*\{$/, "", name)
            sub(/^--pango_markup[ \t]+/, "", name)
            kind[depth] = "mode"
            modename[depth] = unquote(expand(name))
        } else if (w[1] == "bindsym" || w[1] == "bindcode") {
            kind[depth] = "bind"
            bindtype[depth] = w[1]
        } else {
            kind[depth] = "other"
        }
        comment = ""
        return
    }

    if (in_other_block()) { comment = ""; return }

    # Ligne « TOUCHE COMMANDE » dans un bloc bindsym { … }.
    if (depth > 0 && kind[depth] == "bind") {
        key = w[1]
        s = line
        sub(/^[^ \t]+[ \t]+/, "", s)
        add_binding(bindtype[depth], key, s)
        comment = ""
        return
    }

    if (w[1] == "bindsym" || w[1] == "bindcode") {
        s = line
        sub(/^[^ \t]+[ \t]+/, "", s)
        while (s ~ /^--/) sub(/^--[^ \t]+[ \t]+/, "", s)
        key = s
        sub(/[ \t].*$/, "", key)
        sub(/^[^ \t]+[ \t]*/, "", s)
        add_binding(w[1], key, s)
    } else if (w[1] == "unbindsym" || w[1] == "unbindcode") {
        s = line
        sub(/^[^ \t]+[ \t]+/, "", s)
        while (s ~ /^--/) sub(/^--[^ \t]+[ \t]+/, "", s)
        sub(/[ \t].*$/, "", s)
        type = (w[1] == "unbindsym") ? "bindsym" : "bindcode"
        removed[current_mode() SUBSEP type SUBSEP tolower(expand(s))] = 1
    } else if (w[1] == "set" && w[2] ~ /^\$/) {
        s = line
        sub(/^set[ \t]+[^ \t]+[ \t]*/, "", s)
        vars[w[2]] = expand(s)
    } else if (w[1] == "include") {
        s = line
        sub(/^include[ \t]+/, "", s)
        first = inc_n + 1
        include(expand(s), file)
        last = inc_n
        for (i = first; i <= last; i++) parse(inc_list[i])
    }
    comment = ""
}

# Description en français des commandes connues.
function describe(raw, cmd) {
    if (raw ~ /^exec[ \t]+\$term$/)                   return "Ouvrir un terminal"
    if (raw ~ /^exec[ \t]+\$menu$/)                   return "Lancer une application"
    if (cmd ~ /^kill$/)                               return "Fermer la fenêtre"
    if (cmd ~ /^reload$/)                             return "Recharger la configuration"
    if (cmd ~ /^exit$/ || cmd ~ /swaymsg exit/)       return "Quitter la session"
    if (cmd ~ /^focus (left|right|up|down)$/)         return "Aller à la fenêtre d'à côté"
    if (cmd ~ /^move (left|right|up|down)/)           return "Déplacer la fenêtre"
    if (cmd ~ /^move (container |window )?(to )?workspace/) return "Envoyer la fenêtre sur un bureau"
    if (cmd ~ /^workspace (number )?[0-9]+$/)         return "Changer de bureau"
    if (cmd ~ /^workspace (next|prev)/)               return "Bureau suivant / précédent"
    if (cmd ~ /^splith$/)                             return "Diviser horizontalement"
    if (cmd ~ /^splitv$/)                             return "Diviser verticalement"
    if (cmd ~ /^layout stacking$/)                    return "Disposition empilée"
    if (cmd ~ /^layout tabbed$/)                      return "Disposition en onglets"
    if (cmd ~ /^layout toggle split$/)                return "Alterner la division"
    if (cmd ~ /^fullscreen/)                          return "Plein écran"
    if (cmd ~ /^floating toggle$/)                    return "Rendre la fenêtre flottante"
    if (cmd ~ /^focus mode_toggle$/)                  return "Basculer tuiles / flottantes"
    if (cmd ~ /^focus parent$/)                       return "Sélectionner le conteneur parent"
    if (cmd ~ /^focus child$/)                        return "Sélectionner le conteneur enfant"
    if (cmd ~ /^move scratchpad$/)                    return "Cacher la fenêtre (scratchpad)"
    if (cmd ~ /^scratchpad show$/)                    return "Afficher les fenêtres cachées"
    if (cmd ~ /^mode "?resize"?$/)                    return "Redimensionner, puis Échap pour quitter"
    if (cmd ~ /^mode "?passthrough"?$/)               return "Envoyer les touches à l'application"
    if (cmd ~ /^mode "?default"?$/)                   return "Revenir au mode normal"
    if (cmd ~ /^resize /)                             return "Redimensionner la fenêtre"
    if (cmd ~ /grimshot.* output/)                    return "Capturer l'écran"
    if (cmd ~ /grimshot.* active/)                    return "Capturer la fenêtre active"
    if (cmd ~ /grimshot.* area/)                      return "Capturer une zone"
    if (cmd ~ /brightnessctl.*%-/)                    return "Baisser la luminosité"
    if (cmd ~ /brightnessctl.*\+/)                    return "Augmenter la luminosité"
    if (cmd ~ /--increase/)                           return "Monter le volume"
    if (cmd ~ /--decrease/)                           return "Baisser le volume"
    if (cmd ~ /set-sink-mute/)                        return "Couper le son"
    if (cmd ~ /set-source-mute/)                      return "Couper le micro"
    if (cmd ~ /playerctl play-pause/)                 return "Lecture / pause"
    if (cmd ~ /playerctl pause/)                      return "Pause"
    if (cmd ~ /playerctl stop/)                       return "Arrêter la lecture"
    if (cmd ~ /playerctl next/)                       return "Piste suivante"
    if (cmd ~ /playerctl previous/)                   return "Piste précédente"
    if (cmd ~ /playerctl position \+/)                return "Avancer de 10 s"
    if (cmd ~ /playerctl position -/)                 return "Reculer de 10 s"
    return ""
}

# Commentaire du type « Super+F1 : fiche des raccourcis » : on garde la fin.
function from_comment(c,   left) {
    if (match(c, / : /)) {
        left = substr(c, 1, RSTART - 1)
        if (left ~ /\+/ && left !~ / /) c = substr(c, RSTART + 3)
    }
    sub(/\.$/, "", c)
    return toupper(substr(c, 1, 1)) substr(c, 2)
}

function keyname(t,   l) {
    l = tolower(t)
    if (l in KN) return KN[l]
    if (length(t) == 1) return toupper(t)
    return t
}

# Regroupe flèches, HJKL et chiffres sur une seule ligne.
function keydisplay(id,   key, cmd, parts, n, i, out, last, l, dirs, grouped) {
    grouped = 0
    key = B_key[id]
    cmd = B_cmd[id]
    if (B_type[id] == "bindcode") return "Code " key
    n = split(key, parts, "+")
    last = parts[n]
    l = tolower(last)
    dirs = vars["$left"] vars["$down"] vars["$up"] vars["$right"]
    if (cmd ~ /(^| )(left|right|up|down)( |$)/ || cmd ~ /^resize /) {
        if (l == "left" || l == "right" || l == "up" || l == "down" ||
            (length(l) == 1 && dirs != "" && index(tolower(dirs), l))) {
            last = "←↓↑→" (dirs != "" ? " / " toupper(dirs) : "")
            grouped = 1
        }
    } else if (cmd ~ /workspace (number )?[0-9]+$/ && last ~ /^[0-9]$/) {
        last = "1-0"; grouped = 1
    }
    out = ""
    for (i = 1; i < n; i++) out = out keyname(parts[i]) " "
    return out (grouped ? last : keyname(last))
}

function pad(s, w) { while (length(s) < w) s = s " "; return s }

function cut(s, w) { return length(s) > w ? substr(s, 1, w - 1) "…" : s }

BEGIN {
    # Logo Windows de la Nerd Font (nf-fa-windows) pour la touche Super.
    KN["mod4"] = "\xef\x85\xba"; KN["mod1"] = "Alt"; KN["shift"] = "Maj"
    KN["control"] = "Ctrl"; KN["ctrl"] = "Ctrl"
    KN["return"] = "Entrée"; KN["escape"] = "Échap"; KN["space"] = "Espace"
    KN["print"] = "ImpÉc";  KN["minus"] = "-";      KN["plus"] = "+"
    KN["tab"] = "Tab";      KN["backspace"] = "Retour arrière"; KN["delete"] = "Suppr"
    KN["left"] = "←"; KN["right"] = "→"; KN["up"] = "↑"; KN["down"] = "↓"
    KN["xf86audioraisevolume"] = "Volume +"
    KN["xf86audiolowervolume"] = "Volume −"
    KN["xf86audiomute"]        = "Sourdine"
    KN["xf86audiomicmute"]     = "Micro"
    KN["xf86audioplay"]        = "Lecture"
    KN["xf86audiopause"]       = "Pause"
    KN["xf86audiostop"]        = "Stop"
    KN["xf86audionext"]        = "Suivant"
    KN["xf86audioprev"]        = "Précédent"
    KN["xf86audioforward"]     = "Avance"
    KN["xf86audiorewind"]      = "Retour"
    KN["xf86monbrightnessup"]  = "Luminosité +"
    KN["xf86monbrightnessdown"] = "Luminosité −"

    depth = 0
    parse(main)

    rows = 0
    for (i = 1; i <= count; i++) {
        id = ids[i]
        if (id in removed) continue

        desc = describe(B_raw[id], B_cmd[id])
        if (desc == "" && B_comment[id] != "") desc = from_comment(B_comment[id])
        if (desc == "") desc = B_cmd[id]

        k = keydisplay(id)
        if (B_mode[id] != "default")
            k = toupper(substr(B_mode[id], 1, 1)) substr(B_mode[id], 2) " ▸ " k

        dk = k SUBSEP desc
        if (dk in row_of) {
            # Ligne regroupée : perso si l'une des touches l'est.
            if (B_custom[id]) R_custom[row_of[dk]] = 1
            continue
        }
        row_of[dk] = ++rows
        R_key[rows] = k
        R_desc[rows] = cut(desc, 44)
        R_custom[rows] = B_custom[id]
        if (length(k) > kw) kw = length(k)
        if (length(R_desc[rows]) > dw) dw = length(R_desc[rows])
    }

    for (r = 1; r <= rows; r++) {
        if (only_custom && !R_custom[r]) continue
        line = pad(R_key[r], kw) "   " pad(R_desc[r], dw)
        # Icône utilisateur de la Nerd Font (nf-fa-user).
        line = line (R_custom[r] ? "   \xef\x80\x87" : "")
        sub(/[ ]+$/, "", line)
        printf "%s\t%d\n", line, R_custom[r]
    }
}
AWK

rows=$(LC_ALL=C.UTF-8 awk \
    -v main="$main_config" \
    -v user_dir="$user_dir" \
    -v only_custom="$only_custom" \
    "$parser")

if [[ -z "$rows" ]]; then
    printf 'Aucun raccourci trouvé.\n' >&2
    exit 1
fi

labels=()
active=()
i=0
while IFS=$'\t' read -r label custom; do
    labels+=("$label")
    [[ "$custom" == 1 ]] && active+=("$i")
    i=$((i + 1))
done <<< "$rows"

if (( print_only )); then
    printf '%s\n' "${labels[@]}"
    exit 0
fi

# Rofi replie les espaces : on les fige pour garder l'alignement.
nbsp=$(printf '\302\240')
user_icon=$(printf '\357\200\207')
active_rows=$(IFS=,; printf '%s' "${active[*]:-}")

printf '%s\n' "${labels[@]}" | sed "s/ /${nbsp}/g" | rofi -dmenu -i -no-custom \
    -p 'Raccourcis' \
    -mesg "${user_icon}  défini dans ~/.config/sway, le reste vient du système" \
    ${active_rows:+-a "$active_rows"} \
    -theme "${theme}" >/dev/null || true
