#!/usr/bin/env bash
# shellcheck shell=bash
# Fiche des raccourcis, sur le modèle KeyHints :
# deux colonnes alignées, affichées par Rofi.

set -euo pipefail

theme="${HOME}/.config/KeyHints/keyhint.rasi"

keybindings=$(cat <<'EOF'
Échap              | Fermer cette fiche
  Entrée          | Ouvrir un terminal
  D               | Lancer une application
  Maj Q           | Fermer la fenêtre
  ←↑→↓            | Aller à la fenêtre d'à côté
  Maj ←↑→↓        | Déplacer la fenêtre
  1-0             | Changer de bureau
  Maj 1-0         | Envoyer la fenêtre sur un bureau
  F               | Plein écran
  Maj Espace      | Rendre la fenêtre flottante
  Espace          | Basculer vers les fenêtres flottantes
  R               | Redimensionner, puis Échap pour quitter
  Maj C           | Recharger la configuration
  Maj E           | Quitter la session
  ImpÉc           | Menu de capture
ImpÉc              | Capturer l'écran
Alt ImpÉc          | Capturer la fenêtre active
Ctrl ImpÉc         | Capturer une zone
Luminosité         | Touches du clavier
Volume             | Touches du clavier, sourdine comprise
Icône alimentation | Menu de session, dans la barre
  F1              | Afficher cette fiche
EOF
)

# column aligne sur des espaces. Rofi les replie, donc on les fige.
nbsp=$(printf '\302\240')
formatted=$(printf '%s\n' "$keybindings" | column -s '|' -t | sed "s/ /${nbsp}/g")

printf '%s\n' "$formatted" | rofi -dmenu -i -no-custom \
    -p 'Raccourcis' \
    -theme "${theme}" || true
