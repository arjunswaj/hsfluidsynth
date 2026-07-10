module Main where

import Control.Exception (IOException, try)
import qualified Data.Vector.Storable as V
import Sound.Fluidsynth hiding (withSynth)
import System.IO.Error (isDoesNotExistError)
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "renderMidi"
    [ testCase "produces non-empty buffer" $ withSynth $ \synth -> do
        buf <- renderMidi synth "test/data/test.mid"
        assertBool "pcmSamples should be non-empty" (not $ V.null $ pcmSamples buf)
    , testCase "correct sample rate" $ withSynth $ \synth -> do
        buf <- renderMidi synth "test/data/test.mid"
        assertEqual "sample rate" 44100 (pcmSampleRate buf)
    , testCase "stereo output" $ withSynth $ \synth -> do
        buf <- renderMidi synth "test/data/test.mid"
        assertEqual "channels" 2 (pcmChannels buf)
    , testCase "samples length is even (stereo interleaved)" $ withSynth $ \synth -> do
        buf <- renderMidi synth "test/data/test.mid"
        assertBool "even sample count" (even $ V.length $ pcmSamples buf)
    , testCase "invalid MIDI file path throws doesNotExistError" $ withSynth $ \synth -> do
        result <- try $ renderMidi synth "test/data/nonexistent.mid"
        case result of
            Left e ->
                assertBool "should be doesNotExistError" (isDoesNotExistError e)
            Right _ ->
                assertFailure "expected IOException to be thrown"
    ]

withSynth :: (Synth -> IO a) -> IO a
withSynth f = do
    s <- newSettings
    synth <- newSynth s
    f synth