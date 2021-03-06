module Executer
  ( runFile
  , runStr
  , runStrArg
  , benchmark
  , makeLog
  ) where

import Types
import Utils
import System.IO (openTempFile, hClose)
import System.Process (readProcessWithExitCode, showCommandForUser)
import System.FilePath (dropExtension)
import Control.Monad.Reader
import Control.Monad.Except (throwError)
import Flow
import CodeGen (completeCodeGen)

makeLog :: CommandOutput -> JSON -> Log
makeLog (_exitcode, _stdout, _stdin) jsobj = Log
  { exitcode = _exitcode
  , stdout   = show _stdout
  , stdin    = show _stdin
  , json     = jsobj
  }

-- |Compile the Futhark source code in env.
compile :: Command Result
compile = do
  Env filepath _dataset backend _runs <- ask
  let futExec = "futhark"
  let futParams = [show backend, filepath]
  p $ "[Futhark] Command going to be run: " ++ showCommandForUser futExec futParams

  output@(_exitcode, _stdout, _stdin) <- liftIO <| readProcessWithExitCode futExec futParams ""
  when (isExitFailure _exitcode)    <| throwError (CommandFailure CompilationError output)

  p   "[Futhark] Compilation results:"
  p $ "[Futhark] ExitCode: " ++ show _exitcode
  p $ "[Futhark] stdout:   " ++ show _stdout
  p $ "[Futhark] stdin :   " ++ show _stdin
  p   "[Futhark] Compilation COMPLETED"
  let compileLog = makeLog output ""
  return (Result compileLog)

-- |Execute the compiled Futhark executable 'futExec' containing the compiled linear program.
makeTemp :: Command FutPgmFile
makeTemp = do
  let path   = "build/"
  let prefix = "autogenerated_.fut"
  (filepath, handle) <- liftIO $ openTempFile path prefix
  liftIO $ hClose handle
  -- p filepath
  return filepath

writeToFile :: FutPgmStr -> Command ()
writeToFile futStr = do
  filepath <- asks fp
  liftIO   <| writeFile filepath futStr

store :: FutPgmStr -> Command FutPgmFile
store futPgmStr = do
  filepath <- makeTemp
  backend  <- asks be
  let envNew = Env { fp = filepath, ds = "", be = backend, runs = 0 }
  local (const envNew) (writeToFile futPgmStr)
  return filepath

runStr :: FutPgmStr -> Backend -> IO (CommandExecution Result)
runStr futPgmStr backend = runStrArg futPgmStr backend "\n"

runFile :: FutPgmFile -> Backend -> IO (CommandExecution Result)
runFile futPgmFile backend =
  let envInit = Env { fp = futPgmFile, ds = "", be = backend, runs = 0 }
  in execCmd (runFileArgM "\n") envInit

--- but with std'ins
executeArg :: StdInArg -> Command Result
executeArg val = do
  filepath <- asks fp
  let executable = dropExtension filepath
  let params = []
  p $ "[LinPgm] Command going to be run: " ++ showCommandForUser executable params ++ " " ++ val

  output@(_exitcode, _stdout, _stdin) <- liftIO $ readProcessWithExitCode executable params val
  when (isExitFailure _exitcode)    <| throwError (CommandFailure ExecutionError output)

  p   "[LinPgm] Execution results:"
  p $ "[LinPgm] ExitCode: " ++ show _exitcode
  p $ "[LinPgm] stdout:   " ++ show _stdout
  p $ "[LinPgm] stdin :   " ++ show _stdin
  p   "[LinPgm] Execution ENDED"
  let executeLog = makeLog output ""
  return (Result executeLog)

runFileArgM :: StdInArg -> Command Result
runFileArgM val = compile >> executeArg val

runStrArgM :: FutPgmStr -> StdInArg -> Command Result
runStrArgM futPgmStr val = do
  filepath <- store futPgmStr
  backend  <- asks be
  let envNew = Env { fp = filepath, ds = "", be = backend, runs = 0 }
  local (const envNew) (runFileArgM val)

runStrArg :: FutPgmStr -> Backend -> StdInArg -> IO (CommandExecution Result)
runStrArg futPgmStr backend val =
  let envInit = Env { fp = "", ds = "", be = backend, runs = 0 }
  in execCmd (runStrArgM futPgmStr val) envInit

makeHeader :: FilePath -> FutPgmStr
makeHeader dsn = concat
  [ "-- Autogenerated benchmark v2.  Edits will be overwritten.\n"
  , "--\n"
  , "-- ==\n"
  , "-- input @ " ++ dsn ++ "\n\n"
  ]

benchmark :: FilePath -> Dataset -> Backend -> Runs -> LFun -> Val -> IO (CommandExecution Result)
benchmark filename dataset backend noRuns futPgmStr val =
  let path = "build/"
      fullname = path ++ filename
      futPgmCompiled = completeCodeGen futPgmStr val
   in execCmd (benchmarkM futPgmCompiled dataset)
      <| Env { fp=fullname, ds=dataset, be=backend, runs=noRuns }

benchmarkM :: FutPgmStr -> Dataset -> Command Result
benchmarkM futPgmStr dsn = do
  writeToFile <| makeHeader dsn ++ futPgmStr
  runBenchmark

runBenchmark :: Command Result
runBenchmark = do
  Env filepath dataset backend noRuns <- ask
  let executable = "futhark"
  let jsonfile = dropExtension filepath ++ ".json"
  -- Documentation: https://futhark.readthedocs.io/en/stable/man/futhark-bench.html#futhark-bench-1
  let { params =
        [ "bench"
        --, "--backend=" ++ backend
        , "--json=" ++ jsonfile
        , "--runs=" ++ show noRuns
        , filepath
        ]
      }
  --p $ "[Benchmark] Command to be run: " ++ showCommandForUser executable params

  output@(_exitcode, _stdout, _stdin) <- liftIO <| readProcessWithExitCode executable params ""
  when (isExitFailure _exitcode)                <| throwError (CommandFailure BenchmarkError output)

  jsobj <- liftIO <| readFile jsonfile

  p   "[Benchmark] Execution results:"
  p $ "[Benchmark] ExitCode: " ++ show _exitcode
  p $ "[Benchmark] stdout:   " ++ _stdout
  p $ "[Benchmark] stdin :   " ++ _stdin
  p   "[Benchmark] Execution ENDED"
  p $ "[Benchmark] Inspect results with: 'jq . " ++ jsonfile ++ "'"
  p $ "[Benchmark] Inspect program with: 'vim " ++ filepath ++ "'"
  p $ "[Benchmark] Inspect dataset with: 'vim build/" ++ dataset ++ "'"
  let benchmarkLog = makeLog output jsobj
  return (Result benchmarkLog)
