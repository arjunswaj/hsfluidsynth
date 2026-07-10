module Main where

import Control.Exception (IOException, try)
import Sound.Fluidsynth
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Settings"
    [ testCase "setStr/getStr roundtrip" $ do
        s <- newSettings
        setStr s "audio.driver" "pulseaudio"
        v <- getStr s "audio.driver"
        v @?= Just "pulseaudio"
    , testCase "setNum/getNum roundtrip" $ do
        s <- newSettings
        setNum s "synth.gain" 0.5
        v <- getNum s "synth.gain"
        v @?= Just 0.5
    , testCase "setInt/getInt roundtrip" $ do
        s <- newSettings
        setInt s "synth.polyphony" 64
        v <- getInt s "synth.polyphony"
        v @?= Just 64
    , testCase "get invalid key returns Nothing" $ do
        s <- newSettings
        v <- getStr s "nonexistent.setting"
        v @?= Nothing
        v' <- getNum s "nonexistent.setting"
        v' @?= Nothing
        v'' <- getInt s "nonexistent.setting"
        v'' @?= Nothing
    , testCase "set invalid key throws exception" $ do
        s <- newSettings
        r <- try $ setStr s "nonexistent.setting" "value"
        case r of
            Left (_ :: IOException) -> return ()
            Right _                 -> assertFailure "expected IOException"
    , testCase "set invalid key throws exception (num)" $ do
        s <- newSettings
        r <- try $ setNum s "nonexistent.setting" 1.0
        case r of
            Left (_ :: IOException) -> return ()
            Right _                 -> assertFailure "expected IOException"
    , testCase "set invalid key throws exception (int)" $ do
        s <- newSettings
        r <- try $ setInt s "nonexistent.setting" 1
        case r of
            Left (_ :: IOException) -> return ()
            Right _                 -> assertFailure "expected IOException"
    ]
