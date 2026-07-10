module Main where

import Sound.Fluidsynth
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Player"
    [ testCase "newPlayer creates a player" $ do
        s <- newSettings
        synth <- newSynth s
        player <- newPlayer synth
        return ()
    , testCase "player play/stop/join cycle" $ do
        s <- newSettings
        synth <- newSynth s
        player <- newPlayer synth
        playerAdd player "test/data/test.mid"
        playerPlay player
        playerStop player
        playerJoin player
    , testCase "player play/stop/play again" $ do
        s <- newSettings
        synth <- newSynth s
        player <- newPlayer synth
        playerAdd player "test/data/test.mid"
        playerPlay player
        playerStop player
        playerJoin player
        playerAdd player "test/data/test.mid"
        playerPlay player
        playerStop player
        playerJoin player
    , testCase "player status during phases" $ do
        s <- newSettings
        synth <- newSynth s
        player <- newPlayer synth
        status1 <- playerGetStatus player
        status1 @?= PlayerReady
        playerAdd player "test/data/test.mid"
        playerPlay player
        status2 <- playerGetStatus player
        status2 @?= PlayerPlaying
        playerStop player
        playerJoin player
        status3 <- playerGetStatus player
        status3 @?= PlayerDone
    , testCase "player cleanup via ForeignPtr" $ do
        s <- newSettings
        synth <- newSynth s
        _ <- newPlayer synth
        return ()
    ]
