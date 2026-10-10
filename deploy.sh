#!/bin/bash
#
# deploy.sh - Install all scripts in this repo into a user-local bin directory.
# No root required. Scripts are symlinked by default (so edits/git pulls take
# effect immediately); use --copy to copy instead.
#
# Usage: ./deploy.sh [--copy] [--dir <target_dir>] [--uninstall]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$(basename "$0")"
TARGET_DIR="$HOME/.local/bin"
MODE="link"
UNINSTALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --copy) MODE="copy" ;;
        --dir) TARGET_DIR="${2:?--dir requires a path}"; shift ;;
        --uninstall) UNINSTALL=1 ;;
        -h|--help)
            echo "Usage: $SELF [--copy] [--dir <target_dir>] [--uninstall]"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "$TARGET_DIR"

# Grant execute permission to every script in the repo (including this one)
if [[ $UNINSTALL -eq 0 ]]; then
    for script in "$SCRIPT_DIR"/*.sh; do
        [[ -f "$script" ]] || continue
        chmod +x "$script"
        echo "granted  +x $(basename "$script")"
    done
    echo
fi

count=0
for src in "$SCRIPT_DIR"/*.sh; do
    [[ -f "$src" ]] || continue
    name="$(basename "$src")"
    [[ "$name" == "$SELF" ]] && continue

    # Command name: drop .sh, use dashes (kill_port.sh -> kill-port)
    cmd="${name%.sh}"
    cmd="${cmd//_/-}"
    dest="$TARGET_DIR/$cmd"

    if [[ $UNINSTALL -eq 1 ]]; then
        if [[ -e "$dest" || -L "$dest" ]]; then
            rm -f "$dest"
            echo "removed  $dest"
        fi
        continue
    fi

    rm -f "$dest"
    if [[ "$MODE" == "link" ]]; then
        ln -s "$src" "$dest"
    else
        cp "$src" "$dest"
        chmod +x "$dest"
    fi
    echo "deployed $cmd -> $dest"
    count=$((count + 1))
done

[[ $UNINSTALL -eq 1 ]] && exit 0

echo
echo "Deployed $count script(s) to $TARGET_DIR"

case ":$PATH:" in
    *":$TARGET_DIR:"*) ;;
    *)
        rc="$HOME/.bashrc"
        [[ "${SHELL:-}" == */zsh ]] && rc="$HOME/.zshrc"
        echo
        echo "NOTE: $TARGET_DIR is not in your PATH. Add it with:"
        echo "  echo 'export PATH=\"$TARGET_DIR:\$PATH\"' >> $rc && source $rc"
        ;;
esac
