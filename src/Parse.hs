module Parse (
  parse', ltlformula, graph, parseFormula, parseGraph, parseDot,
  graphFromFile, dotFromFile, formula
) where

import Types

import Data.Function (on)
import Data.Ratio ((%))
import Data.Maybe (catMaybes, fromJust)
import qualified Data.Set as S
import qualified Data.IntSet as IS
import qualified Data.Vector as V
import Data.List (sort, sortOn, nub, groupBy)
import Text.Parsec hiding (State)
import Text.Parsec.String (Parser)

import qualified Data.Text.Lazy as TL
import Data.GraphViz.Types hiding (parse)
import Data.GraphViz (DotGraph)
import Data.GraphViz.Attributes.Complete
import Data.GraphViz.Exception
import Control.Exception

spc :: Parser ()
spc = many (oneOf " \t") *> pure () -- space but not newline

sym :: String -> Parser ()
sym x = spc *> string x *> spc

parse' :: Parser a -> String -> String -> Maybe a
parse' p f s = either (const Nothing) Just $ parse p f s

parseint::Parser Int
parseint = read <$> many1 digit

ltlformula :: Parser (Formula Char)
ltlformula = skipMany space *> (ptru <|> pfls <|> pprop <|> pnot <|> pnext <|> pfin <|> pglob <|> pbinary) <* skipMany space
  where ptru = sym "1" *> pure Tru
        pfls = sym "0" *> pure Fls
        pprop  = Prop <$> lower
        pnot  = Not  <$> (sym "~" *> ltlformula)
        pnext = Next <$> (sym "X" *> ltlformula)
        -- syntactic sugar
        pfin = Until 1 <$> pure Tru <*> (sym "F" *> ltlformula)
        pglob = Not <$> (Until 1 <$> pure Tru <*> (Not <$> (sym "G" *> ltlformula)))

        parseufrac = do
          (m,n) <- (,) <$> (sym "[" *> parseint <* sym "/") <*> (parseint  <* sym "]")
          if m>n || m<=0 || n<=0
            then error $ "Parse error: Invalid fraction at U[..] in formula: " ++ show m ++ "/" ++ show n
            else return $ m % n

        andop = char '&' *> pure And
        orop  = char '|' *> pure Or
        untilop = Until <$> (sym "U" *> option 1 parseufrac)
        binop = spaces *> andop <|> orop <|> untilop <* spaces
        pbinary = (\f op g -> op f g) <$> (sym "(" *> ltlformula) <*> (spaces *> binop <* spaces) <*> (ltlformula <* sym ")")

-- parser for input in same format as pretty printed formulae
parseFormula :: String -> Maybe (Formula Char)
parseFormula str = parse' (ltlformula <* eof) "<formula>" str

-- parser for graph
graph :: Parser (Graph Char)
graph = do
  nodedefs <- sortOn fst . catMaybes <$> many gline <* eof
  let nodeids = map fst nodedefs
      maxnode = maximum (maximum (-1:nodeids):map (IS.findMax . snd . snd) nodedefs)
  if (length . nub . sort $ nodeids) < length nodeids
  then error $ "Parse error: Multiple definition of a node!"
  else if maxnode == -1
  then error $ "Parse error: Graph looks empty!"
  else return $ (V.replicate (maxnode+1) (S.empty, IS.empty)) V.// nodedefs
  where node = Just <$> ( (,) <$> (parseint <* spc) <*> ( (,) <$> (option S.empty propset) <*> (sym "->" *> succlist) ) )
        propset = S.fromList <$> (sym "{" *> ((lower <* spc) `sepBy` (char ',' *> spc)) <* char '}')
        succlist = IS.fromList <$> ((parseint <* spc) `sepBy1` (char ',' *> spc)) <* endOfLine
        comment = char '#' *> many (noneOf "\r\n") *> endOfLine *> pure Nothing
        gline = spc *> (node <|> comment)

-- parser for labelled adj. graph
parseGraph :: String -> String -> Maybe (Graph Char)
parseGraph filename str = parse' graph filename' str
  where filename' = if null filename then "<stdin>" else filename

-- load a digraph from a dot file
parseDot :: String -> IO (Maybe (Graph Char))
parseDot dgs = catch (Just <$> evaluate g) handle
  where handle :: GraphvizException -> IO (Maybe (Graph Char))
        handle _ = return Nothing
        g = parseDot' dgs

parseDot' :: String -> Graph Char
parseDot' dgs = g''
  where dg = parseDotGraph (TL.pack dgs) :: DotGraph Int
        ns = graphNodes dg
        toEdge (DotEdge f t _) = (f,t)
        nn = 1+maximum ((-1):map nodeID ns)
        g = V.replicate nn (S.empty, IS.empty)
        --throw all symbols in all text labels in one set
        at n = S.unions $ map S.fromList $ catMaybes $ map getStr $ nodeAttributes n
        getStr (Label (StrLabel s)) = Just $ TL.unpack s
        getStr _ = Nothing
        g' = g V.// zip (map nodeID ns) (map (\n -> (at n, IS.empty)) ns)
        es = map (\((f,t):ess) -> (f, (fst $ g' V.! f, IS.fromList $ t:map snd ess)) ) $ groupBy ((==) `on` fst) $ map toEdge $ graphEdges dg
        g'' = g' V.// es

----------------------------

-- helpers for REPL, unsafe!

formula = fromJust . parseFormula

graphFromFile :: String -> IO (Graph Char)
graphFromFile f = readFile f >>= return . fromJust . parseGraph f

dotFromFile :: String -> IO (Graph Char)
dotFromFile f = readFile f >>= return . parseDot'
