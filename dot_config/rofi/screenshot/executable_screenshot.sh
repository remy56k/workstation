#!/usr/bin/env bash
# shellcheck shell=bash
# Menu de capture, sur le modèle des applets Rofi :
# écran entier ou zone, via grimshot.
# Le menu se ferme avant la sélection, pour laisser slurp prendre la souris.
# grimshot affiche une notification une fois l'image écrite.

set -euo pipefail

dir="${HOME}/.config/rofi/screenshot"
theme="${dir}/menu.rasi"

screen=$'  Écran entier'
area=$'  Zone'

chosen="$(printf '%s\n' "${screen}" "${area}" \
    | rofi -dmenu -i -p 'Capture' -theme "${theme}")"

case "${chosen}" in
    "${screen}")
        grimshot --notify save output
        ;;
    "${area}")
        grimshot --notify save area
        ;;
esac
