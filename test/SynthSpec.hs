module Main where

import Control.Exception (IOException, try)
import Sound.Fluidsynth
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Synth"
    [ testCase "newSynth initializes successfully" $ do
        s <- newSettings
        synth <- newSynth s
        -- Just verifying it doesn't throw; synth holds a ref to settings
        return ()
    , testCase "system reset doesn't crash" $ do
        s <- newSettings
        synth <- newSynth s
        synthSystemReset synth
    , testCase "load invalid soundfont throws IOException" $ do
        s <- newSettings
        synth <- newSynth s
        r <- try $ loadSoundFont synth "/nonexistent/soundfont.sf2"
        case r of
            Left (_ :: IOException) -> return ()
            Right _                 -> assertFailure "expected IOException"
    , testCase "loadSF invalid path throws IOException" $ do
        s <- newSettings
        synth <- newSynth s
        r <- try $ loadSF synth "/nonexistent/soundfont.sf2"
        case r of
            Left (_ :: IOException) -> return ()
            Right _                 -> assertFailure "expected IOException"
    , testCase "synth cleanup via ForeignPtr" $ do
        -- Synth holds a ForeignPtr which automatically calls delete_fluid_synth
        -- when garbage collected. Just verify construction works.
        s <- newSettings
        _ <- newSynth s
        return ()
    , testCase "unloadSoundFont invalid path throws IOException" $ do
        s <- newSettings
        synth <- newSynth s
        r <- try $ unloadSoundFont synth "/nonexistent/soundfont.sf2"
        case r of
            Left (_ :: IOException) -> return ()
            Right _                 -> assertFailure "expected IOException"
    ]