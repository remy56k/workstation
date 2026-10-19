#!/usr/bin/env bash
# shellcheck shell=bash
# Menu de session.
# Verrouiller et suspendre partent tout de suite.
# Quitter, redémarrer et éteindre demandent une confirmation.

set -euo pipefail

dir="${HOME}/.config/rofi/powermenu"
theme="${dir}/menu.rasi"
confirm_theme="${dir}/confirm.rasi"

lock=$'  Verrouiller'
suspend=$'  Suspendre'
logout=$'  Déconnexion'
reboot=$'  Redémarrer'
shutdown=$'  Éteindre'

confirm() {
    local answer
    answer="$(printf 'Oui\nNon\n' | rofi -dmenu -i -p 'Confirmation' -mesg "$1" -theme "${confirm_theme}")"
    [[ "${answer}" == "Oui" ]]
}

chosen="$(printf '%s\n' "${lock}" "${suspend}" "${logout}" "${reboot}" "${shutdown}" \
    | rofi -dmenu -i -p 'Session' -theme "${theme}")"

case "${chosen}" in
    "${lock}")
        swaylock
        ;;
    "${suspend}")
        systemctl suspend
        ;;
    "${logout}")
        if confirm "Quitter la session ?"; then
            swaymsg exit
        fi
        ;;
    "${reboot}")
        if confirm "Redémarrer ?"; then
            systemctl reboot
        fi
        ;;
    "${shutdown}")
        if confirm "Éteindre ?"; then
            systemctl poweroff
        fi
        ;;
esac
