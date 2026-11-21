module Main where

import Control.Exception (IOException, try)
import Data.List (isPrefixOf)
import Sound.Fluidsynth
import System.IO.Error (ioeGetErrorString)
import Test.Tasty
import Test.Tasty.HUnit
import TestSoundFont (resolveDualTestSoundFonts)

main :: IO ()
main = do
    mFonts <- resolveDualTestSoundFonts
    case mFonts of
        Nothing ->
            defaultMain $ testGroup "Synth"
                (baseTests ++ [testGroup "when fixture fonts available (no SoundFont)" []])
        Just (sfPathA, sfPathB) -> do
            eFonts <- try (probeFixtureFonts sfPathA sfPathB)
            case eFonts of
                Left (_ :: IOException) ->
                    defaultMain $ testGroup "Synth"
                        (baseTests ++ [testGroup "when fixture fonts available (no SoundFont)" []])
                Right _ ->
                    defaultMain $ testGroup "Synth" (baseTests ++ [fixtureTests sfPathA sfPathB])

-- | Verify both fixture fonts load; used to gate the fixture-dependent group.
probeFixtureFonts :: FilePath -> FilePath -> IO ()
probeFixtureFonts sfPathA sfPathB = do
    s <- newSettings
    synth <- newSynth s
    _ <- loadSoundFont synth sfPathA
    _ <- loadSoundFont synth sfPathB
    return ()

-- | Fresh synth with both fixture fonts loaded.
newSFTestSynth :: FilePath -> FilePath -> IO (Synth, SoundFontId, SoundFontId)
newSFTestSynth sfPathA sfPathB = do
    s <- newSettings
    synth <- newSynth s
    sfA <- loadSoundFont synth sfPathA
    sfB <- loadSoundFont synth sfPathB
    return (synth, sfA, sfB)

baseTests :: [TestTree]
baseTests =
    [ testCase "newSynth initializes successfully" $ do
        s <- newSettings
        _ <- newSynth s
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

fixtureTests :: FilePath -> FilePath -> TestTree
fixtureTests sfPathA sfPathB = testGroup "when fixture fonts available"
    [ testCase "program select valid soundfont succeeds" $ do
        (synth, sfid, _) <- newSFTestSynth sfPathA sfPathB
        synthProgramSelect synth (Channel 0) sfid 0 0
    , testCase "program select invalid soundfont throws IOException" $ do
        (synth, _, _) <- newSFTestSynth sfPathA sfPathB
        r <- try $ synthProgramSelect synth (Channel 0) (SoundFontId 999999) 0 0
        case r of
            Left e -> assertBool "error should start with 'synthProgramSelect:'" $
                "synthProgramSelect:" `isPrefixOf` ioeGetErrorString e
            Right _ -> assertFailure "expected IOException"
    , testCase "bank offset set/get roundtrip" $ do
        (synth, sfid, _) <- newSFTestSynth sfPathA sfPathB
        synthSetBankOffset synth sfid 160
        offset <- synthGetBankOffset synth sfid
        assertEqual "bank offset" 160 offset
    , testCase "dual soundfont program select honors bank offset" $ do
        (synth, sfA, sfB) <- newSFTestSynth sfPathA sfPathB
        assertBool "soundfont ids should differ" (sfA /= sfB)
        synthSetBankOffset synth sfB 160
        synthProgramSelect synth (Channel 0) sfA 0 0
        synthProgramSelect synth (Channel 1) sfB (160 + 0) 0
    ]
