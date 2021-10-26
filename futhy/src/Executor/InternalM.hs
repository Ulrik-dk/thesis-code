module Executor.InternalM where

import Types
import System.IO (openTempFile, hClose, stderr, hPrint)
import System.Process (readProcessWithExitCode, showCommandForUser)
import System.FilePath (dropExtension)
import Control.Monad.Reader
import Control.Monad.Except (throwError)
import GHC.IO.Exception (ExitCode(..))
import Flow

p :: String -> Command ()
p s =
  let debug = False
  in when debug (liftIO <| hPrint stderr s)

-- |Compile the Futhark source code in env.
compile :: Command Result
compile = do
  Env filepath backend <- ask
  let futExec = "futhark"
  let futParams = [show backend, filepath]
  p $ "[Futhark] Command going to be run: " ++ showCommandForUser futExec futParams

  output@(exitcode, stdout, stdin) <- liftIO $ readProcessWithExitCode futExec futParams ""
  when (isExitFailure exitcode)    <| throwError (CommandFailure CompilationError output)

  p   "[Futhark] Compilation results:"
  p $ "[Futhark] ExitCode: " ++ show exitcode
  p $ "[Futhark] stdout:   " ++ show stdout
  p $ "[Futhark] stdin :   " ++ show stdin
  p   "[Futhark] Compilation COMPLETED"
  return (CommandResult output)

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

runStr :: FutPgmStr -> Backend -> IO (CommandExecution Result)
runStr futPgmStr backend = runStrArg futPgmStr backend "\n"

runFile :: FutPgmFile -> Backend -> IO (CommandExecution Result)
runFile futPgmFile backend =
  let envInit = Env { fp = futPgmFile, be = backend }
  in execCmd (runFileArgM "\n") envInit

--- but with std'ins
executeArg :: StdInArg -> Command Result
executeArg arg = do
  filepath <- asks fp
  let executable = dropExtension filepath
  let params = []
  p $ "[LinPgm] Command going to be run: " ++ showCommandForUser executable params <> " " <> arg

  output@(exitcode, stdout, stdin) <- liftIO $ readProcessWithExitCode executable params arg
  when (isExitFailure exitcode)    <| throwError (CommandFailure ExecutionError output)

  p   "[LinPgm] Execution results:"
  p $ "[LinPgm] ExitCode: " ++ show exitcode
  p $ "[LinPgm] stdout:   " ++ show stdout
  p $ "[LinPgm] stdin :   " ++ show stdin
  p   "[LinPgm] Execution ENDED"
  return (CommandResult output)


runStrArg :: FutPgmStr -> Backend -> StdInArg -> IO (CommandExecution Result)
runStrArg futPgmStr backend arg =
  let envInit = Env { fp = "", be = backend }
  in execCmd (runStrArgM futPgmStr arg) envInit

runStrArgM :: FutPgmStr -> StdInArg -> Command Result
runStrArgM futPgmStr arg = do
  filepath <- store futPgmStr
  backend <- asks be
  let envNew = Env { fp = filepath, be = backend }
  local (const envNew) (runFileArgM arg)

runFileArgM :: StdInArg -> Command Result
runFileArgM arg = compile >> executeArg arg
