module Executor.InternalM where

import Types
import System.IO (stderr, hPrint, openTempFile, hClose)
import System.Process (readProcessWithExitCode, showCommandForUser)
import System.FilePath (dropExtension)
import Control.Monad.Reader
import Control.Monad.Except (throwError)
import GHC.IO.Exception (ExitCode(..))

p :: String -> Command ()
p = liftIO . hPrint stderr

-- |Compile the Futhark source code in env.
compile :: Command CommandResult
compile = do
  Env filepath backend <- ask
  let futExec = "futhark"
  let futParams = [show backend, filepath]
  p $ "[Futhark] Command going to be run: " ++ showCommandForUser futExec futParams

  output <- liftIO $ readProcessWithExitCode futExec futParams ""
  let (exitcode, stdout, stdin) = output
  case exitcode of
         ExitFailure _ -> throwError (CompilationError output)
         ExitSuccess   -> return ()

  p   "[Futhark] Compilation results:"
  p $ "[Futhark] ExitCode: " ++ show exitcode
  p $ "[Futhark] stdout:   " ++ show stdout
  p $ "[Futhark] stdin :   " ++ show stdin
  p   "[Futhark] Compilation COMPLETED"
  return $ Output output

-- |Execute the compiled Futhark executable 'futExec' containing the compiled linear program.
makeTemp :: Command FutPgmFile
makeTemp = do
  let path   = "build/"
  let prefix = "autogenerated_.fut"
  (filepath, handle) <- liftIO $ openTempFile path prefix
  liftIO $ hClose handle
  p filepath
  return filepath

writeTemp :: FutPgmStr -> Command ()
writeTemp futStr = do
  filepath <- asks fp
  liftIO $ writeFile filepath futStr

store :: FutPgmStr -> Command FutPgmFile
store futPgmStr = do
  filepath <- makeTemp
  backend <- asks be
  let envNew = Env { fp = filepath, be = backend }
  local (const envNew) (writeTemp futPgmStr)
  return filepath

runStr :: FutPgmStr -> Backend -> IO (Either CommandError CommandResult)
runStr futPgmStr backend = runStrArg futPgmStr backend "\n"

runFile :: FutPgmFile -> Backend -> IO (Either CommandError CommandResult)
runFile futPgmFile backend =
  let envInit = Env { fp = futPgmFile, be = backend }
  in execCmd (runFileArgM "\n") envInit

--- but with std'ins
executeArg :: StdInArg -> Command CommandResult
executeArg arg = do
  filepath <- asks fp
  let executable = dropExtension filepath
  let params = []
  p $ "[LinPgm] Command going to be run: " ++ showCommandForUser executable params

  output <- liftIO $ readProcessWithExitCode executable params arg
  let (exitcode, stdout, stdin) = output
  case exitcode of
         ExitFailure _ -> throwError (ExecutionError (exitcode, stdout, stdin))
         ExitSuccess   -> return ()

  p   "[LinPgm] Execution results:"
  p $ "[LinPgm] ExitCode: " ++ show exitcode
  p $ "[LinPgm] stdout:   " ++ show stdout
  p $ "[LinPgm] stdin :   " ++ show stdin
  p   "[LinPgm] Execution ENDED"
  return $ Output output


runStrArg :: FutPgmStr -> Backend -> StdInArg -> IO (DerivativeComputation CommandResult)
runStrArg futPgmStr backend arg =
  let envInit = Env { fp = "", be = backend }
  in execCmd (runStrArgM futPgmStr arg) envInit

runStrArgM :: FutPgmStr -> StdInArg -> Command CommandResult
runStrArgM futPgmStr arg = do
  filepath <- store futPgmStr
  backend <- asks be
  let envNew = Env { fp = filepath, be = backend }
  local (const envNew) (runFileArgM arg)

runFileArgM :: StdInArg -> Command CommandResult
runFileArgM arg = compile >> executeArg arg
