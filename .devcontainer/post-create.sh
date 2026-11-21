#!/usr/bin/env bash
# Prepare the devcontainer. You can run it more than once.
set -euo pipefail

cd "$(dirname "$0")/.."
echo "=== hsfluidsynth DevContainer Setup ==="

echo "Updating Hackage package index..."
cabal update

echo "Building dependencies..."
cabal build --only-dependencies --enable-tests

echo "Building hsfluidsynth and tests..."
cabal build --enable-tests

# Marker read by .devcontainer/exec.sh so a fresh Compose container is prepared
# exactly once. Lives on the dist-newstyle volume, so it survives container
# recreation but is discarded when the build cache is wiped.
mkdir -p dist-newstyle
touch dist-newstyle/.dev-ready

echo ""
echo "=== Setup Complete ==="
echo "git:        $(git --version)"
echo "jj:         $(jj --version)"
echo "ghc:        $(ghc --version)"
echo "cabal:      $(cabal --version | head -n1)"
echo "fluidsynth: $(pkg-config --modversion fluidsynth)"
