module Main where

import Control.Exception (SomeException, try)
import Sound.Fluidsynth
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Resource"
    [ testCase "withSettings creates settings and passes to action" $ do
        withSettings $ \s -> do
            setNum s "synth.gain" 0.5
            v <- getNum s "synth.gain"
            v @?= Just 0.5
    , testCase "withSettings survives exception" $ do
        r <- try $ withSettings $ \_ -> do
            error "boom"
        case r of
            Left (_ :: SomeException) -> return ()
            Right _                   -> assertFailure "expected exception"
    , testCase "newSynth creates synth and passes to action" $ do
        withSettings $ \s -> do
            synth <- newSynth s
            synthSystemReset synth
            return ()
    , testCase "newSynth survives exception" $ do
        withSettings $ \s -> do
            r <- try $ do
                synth <- newSynth s
                _ <- error "boom"
                return synth
            case r of
                Left (_ :: SomeException) -> return ()
                Right _                  -> assertFailure "expected exception"
    , testCase "withPlayer creates player and passes to action" $ do
        withSettings $ \s -> do
            synth <- newSynth s
            withPlayer synth $ \player -> do
                status <- playerGetStatus player
                status @?= PlayerReady
    , testCase "withPlayer survives exception" $ do
        withSettings $ \s -> do
            synth <- newSynth s
            r <- try $ withPlayer synth $ \_ -> do
                error "boom"
            case r of
                Left (_ :: SomeException) -> return ()
                Right _                  -> assertFailure "expected exception"
    , testCase "withSettings, newSynth, withPlayer chained" $ do
        withSettings $ \s -> do
            synth <- newSynth s
            withPlayer synth $ \player -> do
                _ <- playerGetStatus player
                return ()
    , testCase "nested resources all cleaned up on exception" $ do
        r <- try $ withSettings $ \s -> do
            synth <- newSynth s
            withPlayer synth $ \_ -> do
                error "deep boom"
        case r of
            Left (_ :: SomeException) -> return ()
            Right _                   -> assertFailure "expected exception"
    ]
