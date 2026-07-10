-- | End-to-end pipeline example.
--
-- Demonstrates the full target pipeline:
--
-- @
-- Standard MIDI file  ->  hsfluidsynth (renderMidi)  ->  PCMBuffer  ->  raw S16 LE file
-- @
--
-- The emitted @.raw@ file contains interleaved stereo, signed 16-bit,
-- little-endian PCM samples. It is directly consumable by @ffmpeg-audio@'s
-- 'encodeMp3' (or by the @ffmpeg@ CLI) -- for example:
--
-- @
-- ffmpeg -f s16le -ar 44100 -ac 2 -i out.raw -c:a libmp3lame -q:a 2 out.mp3
-- @
--
-- Usage:
--
-- @
-- render-midi-example SOUNDFONT.sf2 input.mid output.raw
-- @
module Main (main) where

import qualified Data.ByteString as B
import Data.Int (Int16)
import qualified Data.Vector.Storable as V
import Data.Word (Word8)
import System.Environment (getArgs, getProgName)
import Sound.Fluidsynth

main :: IO ()
main = do
    args <- getArgs
    case args of
        [sfPath, midiPath, outPath] -> render sfPath midiPath outPath
        _ -> do
            name <- getProgName
            putStrLn $ "Usage: " ++ name ++ " SOUNDFONT.sf2 input.mid output.raw"

render :: FilePath -> FilePath -> FilePath -> IO ()
render sfPath midiPath outPath =
    withSettings $ \settings ->
        withSynth (SynthSettings settings) sfPath $ \synth -> do
            buf <- renderMidi synth midiPath
            putStrLn $ "Rendered " ++ show (V.length (pcmSamples buf))
                    ++ " samples (" ++ show (pcmChannels buf) ++ " ch @ "
                    ++ show (pcmSampleRate buf) ++ " Hz)"
            writeRawS16 outPath buf
            putStrLn $ "Wrote raw PCM to " ++ outPath

-- | Write a 'PCMBuffer' to disk as raw interleaved signed 16-bit
-- little-endian samples. The resulting file is consumable by @ffmpeg-audio@
-- (see module Haddock) or the @ffmpeg@ CLI as
-- @-f s16le -ar <sample-rate> -ac <channels>@.
writeRawS16 :: FilePath -> PCMBuffer -> IO ()
writeRawS16 path buf =
    B.writeFile path (B.pack (V.toList bytes))
  where
    -- Per Int16 sample, emit low byte then high byte (little-endian).
    bytes = V.concatMap le16 (pcmSamples buf)
    le16 :: Int16 -> V.Vector Word8
    le16 w = V.fromList [fromIntegral w, fromIntegral (w `div` 256)]
