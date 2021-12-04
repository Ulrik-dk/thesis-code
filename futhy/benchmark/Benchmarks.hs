module Benchmarks (main) where

{-
1. Measure time for interpreter on random value.
2. Make benchmarks for wipFeatures to run on the interpreter benchmarks.
3. Generate random values on command.
4. Expand to compiler.
-}

import Interpreter (interpret)
import Data.Either
--import Test.Tasty.Bench
import Tests hiding (main)
import Random
import Types hiding (runs)
import Utils
import Flow
import Executer
import Plot (savePlot)
import Json (json2series)
import Dataset
import Matrix
import Control.Monad

{- 
benchInterpretor :: String -> LFun -> Val -> Benchmark
benchInterpretor name lf1 vin1 =
  let (lf, vin, _vout) = caramelizeTestParams (lf1, vin1, Zero)
   in bench name <| nf (interpret lf) vin

mainOld :: IO ()
mainOld = defaultMain
  [ genBs "Reduce" genReduceBenchmark 4
  , genBs "Scale" genScaleBenchmark 5
  , genBs "LMap" genLmapBenchmark 5
  , genBs "Zip" genZipBenchmark 5
  --, reduce
  ]

genBs :: String -> (Int -> Benchmark) -> Int ->  Benchmark
genBs n f i = bgroup n $ map f $ powersof10 i

genScaleBenchmark :: Int -> Benchmark
genScaleBenchmark i = benchInterpretor (show i) (Scale 2.0) (rndVecVals i)

genLmapBenchmark :: Int -> Benchmark
genLmapBenchmark i = benchInterpretor (show i) (LMap (Scale 2.0)) (rndVecVals i)

genZipBenchmark :: Int -> Benchmark
genZipBenchmark i = benchInterpretor (show i) (Zip [Scale 2.0]) (Tensor [rndVecVals i])

genReduceBenchmark :: Int -> Benchmark
genReduceBenchmark i = benchInterpretor (show i) (Red <| rndRelCap i i (i `div` 4)) (rndVecVals i)

{- Old-flavour benchmarks for testing GPU -}

benchCompiler :: String -> LFun -> Val -> Benchmark
benchCompiler name lf1 vin1 =
  let (lf, vin, _vout) = caramelizeTestParams (lf1, vin1, Zero)
   in bench name
      <| nfIO
      <| runStrArg (show lf) OPENCL (show vin)


-}



{- New-flavour benchmarks for testing GPU -}
scaleSym :: Bench
scaleSym name dataset backend vecLen runs = benchmark name dataset backend runs (Scale 7.0) (rndVecVals vecLen)

scaleMtx :: Bench
scaleMtx name dataset backend vecLen runs =
  let mtx = getMatrixRep (Scale 59.0) [vecLen]
      lfn = LSec mtx MatrixMult
   in benchmark name dataset backend runs lfn (rndVecVals vecLen)

lmapB :: Bench
lmapB name dataset backend vecLen runs  = benchmark name dataset backend runs (LMap (Scale 11.0)) (rndVecVals vecLen)

zipB :: Bench
zipB name dataset backend vecLen runs   = benchmark name dataset backend runs (Zip [Scale 17.0]) (Tensor [rndVecVals vecLen])

reduceB :: Bench
reduceB name dataset backend vecLen runs =
  let relLen = 100 -- (20 *) . floor . log <| (fromIntegral vecLen :: Double)
      maxIdx = vecLen
      maxVal = 100
   in benchmark name dataset backend runs (Red <| rndRelCap relLen maxIdx maxVal) (rndVecVals vecLen)

genBenchmarks :: String -> Bench -> Backend -> Int -> Runs -> IO PlotData
genBenchmarks name bench backend oom runs = do
  let vecLens = powersof2 oom
  cexs <- mapM (\i -> bench name i backend i runs) vecLens
  print $ "LENGHT: " ++ (show $ length cexs)
  print cexs
  --guard (length (rights cexs) == length vecLens)
  let jsons = map (json . getLog) (rights cexs)
  seriess <- mapM json2series jsons
  return (name, vecLens, seriess)




{- Compound benchmarks
 - [POPL, p. 8]
 - CNNs RNNs
 - Run on GPU
 -
 - genNN layers  inputsize
 -}

main :: IO ()
main = do

  let oom = 11 -- ordersOfMagnitude of 2 of the datasets.  Should be more than 10
  let noRuns = 1

  initDatasets oom
  genBenchmarks "ScaleMtx" scaleMtx C oom noRuns >>= savePlot
  {-
  genBenchmarks "ScaleSym" scaleSym C oom noRuns >>= savePlot
  genBenchmarks "LMap"  lmapB  C oom noRuns >>= savePlot
  genBenchmarks "Zip"   zipB   C oom noRuns >>= savePlot
  genBenchmarks "Reduce" reduceB C oom noRuns >>= savePlot
  -}
  return ()

