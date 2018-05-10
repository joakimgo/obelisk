{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
module Obelisk.Command.CLI where

import Control.Monad.Catch (finally)
import Control.Monad.Reader (MonadIO, liftIO)
import Data.List (isInfixOf)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import GHC.IO.Handle.FD (stdout)
import System.Environment (getArgs)
import System.IO (hFlush, hIsTerminalDevice)

import System.Console.ANSI
import System.Console.Questioner (dots1Spinner, stopIndicator)

import Obelisk.App (MonadObelisk)

-- TODO: This doesn't handle the put* line of functions below, in that: when we print anything while the
-- spinner is already running, it won't appear correctly in the terminal. The exception is `failWith` which
-- raises an exception (that gets handled properly here). One solution to fix this problem is to run a
-- singleton spinner thread and interact with it in order to print something.
withSpinner
  :: MonadObelisk m
  => String  -- ^ Text to print alongside the spinner
  -> Maybe String  -- ^ Optional text to print at the end
  -> m a  -- ^ Action to run and wait for
  -> m a
withSpinner s e f = do
  isTerm <- liftIO $ hIsTerminalDevice stdout
  -- When running in shell completion, disable the spinner. TODO: Do this using ReaderT and config.
  inBashCompletion <- liftIO $ isInfixOf "completion" . unwords <$> getArgs
  case not isTerm || inBashCompletion of
    True -> f
    False -> do
      spinner <- liftIO $ dots1Spinner (1000 * 200) s
      result <- finally f $ do
        liftIO $ stopIndicator spinner
      case e of
        Just exitMsg -> putInfo $ T.pack exitMsg
        Nothing -> liftIO $ hFlush stdout
      return result

data Level = Level_Normal | Level_Warning | Level_Error
  deriving (Bounded, Enum, Eq, Ord, Show)

-- TODO: Handle this error cleanly when evaluating outside of `withSpinner` (eg: runCLI)
failWith :: MonadIO m => Text -> m a
failWith = liftIO . ioError . userError . T.unpack

putError :: MonadIO m => Text -> m ()
putError = liftIO . putMsg Level_Error

putWarning :: MonadIO m => Text -> m ()
putWarning = liftIO . putMsg Level_Warning

putInfo :: MonadIO m => Text -> m ()
putInfo = liftIO . putMsg Level_Normal

putMsg :: MonadIO m => Level -> Text -> m ()
putMsg level s = liftIO $ do
  setColor level
  T.putStrLn s
  setSGR [Reset]

setColor :: Level -> IO ()
setColor = \case
  Level_Error -> do
    setSGR [SetColor Foreground Vivid Red]
    -- setSGR [SetColor Background Vivid White]
  Level_Warning -> do
    setSGR [SetColor Foreground Vivid Yellow]
    -- setSGR [SetColor Background Vivid Black]
  Level_Normal -> return ()
