{-# LANGUAGE CPP                        #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- Copyright 2014 Google Inc. All rights reserved.
--
-- Licensed under the Apache License, Version 2.0 (the "License"); you may not
-- use this file except in compliance with the License. You may obtain a copy of
-- the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
-- WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
-- License for the specific language governing permissions and limitations under
-- the License.

module Sound.Fluidsynth
    (Channel(..)
    ,Key(..)
    ,Velocity(..)
    ,Program(..)
    ,SoundFontId(..)
    ,Settings()
    ,SynthSettings(..)
    ,newSettings
    ,withSettings
    ,setStr
    ,getStr
    ,setNum
    ,getNum
    ,setInt
    ,getInt
    ,newSynth
    ,withSynth
    ,newDriver
    ,newPlayer
    ,withPlayer
    ,Driver()
    ,Synth()
    ,loadSF
    ,loadSoundFont
    ,unloadSoundFont
    ,Player()
    ,PlayerStatus(..)
    ,playerAdd
    ,playerPlay
    ,playerStop
    ,playerJoin
    ,playerGetStatus
    ,playerSeek
    ,synthNoteOn
    ,synthNoteOff
    ,synthWriteS16
    ,synthWriteFloat
    ,synthProgramChange
    ,synthBankSelect
    ,synthProgramSelect
    ,synthSystemReset
    ,FileRenderer()
    ,newFileRenderer
    ,deleteFileRenderer
    ,fileRendererProcessBlock
    ,renderToWav
    ,Event()
    ,eventNoteOn
    ,eventNoteOff
    ,PCMBuffer(..)
    ,pcmBufferFromSynth
    ,getSampleRate
    ,renderPCM
    ,renderMidi
    ,LogLevel(..)
    ,LogCallback
    ,defaultLogCallback
    ,withLogCallback)
where

import           Control.Concurrent        (threadDelay)
import           Control.Exception         (bracket, finally)
import           Control.Monad
import           Data.Int                  (Int16)
import qualified Data.Map                  as M
import qualified Data.Vector.Storable      as V
import           Foreign.C.String
import           Foreign.C.Types           (CDouble, CFloat, CInt (..), CShort,
                                            CUInt)
import           Foreign.ForeignPtr
import           Foreign.Marshal.Alloc     (alloca, finalizerFree, free,
                                            mallocBytes)
import           Foreign.Ptr
import           Foreign.Storable          (peek, sizeOf)
import           System.Directory
import           System.IO.Error

import           Data.IORef                (IORef, newIORef, readIORef,
                                            writeIORef)
import           Sound.Fluidsynth.Internal
import           System.IO                 (hPutStrLn, stderr)
import           System.IO.Unsafe          (unsafePerformIO)

-- | Whether to register C finalizers for FluidSynth objects.
-- On macOS, we skip cleanup to avoid a FluidSynth exit segfault
-- that would prevent HPC from writing coverage .tix files.
-- The OS will reclaim all memory when the process exits.
cleanupEnabled :: Bool
#if defined(darwin_HOST_OS)
cleanupEnabled = False
#else
cleanupEnabled = True
#endif

-- | Conditionally attach a finalizer to a ForeignPtr.
-- On macOS (where cleanupEnabled is False), no finalizer is registered,
-- preventing the segfault during process exit.
foreignPtrWithCleanup :: FinalizerPtr a -> Ptr a -> IO (ForeignPtr a)
foreignPtrWithCleanup finalizer ptr
    | cleanupEnabled = newForeignPtr finalizer ptr
    | otherwise      = newForeignPtr_ ptr

newtype Settings = Settings (ForeignPtr C'fluid_settings_t)

-- | Settings prepared for synth creation.
newtype SynthSettings = SynthSettings Settings
data Synth = Synth (ForeignPtr C'fluid_settings_t) (M.Map FilePath CUInt)
             (ForeignPtr C'fluid_synth_t)
newtype Driver = Driver (ForeignPtr C'fluid_audio_driver_t)
data Player = Player Synth (ForeignPtr C'fluid_player_t)
newtype Event = Event (ForeignPtr C'fluid_event_t)

newtype Channel = Channel Int
    deriving (Enum, Eq, Integral, Ord, Num, Real)
newtype Key = Key Int
    deriving (Enum, Eq, Integral, Ord, Num, Real)
newtype Velocity = Velocity Int
    deriving (Enum, Eq, Integral, Ord, Num, Real)
newtype Program = Program Int
    deriving (Enum, Eq, Integral, Ord, Num, Real)
newtype SoundFontId = SoundFontId Int
    deriving (Eq, Show, Num)

data PlayerStatus = PlayerReady | PlayerPlaying | PlayerStopping | PlayerDone
    deriving (Eq, Show)

-- | FluidSynth log levels.
data LogLevel = LogPanic | LogError | LogWarning | LogInfo | LogDebug
    deriving (Eq, Ord, Show, Enum, Bounded)

-- | Callback type for FluidSynth log messages.
type LogCallback = LogLevel -> String -> IO ()

-- | Default log callback that prints to stderr with a @[FLUID_<LEVEL>]@ prefix.
defaultLogCallback :: LogCallback
defaultLogCallback level msg =
    hPutStrLn stderr $ "[" ++ prefix ++ "] " ++ msg
  where
    prefix = case level of
        LogPanic   -> "FLUID_PANIC"
        LogError   -> "FLUID_ERR"
        LogWarning -> "FLUID_WARN"
        LogInfo    -> "FLUID_INFO"
        LogDebug   -> "FLUID_DBG"

{-# NOINLINE logCallbackRef #-}
logCallbackRef :: IORef (Maybe LogCallback)
logCallbackRef = unsafePerformIO (newIORef Nothing)

foreign import ccall "wrapper"
    mkLogCallbackFunPtr :: (CInt -> CString -> Ptr () -> IO ())
                        -> IO (FunPtr (CInt -> CString -> Ptr () -> IO ()))

-- | Wrapper invoked by FluidSynth from C. Reads the current callback from
-- the 'logCallbackRef' and dispatches to it.
logCallbackCWrapper :: CInt -> CString -> Ptr () -> IO ()
logCallbackCWrapper level msg _ = do
    mbCB <- readIORef logCallbackRef
    case mbCB of
        Nothing -> return ()
        Just cb -> do
            haskellMsg <- peekCAString msg
            cb (toEnum (fromIntegral level)) haskellMsg

-- | Register a log callback for the duration of an action.
--
-- The callback is installed via 'fluid_set_log_function' for all five log
-- levels. The previous handler is restored when the action completes or
-- throws an exception. The underlying C 'FunPtr' is freed on exit.
withLogCallback :: LogCallback -> IO a -> IO a
withLogCallback cb action = do
    wrapperFunPtr <- mkLogCallbackFunPtr logCallbackCWrapper
    cCallback <- mk'fluid_log_function_t wrapperFunPtr
    let callbackPtr = castFunPtrToPtr cCallback :: Ptr C'fluid_log_function_t
    oldPtrs <- forM [0 .. 4] $ \level -> do
        oldPtr <- c'fluid_set_log_function level callbackPtr nullPtr
        return (level, oldPtr)
    writeIORef logCallbackRef (Just cb)
    action `finally` do
        writeIORef logCallbackRef Nothing
        forM_ oldPtrs $ \(level, oldPtr) ->
            void $ c'fluid_set_log_function level oldPtr nullPtr
        freeHaskellFunPtr cCallback
        freeHaskellFunPtr wrapperFunPtr

newSettings :: IO Settings
newSettings = do
    ptr <- c'new_fluid_settings
    settings <- foreignPtrWithCleanup p'delete_fluid_settings ptr
    return $! Settings settings

setStr :: Settings -> String -> String -> IO ()
setStr (Settings settings) key val =
    withForeignPtr settings $ \ptr ->
        withCAString key $ \ckey ->
            withCAString val $ \cval -> do
                ret <- c'fluid_settings_setstr ptr ckey cval
                when (ret /= 0) $
                    ioError $ userError $ "Failed to set string setting: " ++ key

getStr :: Settings -> String -> IO (Maybe String)
getStr (Settings settings) key =
    withForeignPtr settings $ \ptr ->
        withCAString key $ \ckey ->
            alloca $ \pstr -> do
                ret <- c'fluid_settings_dupstr ptr ckey pstr
                cstr <- peek pstr
                if ret /= 0 || cstr == nullPtr
                    then return Nothing
                    else do
                        s <- peekCAString cstr
                        free cstr
                        return (Just s)

setNum :: Settings -> String -> Double -> IO ()
setNum (Settings settings) key val =
    withForeignPtr settings $ \ptr ->
        withCAString key $ \ckey -> do
            ret <- c'fluid_settings_setnum ptr ckey (realToFrac val)
            when (ret /= 0) $
                ioError $ userError $ "Failed to set numeric setting: " ++ key

getNum :: Settings -> String -> IO (Maybe Double)
getNum (Settings settings) key =
    withForeignPtr settings $ \ptr ->
        withCAString key $ \ckey ->
            alloca $ \pnum -> do
                ret <- c'fluid_settings_getnum ptr ckey pnum
                if ret /= 0
                    then return Nothing
                    else do
                        v <- peek pnum
                        return $ Just (realToFrac v :: Double)

setInt :: Settings -> String -> Int -> IO ()
setInt (Settings settings) key val =
    withForeignPtr settings $ \ptr ->
        withCAString key $ \ckey -> do
            ret <- c'fluid_settings_setint ptr ckey (fromIntegral val)
            when (ret /= 0) $
                ioError $ userError $ "Failed to set integer setting: " ++ key

getInt :: Settings -> String -> IO (Maybe Int)
getInt (Settings settings) key =
    withForeignPtr settings $ \ptr ->
        withCAString key $ \ckey ->
            alloca $ \pint -> do
                ret <- c'fluid_settings_getint ptr ckey pint
                if ret /= 0
                    then return Nothing
                    else do
                        v <- peek pint
                        return $ Just (fromIntegral v :: Int)

newSynth :: Settings -> IO Synth
newSynth (Settings settings) = do
    withForeignPtr settings $ \ptr -> do
        ptr' <- c'new_fluid_synth ptr
        synth <- foreignPtrWithCleanup p'delete_fluid_synth ptr'
        return $! Synth settings M.empty synth

newDriver :: Synth -> IO Driver
newDriver (Synth settings _ synth) = do
    withForeignPtr settings $ \ptr -> do
        withForeignPtr synth $ \ptr' -> do
            ptr'' <- c'new_fluid_audio_driver ptr ptr'
            driver <- foreignPtrWithCleanup p'delete_fluid_audio_driver ptr''
            return $! Driver driver

newPlayer :: Synth -> IO Player
newPlayer s@(Synth _ _ synth) = do
    withForeignPtr synth $ \ptr -> do
        ptr' <- c'new_fluid_player ptr
        player <- foreignPtrWithCleanup p'delete_fluid_player ptr'
        return $! Player s player

-- | Create settings, perform an action, and release settings.
-- Settings are released when the action completes or throws.
withSettings :: (Settings -> IO a) -> IO a
withSettings = bracket newSettings (const $ return ())

-- | Create a synth from settings, load a SoundFont, perform an action,
-- and release the synth.  The synth is released when the action completes
-- or throws.
withSynth :: SynthSettings -> FilePath -> (Synth -> IO a) -> IO a
withSynth (SynthSettings settings) sfPath action =
    bracket (newSynth settings) (const $ return ()) $ \synth -> do
        _ <- loadSoundFont synth sfPath
        action synth

-- | Create a player from synth, perform an action, and release the player.
-- The player is stopped and released when the action completes or throws.
withPlayer :: Synth -> (Player -> IO a) -> IO a
withPlayer synth = bracket (newPlayer synth) (const $ return ())

loadSF :: Synth -> String -> IO Synth
loadSF (Synth settings sfmap synth) path = do
    abspath <- canonicalizePath path
    let msfid = M.lookup abspath sfmap
    withForeignPtr synth $ \ptr ->
        withCAString abspath $ \cstr -> case msfid of
            Just sfid -> do
                err <- c'fluid_synth_sfreload ptr sfid
                if err == -1
                    then ioError $ userError "Couldn't reload soundfont!"
                    else return $ Synth settings sfmap synth
            Nothing -> do
                sfid <- c'fluid_synth_sfload ptr cstr 1
                let sfmap' = M.insert abspath (fromIntegral sfid) sfmap
                if sfid == -1
                    then ioError $ userError "Couldn't load soundfont!"
                    else return $ Synth settings sfmap' synth

unloadSF :: Synth -> String -> IO Synth
unloadSF (Synth settings sfmap synth) path = do
    abspath <- canonicalizePath path
    case M.lookup abspath sfmap of
        Nothing -> ioError $ userError "Soundfont not loaded!"
        Just sfid -> do
            withForeignPtr synth $ \ptr -> do
                err <- c'fluid_synth_sfunload ptr sfid 1
                let sfmap' = M.delete abspath sfmap
                if err == -1
                    then ioError $ userError "Couldn't unload soundfont!"
                    else return $ Synth settings sfmap' synth

synthNoteOn :: Synth -> Channel -> Key -> Velocity -> IO ()
synthNoteOn (Synth _ _ synth) c k v =
    void $ withForeignPtr synth $ \ptr ->
        c'fluid_synth_noteon ptr (fromIntegral c) (fromIntegral k)
            (fromIntegral v)

synthNoteOff :: Synth -> Channel -> Key -> IO ()
synthNoteOff (Synth _ _ synth) c k =
    withForeignPtr synth $ \ptr ->
        void $ c'fluid_synth_noteoff ptr (fromIntegral c) (fromIntegral k)

-- | Render audio samples from the synth.
--
-- Interleaved stereo, signed 16-bit, little-endian.
-- The returned vector has length = @nframes * 2@
-- (left and right channels interleaved: L0, R0, L1, R1, ...).
-- Throws 'IOException' if the underlying FluidSynth call fails.
synthWriteS16 :: Synth -> Int -> IO (V.Vector Int16)
synthWriteS16 (Synth _ _ synth) nframes = do
    let nsamples = nframes * 2
        bufSize = nsamples * sizeOf (undefined :: CShort)
    buf <- mallocBytes bufSize
    ret <- withForeignPtr synth $ \ptr ->
        c'fluid_synth_write_s16 ptr (fromIntegral nframes) (castPtr buf) 0 2 (castPtr buf) 1 2
    if ret /= 0
        then do free buf; ioError $ userError "fluid_synth_write_s16 failed"
        else do
            fptr <- newForeignPtr finalizerFree (castPtr buf :: Ptr Int16)
            return $ V.unsafeFromForeignPtr fptr 0 nsamples

-- | Render audio samples from the synth as floats.
--
-- Interleaved stereo, 32-bit float.
-- The returned vector has length = @nframes * 2@
-- (left and right channels interleaved: L0, R0, L1, R1, ...).
-- Throws 'IOException' if the underlying FluidSynth call fails.
synthWriteFloat :: Synth -> Int -> IO (V.Vector CFloat)
synthWriteFloat (Synth _ _ synth) nframes = do
    let nsamples = nframes * 2
        bufSize = nsamples * sizeOf (undefined :: CFloat)
    buf <- mallocBytes bufSize
    let fbuf = castPtr buf :: Ptr CFloat
    ret <- withForeignPtr synth $ \ptr ->
        c'fluid_synth_write_float ptr (fromIntegral nframes) fbuf 0 2 fbuf 1 2
    if ret /= 0
        then do free buf; ioError $ userError "fluid_synth_write_float failed"
        else do
            fptr <- newForeignPtr finalizerFree (castPtr buf :: Ptr CFloat)
            return $ V.unsafeFromForeignPtr fptr 0 nsamples

-- | Render audio samples from the synth in a self-describing buffer.
--
-- PCMBuffer bundles signed 16-bit, little-endian, interleaved audio samples
-- together with their sample rate and channel count. The buffer owns its data
-- and is directly consumable by @ffmpeg-audio@ without any conversion.
--
-- Sample layout: @[L, R, L, R, ...]@ for stereo (2 channels).
data PCMBuffer = PCMBuffer
    { pcmSampleRate :: !Int
    , pcmChannels   :: !Int
    , pcmSamples    :: !(V.Vector Int16)
    }
    deriving (Eq, Show)

-- | Create a 'PCMBuffer' by rendering audio from a synth.
--
-- The sample rate is passed explicitly (e.g., from the @synth.sample-rate@
-- setting). The number of frames to render is @nframes@. Output is always
-- stereo (2 channels, interleaved).
--
-- The returned buffer owns its sample data; no mutable buffers are exposed.
pcmBufferFromSynth :: Synth -> Int -> Int -> IO PCMBuffer
pcmBufferFromSynth synth sampleRate nframes = do
    samples <- synthWriteS16 synth nframes
    return $ PCMBuffer sampleRate 2 samples

-- | Look up the sample rate from a 'Settings' object.
--
-- Returns @Nothing@ if the setting is not available (e.g., if FluidSynth
-- does not support querying it).
getSampleRate :: Settings -> IO (Maybe Double)
getSampleRate = flip getNum "synth.sample-rate"

-- | Convenience: get the sample rate from a synth's settings.
-- Uses the settings ForeignPtr already owned by the Synth (safe -
-- no duplicate finalizer).  Falls back to 44100 if the setting
-- cannot be read.
getSynthSampleRate :: Synth -> IO Int
getSynthSampleRate (Synth sf _ _) =
    withForeignPtr sf $ \ptr ->
        withCAString "synth.sample-rate" $ \ckey ->
            alloca $ \pval -> do
                err <- c'fluid_settings_getnum ptr ckey pval
                if err == 0
                    then round . realToFrac <$> peek pval
                    else return 44100

-- | Render PCM audio from the synth, auto-detecting the sample rate.
--
-- This is a high-level convenience that reads @synth.sample-rate@ from
-- the synth's settings and renders @nframes@ of stereo, signed 16-bit,
-- interleaved audio.  Falls back to 44100 if the setting is unavailable.
--
-- @
-- buf <- renderPCM synth 44100   -- one second of audio
-- @
renderPCM :: Synth -> Int -> IO PCMBuffer
renderPCM synth nframes = do
    sampleRate <- getSynthSampleRate synth
    samples <- synthWriteS16 synth nframes
    return $ PCMBuffer sampleRate 2 samples

-- | Render an entire MIDI file to PCM audio.
--
-- Creates a player, adds the MIDI file, plays it, renders audio in blocks
-- while the player is running, waits for the player to finish, then returns
-- the complete PCM buffer (stereo, signed 16-bit, interleaved).
--
-- Throws 'IOException' if the MIDI file cannot be loaded or the player fails.
renderMidi :: Synth -> FilePath -> IO PCMBuffer
renderMidi synth@(Synth _ _ synthFPtr) path = do
    exists <- doesFileExist path
    unless exists $
        ioError $ mkIOError doesNotExistErrorType
            ("renderMidi: MIDI file not found: " ++ path) Nothing Nothing
    -- Create player with no finalizer so we can delete it explicitly
    playerFPtr <- withForeignPtr synthFPtr $ \ptr -> do
        ptr' <- c'new_fluid_player ptr
        newForeignPtr_ ptr'
    let player = Player synth playerFPtr
    playerAdd player path
    playerPlay player
    threadDelay 50000
    samples <- collectWhilePlaying synth player 8192
    playerJoin player
    -- Destroy player before tail render to avoid use-after-free
    withForeignPtr playerFPtr $ \ptr -> c'delete_fluid_player ptr
    tailSamples <- synthWriteS16 synth 4096
    sampleRate <- getSynthSampleRate synth
    return $ PCMBuffer sampleRate 2 (samples V.++ tailSamples)

-- | A file renderer that writes synth audio directly to a file configured
-- in the synth's settings (e.g., @audio.file.name@, @audio.file.type@,
-- @audio.file.sample-format@).
--
-- Keeps a reference to the underlying 'fluid_synth_t' 'ForeignPtr' to ensure
-- correct finalization order (the renderer must be destroyed before the synth).
data FileRenderer = FileRenderer (ForeignPtr C'fluid_synth_t) (ForeignPtr C'fluid_file_renderer_t)

-- | Create a file renderer for the given synth.
--
-- The output file path and format are controlled by the synth's settings.
-- At minimum, you should set @audio.file.name@ to the desired output path.
newFileRenderer :: Synth -> IO FileRenderer
newFileRenderer (Synth _ _ synth) = do
    ptr <- withForeignPtr synth c'new_fluid_file_renderer
    -- Use newForeignPtr_ (no finalizer) because the finalization order
    -- relative to the synth's ForeignPtr is unpredictable with GC.
    -- Callers should use `deleteFileRenderer` to explicitly free the
    -- renderer before the synth goes out of scope.
    fPtr <- newForeignPtr_ ptr
    return $ FileRenderer synth fPtr

-- | Explicitly delete a 'FileRenderer'.
--
-- This should be called before the associated 'Synth' goes out of scope
-- to ensure proper resource ordering. After calling this, the renderer
-- must not be used again.
deleteFileRenderer :: FileRenderer -> IO ()
deleteFileRenderer (FileRenderer synth fPtr) = do
    withForeignPtr fPtr $ \ptr -> c'delete_fluid_file_renderer ptr
    touchForeignPtr synth

-- | Process one block of audio through the file renderer.
--
-- Returns 'True' if more data is available ('FLUID_OK'),
-- 'False' if rendering is complete or an error occurred ('FLUID_FAILED').
fileRendererProcessBlock :: FileRenderer -> IO Bool
fileRendererProcessBlock (FileRenderer _synth fPtr) = do
    result <- withForeignPtr fPtr c'fluid_file_renderer_process_block
    return (result == 0)

-- | Convenience: render a MIDI file to a WAV file using the file renderer.
--
-- Configures the synth for file output, loads the soundfont, plays the
-- MIDI file, and renders audio to the specified WAV path. Blocks until
-- rendering is complete.
renderToWav :: Synth -> String -> FilePath -> IO ()
renderToWav synth sfPath midiPath = do
    let Synth settings _ _ = synth
    withForeignPtr settings $ \sptr ->
        withCAString "audio.file.name" $ \key ->
            withCAString midiPath $ \val -> do
                ret <- c'fluid_settings_setstr sptr key val
                when (ret /= 0) $
                    ioError $ userError "renderToWav: failed to set audio.file.name"
    _ <- loadSoundFont synth sfPath
    player <- newPlayer synth
    playerAdd player midiPath
    renderer <- newFileRenderer synth
    playerPlay player
    let loop = do
            more <- fileRendererProcessBlock renderer
            when more loop
    loop

-- | Render audio samples from the synth.
--
-- CollectWhilePlaying helper.
-- Renders in blocks and accumulates them into a list, then concatenates.
collectWhilePlaying :: Synth -> Player -> Int -> IO (V.Vector Int16)
collectWhilePlaying synth player blockSize = do
    blocks <- go []
    return $ V.concat blocks
  where
    go acc = do
        status <- playerGetStatus player
        if status == PlayerDone
            then return (reverse acc)
            else do
                block <- synthWriteS16 synth blockSize
                go (block : acc)

synthProgramChange :: Synth -> Channel -> Program -> IO ()
synthProgramChange (Synth _ _ synth) c p =
    void $ withForeignPtr synth $ \ptr ->
        c'fluid_synth_program_change ptr (fromIntegral c) (fromIntegral p)

synthBankSelect :: Synth -> Channel -> Int -> IO ()
synthBankSelect (Synth _ _ synth) c b =
    void $ withForeignPtr synth $ \ptr ->
        c'fluid_synth_bank_select ptr (fromIntegral c) (fromIntegral b)

-- | Select a program for a channel from a specific SoundFont, bank, and
-- program number. Throws 'IOException' if the SoundFont cannot be found or
-- the selection fails.
synthProgramSelect :: Synth -> Channel -> SoundFontId -> Int -> Int -> IO ()
synthProgramSelect (Synth _ _ synth) (Channel c) (SoundFontId sfontId) bank prog =
    withForeignPtr synth $ \ptr -> do
        sfptr <- c'fluid_synth_get_sfont_by_id ptr (fromIntegral sfontId)
        if sfptr == nullPtr
            then ioError $ userError $ "synthProgramSelect: soundfont not found: " ++ show sfontId
            else do
                ret <- c'fluid_synth_program_select ptr (fromIntegral c) sfptr
                         (fromIntegral bank) (fromIntegral prog)
                when (ret /= 0) $ do
                    errStr <- c'fluid_synth_error ptr
                    msg <- peekCAString errStr
                    ioError $ userError $ "synthProgramSelect: " ++ msg

-- | Reset the synth to its default state (all controllers reset, notes off).
synthSystemReset :: Synth -> IO ()
synthSystemReset (Synth _ _ synth) =
    void $ withForeignPtr synth $ \ptr ->
        c'fluid_synth_system_reset ptr

-- | Load a SoundFont into the synth, returning its SoundFont ID.
--
-- Wraps 'loadSF' and resolves the loaded ID from the synth's internal SF map.
-- Throws 'IOException' (via 'loadSF') if the file cannot be loaded or is not
-- found. Safe to call repeatedly; already-loaded SoundFonts are reloaded
-- rather than duplicated.
loadSoundFont :: Synth -> FilePath -> IO SoundFontId
loadSoundFont synth path = do
    Synth _ sfmap _ <- loadSF synth path
    abspath <- canonicalizePath path
    case M.lookup abspath sfmap of
        Just sfid -> return (SoundFontId (fromIntegral sfid))
        Nothing   -> ioError $ userError "loadSoundFont: soundfont not found after load"

-- | Unload a previously-loaded SoundFont from the synth.
-- Throws 'IOException' if the SoundFont was not loaded or the underlying call
-- fails.
unloadSoundFont :: Synth -> FilePath -> IO ()
unloadSoundFont synth path = void $ unloadSF synth path

-- | Add a MIDI file to the player's playlist. Throws 'IOException' if the
-- file cannot be added.
playerAdd :: Player -> String -> IO ()
playerAdd (Player _ player) path = do
    withForeignPtr player $ \ptr ->
        withCAString path $ \cstr -> do
            ret <- c'fluid_player_add ptr cstr
            when (ret /= 0) $
                ioError $ userError $ "Failed to add MIDI file: " ++ path

-- | Start playback. Throws 'IOException' if the player fails to start.
playerPlay :: Player -> IO ()
playerPlay (Player _ player) = do
    ret <- withForeignPtr player c'fluid_player_play
    when (ret /= 0) $
        ioError $ userError "Failed to play player"

-- | Stop playback asynchronously. Throws 'IOException' on failure.
playerStop :: Player -> IO ()
playerStop (Player _ player) = do
    ret <- withForeignPtr player c'fluid_player_stop
    when (ret /= 0) $
        ioError $ userError "Failed to stop player"

-- | Block until the player finishes playback. Throws 'IOException' on failure.
playerJoin :: Player -> IO ()
playerJoin (Player _ player) = do
    ret <- withForeignPtr player c'fluid_player_join
    when (ret /= 0) $
        ioError $ userError "Failed to join player"

-- | Query the player's current status.
playerGetStatus :: Player -> IO PlayerStatus
playerGetStatus (Player _ player) = do
    status <- withForeignPtr player c'fluid_player_get_status
    return $ case status of
        0 -> PlayerReady
        1 -> PlayerPlaying
        2 -> PlayerStopping
        _ -> PlayerDone

-- | Seek the player to the given tick position. Throws 'IOException' on
-- failure.
playerSeek :: Player -> Int -> IO ()
playerSeek (Player _ player) ticks = do
    ret <- withForeignPtr player $ \ptr ->
        c'fluid_player_seek ptr (fromIntegral ticks)
    when (ret /= 0) $
        ioError $ userError "Failed to seek player"

-- | Make an event.
--
--   Since the event is unpatterned, it isn't going to be very useful. End
--   users almost certainly want the patterned event creators.
newEvent :: IO Event
newEvent = do
    ptr <- c'new_fluid_event
    event <- foreignPtrWithCleanup p'delete_fluid_event ptr
    return $! Event event

-- | Make an event and call an action on it.
--
--   Just a combinator meant to help write the following bindings.
withNewEvent :: (Ptr C'fluid_event_t -> IO ()) -> IO Event
withNewEvent action = do
    e@(Event event) <- newEvent
    withForeignPtr event action
    return e

eventNoteOn :: Channel -> Key -> Velocity -> IO Event
eventNoteOn c k v = withNewEvent $ \ptr ->
    c'fluid_event_noteon ptr (fromIntegral c) (fromIntegral k)
        (fromIntegral v)

eventNoteOff :: Channel -> Key -> IO Event
eventNoteOff c k = withNewEvent $ \ptr ->
    c'fluid_event_noteoff ptr (fromIntegral c) (fromIntegral k)

eventPitchSens :: Channel -> Int -> IO Event
eventPitchSens c amount = withNewEvent $ \ptr ->
    c'fluid_event_pitch_wheelsens ptr (fromIntegral c) (fromIntegral amount)

eventPitchBend :: Channel -> Int -> IO Event
eventPitchBend c amount = withNewEvent $ \ptr ->
    c'fluid_event_pitch_bend ptr (fromIntegral c) (fromIntegral amount)

eventProgramControl :: Channel -> Program -> IO Event
eventProgramControl c p = withNewEvent $ \ptr ->
    c'fluid_event_program_change ptr (fromIntegral c) (fromIntegral p)

eventVolume :: Channel -> Int -> IO Event
eventVolume c amount = withNewEvent $ \ptr ->
    c'fluid_event_volume ptr (fromIntegral c) (fromIntegral amount)
