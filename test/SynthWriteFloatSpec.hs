module Main where

import Control.Exception (IOException, try)
import qualified Data.Vector.Storable as V
import Sound.Fluidsynth
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = do
    eResult <- try $ synthWithSF
    case eResult of
        Left (_ :: IOException) ->
            defaultMain $ testGroup "SynthWriteFloat (no SoundFont)" baseTests
        Right result -> defaultMain result
  where
    synthWithSF = do
        s <- newSettings
        synth <- newSynth s
        _ <- loadSoundFont synth sfPath
        return $ testGroup "SynthWriteFloat" (baseTests ++ sfDependentTests synth)

sfPath :: FilePath
sfPath =
    "/opt/homebrew/Cellar/fluid-synth/2.5.5/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2"

baseTests :: [TestTree]
baseTests =
    [ testCase "zero frames returns empty vector" $ do
        s <- newSettings
        synth <- newSynth s
        result <- synthWriteFloat synth 0
        assertEqual "length" 0 (V.length result)
    , testCase "empty vector is null" $ do
        s <- newSettings
        synth <- newSynth s
        result <- synthWriteFloat synth 0
        assertBool "should be null" (V.null result)
    ]

sfDependentTests :: Synth -> [TestTree]
sfDependentTests synth =
    [ testCase "expected number of samples" $ do
        synthNoteOn synth 0 60 100
        result <- synthWriteFloat synth 4410
        synthNoteOff synth 0 60
        assertEqual "length = nframes * 2" 8820 (V.length result)
    , testCase "non-zero output after note on" $ do
        synthNoteOn synth 0 60 100
        result <- synthWriteFloat synth 4410
        synthNoteOff synth 0 60
        assertBool "output should contain non-zero samples"
            (V.any (/= 0) result)
    , testCase "produces 2 samples for 1 frame (stereo)" $ do
        synthNoteOn synth 0 60 100
        result <- synthWriteFloat synth 1
        synthNoteOff synth 0 60
        assertEqual "got left and right" 2 (V.length result)
    ]