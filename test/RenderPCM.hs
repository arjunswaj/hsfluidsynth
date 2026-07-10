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
            defaultMain $ testGroup "RenderPCM (no SoundFont)" baseTests
        Right result -> defaultMain result
  where
    synthWithSF = do
        s <- newSettings
        synth <- newSynth s
        _ <- loadSoundFont synth sfPath
        return $ testGroup "RenderPCM" (baseTests ++ sfDependentTests synth)

sfPath :: FilePath
sfPath =
    "/opt/homebrew/Cellar/fluid-synth/2.5.5/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2"

baseTests :: [TestTree]
baseTests =
    [ testCase "zero frames returns empty buffer" $ do
        s <- newSettings
        synth <- newSynth s
        buf <- renderPCM synth 0
        assertEqual "sample rate" 44100 (pcmSampleRate buf)
        assertEqual "channels" 2 (pcmChannels buf)
        assertEqual "samples length" 0 (V.length (pcmSamples buf))
    , testCase "default sample rate without SoundFont" $ do
        s <- newSettings
        synth <- newSynth s
        buf <- renderPCM synth 100
        assertEqual "sample rate" 44100 (pcmSampleRate buf)
        assertEqual "channels" 2 (pcmChannels buf)
        assertEqual "samples length" 200 (V.length (pcmSamples buf))
    ]

sfDependentTests :: Synth -> [TestTree]
sfDependentTests synth =
    [ testCase "correct sample rate" $ do
        synthNoteOn synth 0 60 100
        buf <- renderPCM synth 4410
        synthNoteOff synth 0 60
        assertEqual "sample rate" 44100 (pcmSampleRate buf)
    , testCase "correct channels" $ do
        synthNoteOn synth 0 60 100
        buf <- renderPCM synth 4410
        synthNoteOff synth 0 60
        assertEqual "channels" 2 (pcmChannels buf)
    , testCase "non-empty samples" $ do
        synthNoteOn synth 0 60 100
        buf <- renderPCM synth 4410
        synthNoteOff synth 0 60
        assertBool "should contain samples" (not $ V.null $ pcmSamples buf)
    , testCase "correct sample count for 100 frames" $ do
        synthNoteOn synth 0 60 100
        buf <- renderPCM synth 100
        synthNoteOff synth 0 60
        assertEqual "2 bytes per frame * 2 channels = 2 samples per frame"
            200 (V.length (pcmSamples buf))
    , testCase "non-zero output with SoundFont" $ do
        synthNoteOn synth 0 60 100
        buf <- renderPCM synth 4410
        synthNoteOff synth 0 60
        assertBool "output should contain non-zero samples"
            (V.any (/= 0) (pcmSamples buf))
    , testCase "multiple durations" $ do
        buf0 <- renderPCM synth 0
        assertEqual "0 frames" 0 (V.length (pcmSamples buf0))
        buf100 <- renderPCM synth 100
        assertEqual "100 frames" 200 (V.length (pcmSamples buf100))
        buf1sec <- renderPCM synth 44100
        assertEqual "44100 frames" 88200 (V.length (pcmSamples buf1sec))
    ]
