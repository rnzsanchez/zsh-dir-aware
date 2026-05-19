#!/usr/bin/env bash
set -euo pipefail

ZSHRC="$HOME/.zshrc"
MARKER_START="# >>> zsh-dir-aware >>>"
MARKER_END="# <<< zsh-dir-aware <<<"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: macOS only." >&2
    exit 1
fi

if ! command -v brew &>/dev/null; then
    echo "Error: Homebrew not found. Install it from https://brew.sh first." >&2
    exit 1
fi

echo "Installing dependencies..."
brew install zsh-autosuggestions zsh-syntax-highlighting 2>/dev/null || true

if grep -q "$MARKER_START" "$ZSHRC" 2>/dev/null; then
    echo "zsh-dir-aware is already configured in $ZSHRC. Nothing to do."
    echo "To reinstall, remove the block between $MARKER_START and $MARKER_END and run again."
    exit 0
fi

cat >> "$ZSHRC" << 'ZSHBLOCK'

# >>> zsh-dir-aware >>>
zstyle ':completion:*' special-dirs true

typeset -g  _DA_PREFIX=""
typeset -ga _DA_MATCHES=()
typeset -gi _DA_IDX=1

_da_build_matches() {
    local buf="$1" prefix="$2"
    local cmd="${buf%% *}"
    local path_prefix="${buf#$cmd }"

    _DA_PREFIX="$buf"
    _DA_MATCHES=()
    _DA_IDX=1

    local best="${history[(r)${prefix}*]}"
    if [[ -n "$best" ]]; then
        local first_arg="${${best#$cmd }%% *}"
        [[ -e "${first_arg/#\~/$HOME}" ]] && _DA_MATCHES+=("$best")
    fi

    local -a fs
    fs=(${path_prefix/#\~/$HOME}*(N/))
    local m
    for m in $fs; do
        local cand="$cmd ${m/#$HOME/~}"
        [[ "$cand" != "${_DA_MATCHES[1]}" ]] && _DA_MATCHES+=("$cand")
    done
}

_zsh_autosuggest_strategy_dir_aware() {
    emulate -L zsh
    setopt EXTENDED_GLOB

    typeset -g suggestion
    local buf="$1"

    if [[ "$buf" =~ ^(cd|pushd|popd|ls|ll|la|open|cp|mv|mkdir|rmdir)[[:space:]] ]]; then
        if (( ${#_DA_MATCHES} > 0 )) && (( ${_DA_MATCHES[(I)$buf]} )); then
            suggestion=""
            return
        fi
        local prefix="${buf//(#m)[\\*?[\]<>()|^~#]/\\$MATCH}"
        _da_build_matches "$buf" "$prefix"
        [[ ${#_DA_MATCHES} -gt 0 ]] && suggestion="${_DA_MATCHES[1]}"
    else
        _DA_MATCHES=()
        _zsh_autosuggest_strategy_history "$buf"
    fi
}

_da_cycle() {
    local dir="$1"

    if [[ ! "$BUFFER" =~ ^(cd|pushd|popd|ls|ll|la|open|cp|mv|mkdir|rmdir)[[:space:]] ]]; then
        [[ "$dir" == "next" ]] && zle down-line-or-beginning-search \
                                || zle up-line-or-beginning-search
        return
    fi

    # Async strategy runs in a subshell so _DA_MATCHES never reaches the parent.
    # Rebuild in the parent shell whenever BUFFER isn't already a cycle candidate.
    if (( ! ${_DA_MATCHES[(I)$BUFFER]} )); then
        setopt local_options extended_glob
        local prefix="${BUFFER//(#m)[\\*?[\]<>()|^~#]/\\$MATCH}"
        _da_build_matches "$BUFFER" "$prefix"
    fi

    if [[ ${#_DA_MATCHES} -le 1 ]]; then
        [[ "$dir" == "next" ]] && zle down-line-or-beginning-search \
                                || zle up-line-or-beginning-search
        return
    fi

    if [[ "$dir" == "next" ]]; then
        _DA_IDX=$(( _DA_IDX % ${#_DA_MATCHES} + 1 ))
    else
        _DA_IDX=$(( (_DA_IDX - 2 + ${#_DA_MATCHES}) % ${#_DA_MATCHES} + 1 ))
    fi

    BUFFER="${_DA_MATCHES[$_DA_IDX]}"
    CURSOR=${#BUFFER}
    POSTDISPLAY=""
}

_da_up()   { _da_cycle prev }
_da_down() { _da_cycle next }
zle -N _da_up
zle -N _da_down

ZSH_AUTOSUGGEST_STRATEGY=(dir_aware)

source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# Must be after sourcing so the plugin's defaults are established first
ZSH_AUTOSUGGEST_IGNORE_WIDGETS+=(_da_up _da_down)

source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Bind both normal (^[[) and application cursor (^[O) escape sequences for portability
bindkey '^[[A' _da_up
bindkey '^[OA' _da_up
bindkey '^[[B' _da_down
bindkey '^[OB' _da_down
# <<< zsh-dir-aware <<<
ZSHBLOCK

echo "Done. Run 'exec zsh' to apply."
