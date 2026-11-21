module TestSoundFont
    ( resolveTestSoundFont
    , resolveDualTestSoundFonts
    ) where

import Control.Monad (filterM)
import Data.List (nub)
import Data.Maybe (listToMaybe, maybeToList)
import System.Directory (canonicalizePath, doesFileExist)
import System.Environment (lookupEnv)

defaultPrimaryCandidates :: [FilePath]
defaultPrimaryCandidates =
    [ "/usr/local/share/soundfonts/VintageDreamsWaves-v2.sf2"
    , "/usr/share/sounds/sf2/FluidR3_GM.sf2"
    , "/soundfonts/FluidR3_GM.sf2"
    , "/opt/homebrew/Cellar/fluid-synth/2.5.5/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2"
    , "/usr/share/sounds/sf2/default-GM.sf2"
    , "/usr/share/soundfonts/default.sf2"
    ]

defaultDualCandidates :: [FilePath]
defaultDualCandidates =
    [ "/usr/local/share/soundfonts/VintageDreamsWaves-v2.sf2"
    , "/usr/local/share/soundfonts/VintageDreamsWaves-v2.sf3"
    , "/usr/share/sounds/sf2/FluidR3_GM.sf2"
    , "/soundfonts/Selected.sf2"
    , "/soundfonts/FluidR3_GM.sf2"
    , "/opt/homebrew/Cellar/fluid-synth/2.5.5/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2"
    , "/opt/homebrew/Cellar/fluid-synth/2.5.5/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf3"
    ]

nonEmptyEnv :: String -> IO [FilePath]
nonEmptyEnv name = do
    mVal <- lookupEnv name
    return [p | p <- maybeToList mVal, not (null p)]

-- | Resolve a single test SoundFont path.
-- Checks FLUIDSYNTH_TEST_SF2 first, then well-known Linux/container and macOS paths.
resolveTestSoundFont :: IO (Maybe FilePath)
resolveTestSoundFont = do
    envPaths <- nonEmptyEnv "FLUIDSYNTH_TEST_SF2"
    existing <- filterM doesFileExist (envPaths ++ defaultPrimaryCandidates)
    return (listToMaybe existing)

-- | Resolve two distinct test SoundFont paths (by canonical path) for dual-font tests.
-- Checks FLUIDSYNTH_TEST_SF2 and FLUIDSYNTH_TEST_SF2_ALT first, then fallback paths.
resolveDualTestSoundFonts :: IO (Maybe (FilePath, FilePath))
resolveDualTestSoundFonts = do
    envPrimary <- nonEmptyEnv "FLUIDSYNTH_TEST_SF2"
    envAlt <- nonEmptyEnv "FLUIDSYNTH_TEST_SF2_ALT"
    existing <- filterM doesFileExist (envPrimary ++ envAlt ++ defaultDualCandidates)
    canonical <- mapM canonicalizePath existing
    case nub canonical of
        (a : b : _) -> return (Just (a, b))
        _           -> return Nothing
