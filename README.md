hsfluidsynth
============

Haskell bindings to [FluidSynth](https://www.fluidsynth.org/), a real-time
software synthesizer based on the SoundFont 2 specification.

`hsfluidsynth` provides a small, safe high-level API for loading SoundFonts and
rendering MIDI to signed-16-bit PCM sample buffers.

Requirements
------------

- **FluidSynth >= 2.0.0** (the C library is linked via `pkg-config`). The
  bindings use `new_fluid_sequencer2`, `fluid_player_seek`, and other APIs
  introduced in the 2.x series; earlier FluidSynth is not supported.
- GHC 9.2+ (tested with GHC 9.10.3).
- `pkg-config` resolvable at configuration time.

Building
--------

### Debian / Ubuntu

```
sudo apt install libfluidsynth-dev pkg-config
cabal build all
```

### macOS (Homebrew)

```
brew install fluid-synth pkg-config
cabal build all
```

Core API
--------

The library is exposed through `Sound.Fluidsynth`. The high-level surface is
small:

- `withSettings :: (Settings -> IO a) -> IO a` — bracket-scoped settings.
- `withSynth :: Settings -> (Synth -> IO a) -> IO a` — bracket-scoped synth.
- `withPlayer :: Synth -> (Player -> IO a) -> IO a` — bracket-scoped player.
- `loadSoundFont :: Synth -> FilePath -> IO SoundFontId` — load a `.sf2`,
  returns a `SoundFontId`; throws `IOException` on failure.
- `renderPCM :: Synth -> Int -> IO PCMBuffer` — render N frames directly into
  a `PCMBuffer` (sample rate auto-detected, fallback 44100).
- `renderMidi :: Synth -> FilePath -> IO PCMBuffer` — render an entire MIDI
  file to a `PCMBuffer` (manages the player lifecycle internally).
- `synthWriteS16 :: Synth -> Int -> IO (Vector Int16)` — low-level signed-16
  render returning interleaved stereo samples.
- `synthWriteFloat :: Synth -> Int -> IO (Vector CFloat)` — low-level float
  render returning interleaved stereo samples.

### `PCMBuffer`

```haskell
data PCMBuffer = PCMBuffer
    { pcmSampleRate :: !Int
    , pcmChannels   :: !Int
    , pcmSamples    :: !(Vector Int16)
    }
```

A canonical, self-describing container for rendered PCM: signed 16-bit,
little-endian, interleaved stereo (`[L, R, L, R, ...]`).

Example
-------

`examples/RenderMidiExample.hs` (built as the `render-midi-example`
executable) demonstrates the full pipeline:

```
cabal run render-midi-example -- SOUNDFONT.sf2 input.mid output.raw
```

A minimal program:

```haskell
import Sound.Fluidsynth

main :: IO ()
main = withSettings $ \settings ->
    withSynth settings $ \synth -> do
        _ <- loadSoundFont synth "path/to/sf2/Default.sf2"
        buf <- renderMidi synth "input.mid"
        -- pcmSamples buf :: Vector Int16, interleaved stereo
        ...
```

Testing
-------

Tests are written with `tasty` + `tasty-hunit`. Run them all with:

```
cabal test all
```

Test suites include unit tests for settings, synth, player, `synthWriteS16` /
`synthWriteFloat`, `PCMBuffer`, `renderPCM`, `renderMidi`, the file renderer,
bracket-style resource helpers, logging wrappers, and an end-to-end integration
suite (`IntegrationSpec`) that validates the full `withSettings` → `withSynth`
→ `renderMidi` lifecycle.

Recent work
-----------

Recent additions to the API include bracket-style resource management
(`withSettings`/`withSynth`/`withPlayer`), `renderPCM`/`renderMidi` for
high-level PCM rendering, `FileRenderer` support, logging wrappers
(`LogLevel`, `LogCallback`, `withLogCallback`), newtypes (`SoundFontId`,
`SynthSettings`), a macOS exit segfault workaround, and comprehensive test
coverage across all modules.

Known limitations
-----------------

- **macOS exit segfault (mitigated).** On macOS with FluidSynth 2.x, the
  process may segfault during teardown of FluidSynth's background threads.
  `hsfluidsynth` works around this by skipping C-level cleanup on macOS,
  allowing the OS to reclaim resources on exit. This means HPC coverage
  `.tix` files are now written correctly on macOS.
- No audio driver bindings beyond the file renderer; the emphasis is on
  off-line rendering to sample buffers.

License
-------

MIT (see `LICENSE`). Originally © 2014 Google Inc.; header licensing retained
in original source files.
