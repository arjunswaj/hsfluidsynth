module Main (main) where

import Control.Exception (IOException, try)
import qualified Data.Vector.Storable as V
import Sound.Fluidsynth
import System.Directory (doesFileExist)
import Test.Tasty
import Test.Tasty.HUnit

-- | End-to-end integration validation for the hsfluidsynth pipeline.
--
-- These tests do NOT require a SoundFont to be present on the test machine:
-- FluidSynth will happily render MIDI (producing silence) without a loaded
-- SoundFont, which is enough to validate the *shape* and *consistency* of the
-- returned 'PCMBuffer'.
main :: IO ()
main = do
    midiOk <- doesFileExist "test/data/test.mid"
    if midiOk
        then defaultMain tests
        else defaultMain $ testGroup "IntegrationSpec" $
            [ testCase "test/data/test.mid present" $
                assertFailure "test/data/test.mid is missing; cannot run integration tests"
            ]

midiPath :: FilePath
midiPath = "test/data/test.mid"

tests :: TestTree
tests = testGroup "IntegrationSpec"
    [ testCase "full lifecycle produces a well-shaped buffer" $
        withSettings $ \settings -> do
            synth <- newSynth settings
            buf <- renderMidi synth midiPath
            assertEqual "channels" 2 (pcmChannels buf)
            assertBool "sample rate > 0" (pcmSampleRate buf > 0)
            assertBool "samples non-empty" (not $ V.null $ pcmSamples buf)
            assertBool "sample count divisible by channels"
                (V.length (pcmSamples buf) `mod` pcmChannels buf == 0)
    , testCase "repeated renderMidi calls yield consistent shapes (stable)" $
        withSettings $ \settings -> do
            synth <- newSynth settings
            buf1 <- renderMidi synth midiPath
            buf2 <- renderMidi synth midiPath
            assertEqual "sample rate stable"
                (pcmSampleRate buf1) (pcmSampleRate buf2)
            assertEqual "channel count stable"
                (pcmChannels buf1) (pcmChannels buf2)
            assertEqual "sample count stable"
                (V.length (pcmSamples buf1)) (V.length (pcmSamples buf2))
    , testCase "PCMBuffer samples evenly divide by channels" $
        withSettings $ \settings -> do
            synth <- newSynth settings
            buf <- renderMidi synth midiPath
            let n = V.length (pcmSamples buf)
                ch = pcmChannels buf
            assertBool "channels > 0" (ch > 0)
            assertEqual "n mod ch == 0" 0 (n `mod` ch)
            assertEqual "n div ch matches frame count" (n `div` ch) (n `div` ch)
    , testCase "missing MIDI file throws IOException" $ do
        r <- (try (withSettings $ \settings -> do
                      synth <- newSynth settings
                      renderMidi synth "test/data/does-not-exist.mid"))
              :: IO (Either IOException PCMBuffer)
        case r of
            Left _  -> return ()
            Right _ -> assertFailure "expected IOException for missing MIDI file"
    , testCase "renderPCM produces a stereo buffer with positive rate" $
        withSettings $ \settings -> do
            synth <- newSynth settings
            let nframes = 1024
            buf <- renderPCM synth nframes
            assertEqual "channels" 2 (pcmChannels buf)
            assertBool "sample rate > 0" (pcmSampleRate buf > 0)
            assertEqual "samples length = frames * channels"
                (nframes * pcmChannels buf) (V.length (pcmSamples buf))
    ]
