# initkit prompt.zsh - two-line pastel prompt with cached git info.
#
# Big-repo safety strategy (synchronous by design, async planned for later):
#  - git info is computed only when the directory changed or a command ran
#    (preexec), never on plain prompt redraws;
#  - a single `git status --porcelain=v2 --branch` call provides branch +
#    dirty (incl. untracked) + ahead/behind at once;
#  - core/zsh.sh enables core.untrackedCache and core.fsmonitor globally, which
#    is what keeps `git status` fast even in very large repositories.
#
# No patched/nerd fonts needed (plain glyphs: box drawing, ‹› ↑↓ ✱ ❯ …).
# NOTE: prompt strings must never nest %F{...} (or any braced escape) inside
# ${var:-...} substitutions - the prompt parser ends the substitution at the
# first '}'. Colored segments are precomputed in precmd instead.

setopt PROMPT_SUBST

typeset -g _si_git_info=""
typeset -g _si_git_pwd=""
typeset -g _si_git_refresh=1
typeset -g _si_venv=""

_si_git_render() {
  local input=$1 branch="" oid="" line dirty=0 ahead=0 behind=0
  while IFS= read -r line; do
    case $line in
      '# branch.head '*) branch=${line##'# branch.head '} ;;
      '# branch.oid '*) oid=${line##'# branch.oid '} ;;
      '# branch.ab +'*)
        ahead=${line#'# branch.ab +'}
        ahead=${ahead%% -*}
        behind=${line##*' -'}
        ;;
      [12u?]*) dirty=1 ;;
    esac
  done <<<"$input"

  local out=" %F{176}"
  if [[ -n $branch && $branch != "(detached)" ]]; then
    out+=${branch//\%/%%}
  elif [[ -n $oid ]]; then
    out+="@${oid[1,8]}"
  else
    printf ''
    return
  fi
  out+="%f"
  (( dirty ))  && out+=" %F{210}✱%f"
  (( ahead ))  && out+=" %F{158}↑${ahead}%f"
  (( behind )) && out+=" %F{216}↓${behind}%f"
  printf '%s' "$out"
}

_si_prompt_precmd() {
  if [[ -n ${VIRTUAL_ENV:-} ]]; then
    _si_venv=" %F{114}‹${VIRTUAL_ENV:t}›%f"
  else
    _si_venv=""
  fi

  if (( _si_git_refresh )) || [[ $PWD != $_si_git_pwd ]]; then
    _si_git_refresh=0
    _si_git_pwd=$PWD
    _si_git_info=$(_si_git_render "$(git status --porcelain=v2 --branch 2>/dev/null)")
  fi
}

_si_prompt_preexec() {
  _si_git_refresh=1
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _si_prompt_precmd
add-zsh-hook preexec _si_prompt_preexec

# pastel palette (256-color): 110 sapphire, 75 blue, 176 mauve, 114 mint,
# 158 spring, 216 peach, 213 pink, 210 rose
PROMPT=$'╭─%(!.%F{210}.%F{110})%n@%m%f %F{75}%40<…<%~%<<%f${_si_venv}${_si_git_info}\n╰─%F{213}%(!.#.❯)%f '
RPROMPT='%(?..%F{210}exit %?%f)'
