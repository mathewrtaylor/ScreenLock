#!/bin/bash
# Pulls the latest changes and re-applies them (reload + restart the
# service). Since install.sh symlinks rather than copies, this is the
# entire update story — the equivalent of `apt update && apt full-upgrade`
# for this repo.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

echo "Pulling latest changes..."
git pull --ff-only

exec "$REPO_DIR/install.sh"
