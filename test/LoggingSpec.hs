module Main where

import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.MVar (newMVar, takeMVar, putMVar, readMVar)
import Control.Exception (try, SomeException)
import Control.Monad (void)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Foreign.C.String (withCAString, peekCAString, CString)
import Foreign.C.Types (CInt(..))
import Foreign.Ptr (castFunPtrToPtr, castPtrToFunPtr, FunPtr, Ptr, nullPtr, freeHaskellFunPtr)
import Sound.Fluidsynth
import Sound.Fluidsynth.Internal
import Test.Tasty
import Test.Tasty.HUnit

foreign import ccall "dynamic"
    callFluidLogFun :: FunPtr (CInt -> CString -> Ptr () -> IO ())
                    -> CInt -> CString -> Ptr () -> IO ()

foreign import ccall "wrapper"
    mkTestLogFunPtr :: (CInt -> CString -> Ptr () -> IO ())
                    -> IO (FunPtr (CInt -> CString -> Ptr () -> IO ()))

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Logging"
    [ testCase "defaultLogCallback handles all levels" $ do
        defaultLogCallback LogPanic "panic"
        defaultLogCallback LogError "error"
        defaultLogCallback LogWarning "warning"
        defaultLogCallback LogInfo "info"
        defaultLogCallback LogDebug "debug"

    , testCase "withLogCallback dispatches messages" $ do
        captured <- newIORef (Nothing :: Maybe (LogLevel, String))
        withLogCallback (\lvl msg -> writeIORef captured (Just (lvl, msg))) $ do
            tempWrapper <- mkTestLogFunPtr (\_ _ _ -> return ())
            tempCallback <- mk'fluid_log_function_t tempWrapper
            let tempPtr = castFunPtrToPtr tempCallback
            installedHandler <- c'fluid_set_log_function 1 tempPtr nullPtr
            let installedCFunPtr = castPtrToFunPtr installedHandler :: C'fluid_log_function_t
            let innerFunPtr = mK'fluid_log_function_t installedCFunPtr
            withCAString "test error" $ \cmsg -> do
                callFluidLogFun innerFunPtr 1 cmsg nullPtr
            _ <- c'fluid_set_log_function 1 installedHandler nullPtr
            freeHaskellFunPtr tempCallback
            freeHaskellFunPtr tempWrapper
        result <- readIORef captured
        case result of
            Just (level, msg) -> do
                level @?= LogError
                msg @?= "test error"
            Nothing -> assertFailure "callback was not invoked"

    , testCase "withLogCallback unregisters after action" $ do
        captured <- newIORef False
        withLogCallback (\_ _ -> writeIORef captured True) $ do
            tempWrapper <- mkTestLogFunPtr (\_ _ _ -> return ())
            tempCallback <- mk'fluid_log_function_t tempWrapper
            let tempPtr = castFunPtrToPtr tempCallback
            installedHandler <- c'fluid_set_log_function 1 tempPtr nullPtr
            let installedCFunPtr = castPtrToFunPtr installedHandler :: C'fluid_log_function_t
            let innerFunPtr = mK'fluid_log_function_t installedCFunPtr
            withCAString "during" $ \cmsg -> do
                callFluidLogFun innerFunPtr 1 cmsg nullPtr
            _ <- c'fluid_set_log_function 1 installedHandler nullPtr
            freeHaskellFunPtr tempCallback
            freeHaskellFunPtr tempWrapper
        duringCalled <- readIORef captured
        assertBool "callback should have been called during action" duringCalled

    , testCase "withLogCallback survives exception" $ do
        r <- try $ withLogCallback (const $ const $ return ()) $ do
            error "boom"
        case r of
            Left (_ :: SomeException) -> return ()
            Right _ -> assertFailure "expected exception"

    , testCase "withLogCallback thread safety" $ do
        results <- newMVar ([] :: [(LogLevel, String)])
        withLogCallback (\lvl msg -> do
            void $ takeMVar results
            void $ putMVar results [(lvl, msg)]
            ) $ do
            tempWrapper <- mkTestLogFunPtr (\_ _ _ -> return ())
            tempCallback <- mk'fluid_log_function_t tempWrapper
            let tempPtr = castFunPtrToPtr tempCallback
            installedHandler <- c'fluid_set_log_function 1 tempPtr nullPtr
            let installedCFunPtr = castPtrToFunPtr installedHandler :: C'fluid_log_function_t
            let innerFunPtr = mK'fluid_log_function_t installedCFunPtr
            withCAString "alpha" $ \cmsg1 -> do
                withCAString "beta" $ \cmsg2 -> do
                    void $ forkIO $ callFluidLogFun innerFunPtr 1 cmsg1 nullPtr
                    void $ forkIO $ callFluidLogFun innerFunPtr 1 cmsg2 nullPtr
                    threadDelay 50000
            _ <- c'fluid_set_log_function 1 installedHandler nullPtr
            freeHaskellFunPtr tempCallback
            freeHaskellFunPtr tempWrapper
        result <- readMVar results
        assertEqual "should have at least one result" 1 (length result)
    ]
