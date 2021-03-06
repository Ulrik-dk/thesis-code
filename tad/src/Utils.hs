module Utils where
import Types
import Control.Monad
import Control.Monad.IO.Class
import System.IO (stderr, hPutStrLn)
import Flow

import Data.List (isPrefixOf)

mkT1 :: [RealNumber] -> Val
mkT1 x = Vector $ map Scalar x

mkT2 :: [[RealNumber]] -> Val
mkT2 x = Vector $ map mkT1 x

mkR0 :: Val -> RealNumber
mkR0 (Scalar x) = x
mkR0 _ = undefined

mkR1 :: Val -> [RealNumber]
mkR1 (Vector x@(Scalar _: _)) = map mkR0 x
mkR1 _ = undefined

mkR2 :: Val -> [[RealNumber]]
mkR2 (Vector x@(Vector (Scalar _: _) : _)) = map mkR1 x
mkR2 _ = undefined

--- from https://hackage.haskell.org/package/base-4.15.0.0/docs/src/Data-OldList.html#transpose
transpose               :: [[a]] -> [[a]]
transpose []             = []
transpose ([]   : xss)   = transpose xss
transpose ((x:xs) : xss) = (x : [h | (h:_) <- xss]) : transpose (xs : [ t | (_:t) <- xss])

transposeVal :: Val -> Val
transposeVal x@(Vector (Scalar _: _))          = x
transposeVal x@(Vector (Vector (Scalar _: _) : _)) = mkT2 $ transpose $ mkR2 x
transposeVal _ = error "undefined transposeVal case"

-- Source https://hackage.haskell.org/package/tidal-1.7.8/docs/src/Sound.Tidal.Utils.html#nth
{- | Safer version of !! --}
nth :: Int -> [a] -> Maybe a
nth _ []       = Nothing
nth 0 (x : _)  = Just x
nth n (_ : xs) = nth (n - 1) xs

---- from https://programming-idioms.org/idiom/116/remove-occurrences-of-word-from-string/1380/haskell
remove :: String -> String -> String
remove _ "" = ""
remove w s@(c:cs)
  | w `isPrefixOf` s = remove w (drop (length w) s)
  | otherwise = c : remove w cs

powersof2 :: OOMs -> [Int]
powersof2 (lo, hi) = do j <- [lo..hi]
                        return (2^j)

powersof10 :: (Num a, Integral b) => b -> [a]
powersof10 i = [10 ^ ii | ii <- [1..i]]

p :: String -> Command ()
p s =
  let debug = False
  in when debug (liftIO <| hPutStrLn stderr s)
