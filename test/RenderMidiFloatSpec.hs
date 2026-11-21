module Main where

import Control.Exception (IOException, try)
import qualified Data.Vector.Storable as V
import Sound.Fluidsynth
import System.IO.Error (isDoesNotExistError)
import Test.Tasty
import Test.Tasty.HUnit
import TestSoundFont (resolveTestSoundFont)

main :: IO ()
main = do
    mSfPath <- resolveTestSoundFont
    case mSfPath of
        Nothing ->
            defaultMain $ testGroup "RenderMidiFloat (no SoundFont)" baseTests
        Just sfPath ->
            defaultMain $ testGroup "RenderMidiFloat" (baseTests ++ sfDependentTests sfPath)

midiPath :: FilePath
midiPath = "test/data/test.mid"

isFiniteFloat :: Float -> Bool
isFiniteFloat x = not (isNaN x || isInfinite x)

baseTests :: [TestTree]
baseTests =
    [ testCase "PCMBufferFloat Eq and Show instances work" $ do
        let b1 = PCMBufferFloat 48000 2 (V.fromList [0.0, 0.25, -0.25, 0.5])
            b2 = PCMBufferFloat 48000 2 (V.fromList [0.0, 0.25, -0.25, 0.5])
            b3 = PCMBufferFloat 44100 2 (V.fromList [0.0, 0.25, -0.25, 0.5])
        assertEqual "equal buffers" b1 b2
        assertBool "different sample rate not equal" (b1 /= b3)
        assertBool "Show produces output" (not $ null $ show b1)
    , testCase "produces non-empty stereo buffer at default sample rate" $
        withSettings $ \s -> do
            synth <- newSynth s
            buf <- renderMidiFloat synth midiPath
            assertEqual "sample rate" 44100 (pcmFloatSampleRate buf)
            assertEqual "channels" 2 (pcmFloatChannels buf)
            assertBool "non-empty samples" (not $ V.null $ pcmFloatSamples buf)
            assertBool "even sample count" (even $ V.length $ pcmFloatSamples buf)
            assertBool "all samples finite" (V.all isFiniteFloat (pcmFloatSamples buf))
    , testCase "renders at 48000 Hz with dry synth settings" $
        withSettings $ \s -> do
            setStr s "player.timing-source" "sample"
            setNum s "synth.sample-rate" 48000
            setInt s "synth.reverb.active" 0
            setInt s "synth.chorus.active" 0
            reverb <- getInt s "synth.reverb.active"
            chorus <- getInt s "synth.chorus.active"
            assertEqual "reverb disabled" (Just 0) reverb
            assertEqual "chorus disabled" (Just 0) chorus
            synth <- newSynth s
            buf <- renderMidiFloat synth midiPath
            assertEqual "sample rate" 48000 (pcmFloatSampleRate buf)
            assertEqual "channels" 2 (pcmFloatChannels buf)
            assertBool "non-empty samples" (not $ V.null $ pcmFloatSamples buf)
            assertBool "even sample count" (even $ V.length $ pcmFloatSamples buf)
            assertBool "all samples finite" (V.all isFiniteFloat (pcmFloatSamples buf))
    , testCase "missing MIDI file throws doesNotExistError" $
        withSettings $ \s -> do
            synth <- newSynth s
            result <- try (renderMidiFloat synth "test/data/nonexistent.mid")
                :: IO (Either IOException PCMBufferFloat)
            case result of
                Left e ->
                    assertBool "should be doesNotExistError" (isDoesNotExistError e)
                Right _ ->
                    assertFailure "expected IOException to be thrown"
    ]

sfDependentTests :: FilePath -> [TestTree]
sfDependentTests sfPath =
    [ testCase "48000 Hz dry render with SoundFont produces non-zero finite float samples" $
        withSettings $ \s -> do
            setStr s "player.timing-source" "sample"
            setNum s "synth.sample-rate" 48000
            setInt s "synth.reverb.active" 0
            setInt s "synth.chorus.active" 0
            withSynth (SynthSettings s) sfPath $ \synth -> do
                buf <- renderMidiFloat synth midiPath
                let samples = pcmFloatSamples buf
                assertEqual "sample rate" 48000 (pcmFloatSampleRate buf)
                assertEqual "channels" 2 (pcmFloatChannels buf)
                assertBool "even sample count" (even $ V.length samples)
                assertBool "all samples finite" (V.all isFiniteFloat samples)
                assertBool "non-zero float samples" (V.any (/= 0) samples)
                assertBool "preserves sub-Int16 float precision"
                    (V.any (\x -> x /= 0 && abs (x * 32768 - fromIntegral (round (x * 32768) :: Int)) > 1e-4) samples)
    , testCase "dry settings differ from reverb/chorus enabled render at 48000 Hz" $ do
        dryBuf <- renderConfigured 0 0
        wetBuf <- renderConfigured 1 1
        assertEqual "dry sample rate" 48000 (pcmFloatSampleRate dryBuf)
        assertEqual "wet sample rate" 48000 (pcmFloatSampleRate wetBuf)
        assertBool "dry buffer has audio" (V.any (/= 0) (pcmFloatSamples dryBuf))
        assertBool "wet buffer has audio" (V.any (/= 0) (pcmFloatSamples wetBuf))
        assertBool "dry and wet renders should differ" (pcmFloatSamples dryBuf /= pcmFloatSamples wetBuf)
    ]
  where
    renderConfigured reverbActive chorusActive =
        withSettings $ \s -> do
            setStr s "player.timing-source" "sample"
            setNum s "synth.sample-rate" 48000
            setInt s "synth.reverb.active" reverbActive
            setInt s "synth.chorus.active" chorusActive
            withSynth (SynthSettings s) sfPath $ \synth ->
                renderMidiFloat synth midiPath
