#!/bin/sh
# Installs peek on Linux:
#   curl -fsSL https://raw.githubusercontent.com/kimikr/peek/main/scripts/install.sh | sh
#
# Puts the repository in ~/.local/share/peek, links ~/.local/bin/peek, and installs ldid
# into ~/.local/bin if it is missing. The Swift toolchain and iOS SDK come from xtool,
# which this script does not install; `peek doctor` at the end says what is left to do.
set -eu

REPO=${PEEK_REPO:-https://github.com/kimikr/peek}
DATA=${PEEK_INSTALL_DIR:-$HOME/.local/share/peek}
BIN=${PEEK_BIN_DIR:-$HOME/.local/bin}

say() { printf '%s\n' "$*"; }
fail() { say "peek install: $*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || fail "python3 is required"
python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' || fail "python3 3.9 or newer is required"
command -v git >/dev/null 2>&1 || fail "git is required"

mkdir -p "$BIN" "$(dirname "$DATA")"
if [ -d "$DATA/.git" ]; then
    say "Updating $DATA"
    git -C "$DATA" pull --ff-only --quiet
else
    say "Downloading peek into $DATA"
    git clone --depth 1 --quiet "$REPO" "$DATA"
fi
ln -sf "$DATA/peek" "$BIN/peek"
say "Linked $BIN/peek"

if ! command -v ldid >/dev/null 2>&1 && [ ! -x "$BIN/ldid" ]; then
    case "$(uname -m)" in
        x86_64 | amd64) arch=x86_64 ;;
        aarch64 | arm64) arch=aarch64 ;;
        *) fail "no ldid build for $(uname -m); install ldid yourself (github.com/ProcursusTeam/ldid)" ;;
    esac
    command -v curl >/dev/null 2>&1 || fail "curl is required to download ldid"
    say "Downloading ldid ($arch)"
    curl -fsSL -o "$BIN/ldid" "https://github.com/ProcursusTeam/ldid/releases/latest/download/ldid_linux_$arch"
    chmod +x "$BIN/ldid"
fi

command -v openssl >/dev/null 2>&1 || say "Note: openssl is missing; install it with your package manager."

case ":$PATH:" in
    *":$BIN:"*) ;;
    *) say "Note: add $BIN to your PATH, e.g. echo 'export PATH=\"$BIN:\$PATH\"' >> ~/.bashrc" ;;
esac

say ""
PATH="$BIN:$PATH" "$BIN/peek" doctor --no-build || true
say ""
say "Next: if the Swift toolchain or iOS SDK is missing, install xtool (https://github.com/xtool-org/xtool)"
say "and run \`xtool setup\`. Then install Peek.ipa from the releases page and run \`peek dev <your app>\`."
