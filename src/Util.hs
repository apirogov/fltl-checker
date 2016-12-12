module Util where
import Data.Maybe (fromJust)
import Control.Monad.IO.Class (liftIO, MonadIO)

import Data.Graph.Inductive (Gr, mkGraph)

import qualified Data.Vector as V

import System.Clock

import Parse

eitherToMaybe = either (const Nothing) Just

-- | access 2-indexed variable
at var i j = (var V.! i) V.! j

-- | fully connected graph of size n (e.g. to benchmark cycle search)
full :: Int -> Gr () ()
full n = mkGraph (zip [0..n-1] $ repeat ()) [(a,b,()) | a<-[0..n-1], b<-[0..n-1], a/=b]

-- | get current system time for measurments
currTime :: MonadIO m => m TimeSpec
currTime = liftIO $ getTime Monotonic

-- | get time diff. of two time measurements in milliseconds
msTimeDiff :: TimeSpec -> TimeSpec -> Double
msTimeDiff a b = (/1000000) . fromIntegral . abs . toNanoSecs $ b-a

-- | get time diff. of two time measurements in milliseconds as string
showTime :: TimeSpec -> TimeSpec -> String
showTime a b = show (msTimeDiff a b) ++ " ms"

bench f = do
  s <- getTime Monotonic
  putStrLn $ show f
  e <- getTime Monotonic
  return $ diffTimeSpec e s

-- unsafe REPL helpers

-- | parse formula. exception on failure, use with care
formula = fromJust . eitherToMaybe . parseFormula

-- | parse graph in dot format. exception on failure.
dotFromFile f = readFile f >>= return . parseDot'

