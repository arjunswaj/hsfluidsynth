# AGENTS.md — hsfluidsynth

Haskell FFI bindings to FluidSynth 2.5.5 (`fluidsynth` Cabal package).

## Hard rules

- **Never build, test, format, lint, or run Haskell/C tools on the host.** The
  macOS host must never run `ghc`, `cabal`, `stack`, `ormolu`, `hlint`, or
  ad-hoc Python scripts for this repo. Every build, test, and lint command runs
  inside the Docker devcontainer via `.devcontainer/exec.sh …`.
- **Zero warnings.** Keep library and test code clean under GHC warnings; fix
  the source rather than adding suppressions.
- **Touch only this project's image, container, and volumes**
  (`hsfluidsynth-dev:local`, `hsfluidsynth-dist-newstyle`,
  `hsfluidsynth-cabal-store`). Do not prune unrelated Docker state.
- **Never push without approval.** Commit cleanly on `master` using `git`.

## Running commands — in the devcontainer

Edit files on the host; the repository is bind-mounted at `/workspace`.
`.devcontainer/exec.sh` automatically starts the `dev` Compose service
(`hsfluidsynth-dev:local`) and runs `.devcontainer/post-create.sh` on first use.

```bash
# Build library, examples, and test suites
bash .devcontainer/exec.sh cabal build all --enable-tests

# Run all test suites with full output
bash .devcontainer/exec.sh cabal test all --test-show-details=direct

# Run a single test suite
bash .devcontainer/exec.sh cabal test SynthSpec --test-show-details=direct

# Format check and lint
bash .devcontainer/exec.sh ormolu --mode check Sound/Fluidsynth.hs
bash .devcontainer/exec.sh hlint Sound test

# Long build logged in tmux / interactive shell
bash .devcontainer/exec.sh --watch cabal test all --test-show-details=direct
bash .devcontainer/exec.sh --interactive

# Rebuild or stop the dev container
docker compose --profile dev up -d --build dev
docker compose --profile dev down
```

## SoundFont test resolution

SoundFont-dependent test suites resolve fixture fonts via `test/TestSoundFont.hs`:

1. `FLUIDSYNTH_TEST_SF2` (and optional `FLUIDSYNTH_TEST_SF2_ALT` for dual-font
   tests) when set to an existing file.
2. Fallback search across Linux container and macOS paths:
   - `/usr/local/share/soundfonts/VintageDreamsWaves-v2.sf2` (and `.sf3`)
   - `/usr/share/sounds/sf2/FluidR3_GM.sf2`
   - `/soundfonts/FluidR3_GM.sf2` and `/soundfonts/Selected.sf2`
   - `/opt/homebrew/Cellar/fluid-synth/2.5.5/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2` (and `.sf3`)

The devcontainer image builds FluidSynth 2.5.5 into `/usr/local` and installs
`fluid-soundfont-gm` (plus copies FluidSynth's bundled SoundFonts when present),
so SoundFont tests execute inside Docker rather than skipping.
