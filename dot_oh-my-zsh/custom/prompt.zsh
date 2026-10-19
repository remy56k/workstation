# Custom prompt — Dracula palette
ZSH_THEME_GIT_PROMPT_PREFIX='%F{#bd93f9}(%F{#ff79c6}'
ZSH_THEME_GIT_PROMPT_SUFFIX='%F{#bd93f9})%f'
ZSH_THEME_GIT_PROMPT_BRANCH='%F{#ff79c6}'

setopt PROMPT_SUBST

precmd() {
  PROMPT='🎃 %F{#bd93f9}%n%F{#6272a4}@%F{#ff79c6}%m%f %F{#8be9fd}%2~%f $(git_prompt_info)$(git_prompt_status)%F{#ff5555}➜%f  '
  RPROMPT='%(?.%F{#6272a4}.%F{#ff5555})%?%f'
}
