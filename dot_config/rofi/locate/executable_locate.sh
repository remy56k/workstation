#!/usr/bin/env bash
# shellcheck shell=bash
# Recherche de fichiers via plocate.
# On tape les mots-clés (tous doivent apparaître dans le chemin, sans casse),
# puis on choisit un résultat :
#   Entrée  ouvre le fichier
#   Alt+d   ouvre le dossier parent
#   Alt+c   copie le chemin
# Échap dans la liste revient à la saisie.
# -ellipsize-mode start garde le nom du fichier visible sur les chemins longs.
# La base vient du dernier updatedb (minuterie systemd plocate-updatedb).

set -euo pipefail

dir="${HOME}/.config/rofi/locate"
theme="${dir}/menu.rasi"
query_theme="${dir}/query.rasi"
limit=500

hints='<b>Entrée</b> ouvrir   <b>Alt+d</b> dossier   <b>Alt+c</b> copier   <b>Échap</b> retour'

query=""
while true; do
    query="$(rofi -dmenu -p 'Fichiers' -filter "${query}" -theme "${query_theme}" \
        -mesg 'Mots-clés séparés par des espaces' < /dev/null)" || exit 0
    [[ -n "${query// /}" ]] || exit 0

    # Chaque mot est un motif ; plocate exige qu'ils soient tous présents.
    read -ra words <<< "${query}"
    mapfile -t paths < <(plocate -i -e -l "${limit}" -- "${words[@]}" || true)

    if (( ${#paths[@]} == 0 )); then
        notify-send -a Fichiers 'Aucun résultat' "${query}"
        continue
    fi

    count="${#paths[@]}"
    (( count >= limit )) && count="${limit}+"

    set +e
    index="$(for p in "${paths[@]}"; do
            if [[ -d "${p}" ]]; then icon=''; else icon=''; fi
            printf '%s  %s\n' "${icon}" "${p/#"${HOME}"/\~}"
        done | rofi -dmenu -i -format i -p "${count}" -markup -mesg "${hints}" \
            -ellipsize-mode start \
            -kb-custom-1 'Alt+d' -kb-custom-2 'Alt+c' -theme "${theme}")"
    status=$?
    set -e

    # 1 = Échap : on revient à la saisie.
    (( status == 1 )) && continue
    [[ -n "${index}" ]] || exit 0
    path="${paths[index]}"

    case "${status}" in
        0)
            xdg-open "${path}" >/dev/null 2>&1 &
            ;;
        10)
            target="${path}"
            [[ -d "${target}" ]] || target="$(dirname -- "${path}")"
            xdg-open "${target}" >/dev/null 2>&1 &
            ;;
        11)
            printf '%s' "${path}" | wl-copy
            notify-send -a Fichiers 'Chemin copié' "${path}"
            ;;
    esac
    exit 0
done
