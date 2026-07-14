#!/bin/bash
# Symlinks this repo's files into place and (re)starts the service. Safe to
# re-run any time — that's also what update.sh does after a `git pull`.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

link() {
    local src="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        echo "Backing up existing $dest -> $dest.bak"
        mv "$dest" "$dest.bak"
    fi
    ln -sfn "$src" "$dest"
    echo "Linked $dest -> $src"
}

chmod +x "$REPO_DIR/bin/lock-suspend-timer.sh"

link "$REPO_DIR/bin/lock-suspend-timer.sh" "$HOME/.local/bin/lock-suspend-timer.sh"
link "$REPO_DIR/systemd/lock-suspend.service" "$HOME/.config/systemd/user/lock-suspend.service"
link "$REPO_DIR/desktop/restart-screenlock.desktop" "$HOME/.local/share/applications/restart-screenlock.desktop"

systemctl --user daemon-reload
systemctl --user enable lock-suspend.service
systemctl --user restart lock-suspend.service

echo
echo "Installed. Current status:"
systemctl --user status lock-suspend.service --no-pager
