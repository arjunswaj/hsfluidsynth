module Main where

import Control.Monad (when)
import Sound.Fluidsynth
import System.Directory (doesFileExist, removeFile)
import System.IO.Error (catchIOError)
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "FileRenderer"
    [ testCase "file renderer creates output file" $ do
        let outPath = "/tmp/fluidsynth_fr_test.wav"
        removeFile outPath `catchIOError` const (return ())
        s <- newSettings
        setStr s "audio.file.name" outPath
        synth <- newSynth s
        renderer <- newFileRenderer synth
        let go 0 = return ()
            go n = do
                more <- fileRendererProcessBlock renderer
                when more $ go (n - 1)
        go 10
        deleteFileRenderer renderer
        fileExists <- doesFileExist outPath
        assertBool "output WAV file should exist" fileExists
        removeFile outPath `catchIOError` const (return ())
    , testCase "newFileRenderer and processBlock succeed" $ do
        let outPath = "/tmp/fluidsynth_fr_test2.wav"
        removeFile outPath `catchIOError` const (return ())
        s <- newSettings
        setStr s "audio.file.name" outPath
        synth <- newSynth s
        renderer <- newFileRenderer synth
        more <- fileRendererProcessBlock renderer
        deleteFileRenderer renderer
        assertBool "first block should succeed" more
        removeFile outPath `catchIOError` const (return ())
    ]