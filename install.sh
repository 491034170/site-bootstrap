#!/usr/bin/env bash
#
# site-bootstrap installer. Drops the CLI into ~/.local/bin by default.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/tianmind-studio/site-bootstrap/main/install.sh | bash
#
# Env:
#   SB_PREFIX   Install prefix. Default: $HOME/.local
#   SB_REF      Git ref (branch / tag). Default: main

set -euo pipefail

SB_PREFIX="${SB_PREFIX:-$HOME/.local}"
SB_REF="${SB_REF:-main}"
REPO="tianmind-studio/site-bootstrap"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "==> downloading site-bootstrap@$SB_REF"
curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$SB_REF" \
  | tar -xz -C "$TMPDIR"

SRC="$TMPDIR/$(basename "$REPO")-$SB_REF"
DEST="$SB_PREFIX/share/site-bootstrap"
BIN="$SB_PREFIX/bin/site-bootstrap"

mkdir -p "$SB_PREFIX/bin" "$SB_PREFIX/share"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
ln -sf "$DEST/bin/site-bootstrap" "$BIN"
chmod +x "$DEST/bin/site-bootstrap"

echo ""
echo "==> installed to $BIN"
if ! echo ":$PATH:" | grep -q ":$SB_PREFIX/bin:"; then
  cat <<EOF

Your PATH does not include $SB_PREFIX/bin yet. Add this to your shell rc:

  export PATH="$SB_PREFIX/bin:\$PATH"

Then run: site-bootstrap doctor
EOF
else
  echo "Run: site-bootstrap doctor"
fi
