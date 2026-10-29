#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${UOMP_REPO_URL:-https://github.com/0xSynapse/uomp-core.git}"
REF="${UOMP_REF:-main}"
INSTALL_ROOT="${UOMP_INSTALL_ROOT:-$HOME/.uomp/cli}"
BIN_DIR="${UOMP_BIN_DIR:-$HOME/.local/bin}"
SRC_DIR="$INSTALL_ROOT/src"
BIN_PATH="$BIN_DIR/uomp"

info() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || fail "git is required. Install git and try again."
command -v node >/dev/null 2>&1 || fail "Node.js >= 22 is required. Install Node.js and try again."

NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]")"
if [ "$NODE_MAJOR" -lt 22 ]; then
  fail "Node.js >= 22 is required (found $(node --version))."
fi

if command -v pnpm >/dev/null 2>&1; then
  PNPM=(pnpm)
elif command -v corepack >/dev/null 2>&1; then
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  PNPM=(corepack pnpm)
elif command -v npm >/dev/null 2>&1; then
  PNPM=(npx --yes pnpm@9)
else
  fail "pnpm 9 is required. Install pnpm or enable corepack and try again."
fi

info "Installing UOMP from $REPO_URL ($REF)"

mkdir -p "$INSTALL_ROOT" "$BIN_DIR"

if [ -d "$SRC_DIR/.git" ]; then
  info "Updating existing checkout in $SRC_DIR"
  git -C "$SRC_DIR" fetch --depth 1 origin "$REF"
  git -C "$SRC_DIR" checkout -q FETCH_HEAD
else
  rm -rf "$SRC_DIR"
  git clone --depth 1 --branch "$REF" "$REPO_URL" "$SRC_DIR"
fi

cd "$SRC_DIR"

info "Installing dependencies"
"${PNPM[@]}" install --frozen-lockfile

info "Building the CLI"
"${PNPM[@]}" --filter @uomp/cli... build

chmod +x "$SRC_DIR/packages/cli/dist/cli.js"
ln -sf "$SRC_DIR/packages/cli/dist/cli.js" "$BIN_PATH"

info ""
info "UOMP installed: $BIN_PATH"
info "Version: $("$BIN_PATH" --version)"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    info ""
    info "Add this to your shell profile so 'uomp' is on PATH:"
    info "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac

info ""
info "Next:"
info "  uomp init"
info "  uomp import ~/Obsidian/MyVault"
info "  uomp authorize ./path/to/agent --scope notes/projects"
