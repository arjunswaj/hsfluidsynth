module Main where

import Control.Exception (IOException, try)
import Data.Int (Int16)
import qualified Data.Vector.Storable as V
import Sound.Fluidsynth
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = do
    eResult <- try $ synthWithSF
    case eResult of
        Left (_ :: IOException) ->
            defaultMain $ testGroup "PCMBuffer (no SoundFont)" baseTests
        Right result -> defaultMain result
  where
    synthWithSF = do
        s <- newSettings
        synth <- newSynth s
        _ <- loadSoundFont synth sfPath
        return $ testGroup "PCMBuffer" (baseTests ++ sfDependentTests synth)

sfPath :: FilePath
sfPath =
    "/opt/homebrew/Cellar/fluid-synth/2.5.5/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2"

baseTests :: [TestTree]
baseTests =
    [ testCase "zero frames returns empty buffer" $ do
        s <- newSettings
        synth <- newSynth s
        buf <- pcmBufferFromSynth synth 44100 0
        assertEqual "sample rate" 44100 (pcmSampleRate buf)
        assertEqual "channels" 2 (pcmChannels buf)
        assertEqual "samples length" 0 (V.length (pcmSamples buf))
    , testCase "Eq and Show instances work" $ do
        s <- newSettings
        synth <- newSynth s
        buf1 <- pcmBufferFromSynth synth 44100 0
        buf2 <- pcmBufferFromSynth synth 44100 0
        assertEqual "Eq: equal buffers" buf1 buf2
        assertBool "Show: produces output" (not $ null $ show buf1)
    ]

sfDependentTests :: Synth -> [TestTree]
sfDependentTests synth =
    [ testCase "has correct sample rate" $ do
        synthNoteOn synth 0 60 100
        buf <- pcmBufferFromSynth synth 48000 4410
        synthNoteOff synth 0 60
        assertEqual "sample rate" 48000 (pcmSampleRate buf)
    , testCase "has correct channels" $ do
        synthNoteOn synth 0 60 100
        buf <- pcmBufferFromSynth synth 44100 4410
        synthNoteOff synth 0 60
        assertEqual "channels" 2 (pcmChannels buf)
    , testCase "samples non-empty after rendering" $ do
        synthNoteOn synth 0 60 100
        buf <- pcmBufferFromSynth synth 44100 4410
        synthNoteOff synth 0 60
        assertBool "should contain samples" (not $ V.null $ pcmSamples buf)
    ]
