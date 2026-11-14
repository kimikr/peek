#!/usr/bin/env bash
# Builds the Peek host app as an unsigned IPA for a GitHub release.
#
# Sideloading stores (SideStore, AltStore) and LiveContainer sign the app themselves, so the
# IPA attached to a release works for everyone. Upload it with:
#   gh release create v<version> dist/Peek-<version>.ipa dist/Peek-<version>.ipa.sha256
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(./peek --version)
(cd host && xtool dev build --ipa -c release)
mkdir -p dist
cp host/xtool/Peek.ipa "dist/Peek-$version.ipa"
(cd dist && sha256sum "Peek-$version.ipa" > "Peek-$version.ipa.sha256")
echo "dist/Peek-$version.ipa"
