-- //./Type.hs//

module Kind.Parse where

import Debug.Trace
import Prelude hiding (EQ, LT, GT)
import Kind.Type
import Kind.Reduce
import Highlight (highlightError, highlight)
import Data.Char (ord)
import qualified Data.Map.Strict as M
import Data.Functor.Identity (Identity)
import System.Exit (die)
import Text.Parsec ((<?>), (<|>), getPosition, sourceLine, sourceColumn, getState, setState)
import Text.Parsec.Error (errorPos, errorMessages, showErrorMessages, ParseError, errorMessages, Message(..))
import qualified Text.Parsec as P
import Data.List (intercalate, isPrefixOf)
import System.Console.ANSI

type Uses     = [(String, String)]
type PState   = (String, Uses)
type Parser a = P.ParsecT String PState Identity a

-- Helper functions that consume trailing whitespace
parseTrivia :: Parser ()
parseTrivia = P.skipMany (parseSpace <|> parseComment)
  where
    parseSpace = (P.try $ do
      P.space
      return ()) <?> "Space"
    parseComment = (P.try $ do
      P.string "//"
      P.skipMany (P.noneOf "\n")
      P.char '\n'
      return ()) <?> "Comment"

char :: Char -> Parser Char
char c = P.char c <* parseTrivia

string :: String -> Parser String
string s = P.string s <* parseTrivia

letter :: Parser Char
letter = P.letter

alphaNum :: Parser Char
alphaNum = P.alphaNum

digit :: Parser Char
digit = P.digit

oneOf :: String -> Parser Char
oneOf s = P.oneOf s

noneOf :: String -> Parser Char
noneOf s = P.noneOf s

-- Main parsing functions
doParseTerm :: String -> String -> IO Term
doParseTerm filename input =
  case P.runParser (parseTerm <* P.eof) (filename, []) filename input of
    Left err -> do
      showParseError filename input err
      die ""
    Right term -> return $ bind (genMetas term) []

doParseUses :: String -> String -> IO Uses
doParseUses filename input =
  case P.runParser (parseUses <* P.eof) (filename, []) filename input of
    Left err -> do
      showParseError filename input err
      die ""
    Right uses -> return uses

doParseBook :: String -> String -> IO Book
doParseBook filename input = do
  let parser = do
        uses <- parseUses
        setState (filename, uses)
        parseBook <* P.eof
  case P.runParser parser (filename, []) filename input of
    Left err -> do
      showParseError filename input err
      die ""
    Right book -> return book

-- Error handling
extractExpectedTokens :: ParseError -> String
extractExpectedTokens err =
    let expectedMsgs = [msg | Expect msg <- errorMessages err, msg /= "Space", msg /= "Comment"]
    in intercalate " | " expectedMsgs

showParseError :: String -> String -> P.ParseError -> IO ()
showParseError filename input err = do
  let pos = errorPos err
  let line = sourceLine pos
  let col = sourceColumn pos
  let errorMsg = extractExpectedTokens err
  putStrLn $ setSGRCode [SetConsoleIntensity BoldIntensity] ++ "\nPARSE_ERROR" ++ setSGRCode [Reset]
  putStrLn $ "- expected: " ++ errorMsg
  putStrLn $ "- detected:"
  putStrLn $ highlightError (line, col) (line, col + 1) input
  putStrLn $ setSGRCode [SetUnderlining SingleUnderline] ++ filename ++
             setSGRCode [Reset] ++ " " ++ show line ++ ":" ++ show col

-- Parsing helpers
withSrc :: Parser Term -> Parser Term
withSrc parser = do
  ini <- getPosition
  val <- parser
  end <- getPosition
  (nam, _) <- P.getState
  let iniLoc = Loc nam (sourceLine ini) (sourceColumn ini)
  let endLoc = Loc nam (sourceLine end) (sourceColumn end)
  return $ Src (Cod iniLoc endLoc) val

-- Term Parser
-- -----------

-- Main term parser
parseTerm :: Parser Term
parseTerm = (do
  parseTrivia
  P.choice
    [ parseAll
    , parseSwi
    , parseMat
    , parseLam
    , parseEra
    , parseOp2
    , parseApp
    , parseAnn
    , parseSlf
    , parseIns
    , parseDat
    , parseNat -- sugar
    , parseCon
    , parseUse
    , parseLet
    , parseDo -- sugar
    , parseMatch -- sugar
    , parseSet
    , parseNum
    , parseTxt -- sugar
    , parseLst -- sugar
    , parseChr -- sugar
    , parseHol
    , parseMet
    , parseRef
    ] <* parseTrivia) <?> "Term"

-- Individual term parsers
parseAll = withSrc $ do
  string "∀"
  era <- P.optionMaybe (char '-')
  char '('
  nam <- parseName
  char ':'
  inp <- parseTerm
  char ')'
  bod <- parseTerm
  return $ All nam inp (\x -> bod)

parseLam = withSrc $ do
  string "λ"
  era <- P.optionMaybe (char '-')
  nam <- parseName
  bod <- parseTerm
  return $ Lam nam (\x -> bod)

parseEra = withSrc $ do
  string "λ"
  era <- P.optionMaybe (char '-')
  nam <- char '_'
  bod <- parseTerm
  return $ Lam "_" (\x -> bod)

parseApp = withSrc $ do
  char '('
  fun <- parseTerm
  args <- P.many $ do
    P.notFollowedBy (char ')')
    era <- P.optionMaybe (char '-')
    arg <- parseTerm
    return (era, arg)
  char ')'
  return $ foldl (\f (era, a) -> App f a) fun args

parseAnn = withSrc $ do
  char '{'
  val <- parseTerm
  char ':'
  chk <- P.option False (char ':' >> return True)
  typ <- parseTerm
  char '}'
  return $ Ann chk val typ

parseSlf = withSrc $ do
  string "$("
  nam <- parseName
  char ':'
  typ <- parseTerm
  char ')'
  bod <- parseTerm
  return $ Slf nam typ (\x -> bod)

parseIns = withSrc $ do
  char '~'
  val <- parseTerm
  return $ Ins val

parseDat = withSrc $ do
  P.try $ string "#["
  scp <- P.many parseTerm
  char ']'
  char '{'
  cts <- P.many $ P.try $ do
    char '#'
    nm <- parseName
    tele <- parseTele
    return $ Ctr nm tele
  char '}'
  return $ Dat scp cts

parseTele :: Parser Tele
parseTele = do
  char '{'
  fields <- P.many $ P.try $ do
    nam <- parseName
    char ':'
    typ <- parseTerm
    return (nam, typ)
  char '}'
  char ':'
  ret <- parseTerm
  return $ foldr (\(nam, typ) acc -> TExt nam typ (\x -> acc)) (TRet ret) fields

parseCon = withSrc $ do
  char '#'
  nam <- parseName
  char '{'
  args <- P.many $ do
    P.notFollowedBy (char '}')
    name <- P.optionMaybe $ P.try $ do
      name <- parseName
      char ':'
      return name
    term <- parseTerm
    return (name, term)
  char '}'
  return $ Con nam args

parseSwi = withSrc $ do
  P.try $ string "λ{0:"
  zero <- parseTerm
  string "_:"
  succ <- parseTerm
  char '}'
  return $ Swi zero succ

parseMat = withSrc $ do
  P.try $ string "λ{"
  cse <- P.many $ do
    char '#'
    cnam <- parseName
    char ':'
    cbod <- parseTerm
    return (cnam, cbod)
  char '}'
  return $ Mat cse

parseRef = withSrc $ do
  name <- parseName
  (_, uses) <- P.getState
  let name' = expandUses uses name
  return $ case name' of
    "U32" -> U32
    _     -> Ref name'

parseUse = withSrc $ do
  P.try (string "use ")
  nam <- parseName
  char '='
  val <- parseTerm
  bod <- parseTerm
  return $ Use nam val (\x -> bod)

parseLet = withSrc $ do
  P.try (string "let ")
  nam <- parseName
  char '='
  val <- parseTerm
  bod <- parseTerm
  return $ Let nam val (\x -> bod)

parseSet = withSrc $ char '*' >> return Set

parseNum = withSrc $ Num . read <$> P.many1 digit

parseOp2 = withSrc $ do
  opr <- P.try $ do
    char '('
    parseOper
  fst <- parseTerm
  snd <- parseTerm
  char ')'
  return $ Op2 opr fst snd

parseTxt = withSrc $ do
  char '"'
  txt <- P.many (noneOf "\"")
  char '"'
  return $ Txt txt

parseLst = withSrc $ do
  char '['
  elems <- P.many parseTerm
  char ']'
  return $ Lst elems

parseChr = withSrc $ do
  char '\''  
  chr <- parseEscaped <|> noneOf "'\\"
  char '\''
  return $ Num (fromIntegral $ ord chr)
  where
    parseEscaped :: Parser Char
    parseEscaped = do
      char '\\'
      c <- oneOf "\\\'nrt"
      return $ case c of
        '\\' -> '\\'
        '\'' -> '\''
        'n'  -> '\n'
        'r'  -> '\r'
        't'  -> '\t'

parseHol = withSrc $ do
  char '?'
  nam <- parseName
  ctx <- P.option [] $ do
    char '['
    terms <- P.sepBy parseTerm (char ',')
    char ']'
    return terms
  return $ Hol nam ctx

parseMet = withSrc $ do
  char '_'
  return $ Met 0 []

parseName :: Parser String
parseName = do
  head <- letter
  tail <- P.many (alphaNum <|> oneOf "/_.-")
  parseTrivia
  return (head : tail)

parseOper = P.choice
  [ P.try (string "+") >> return ADD
  , P.try (string "-") >> return SUB
  , P.try (string "*") >> return MUL
  , P.try (string "/") >> return DIV
  , P.try (string "%") >> return MOD
  , P.try (string "<<") >> return LSH
  , P.try (string ">>") >> return RSH
  , P.try (string "<=") >> return LTE
  , P.try (string ">=") >> return GTE
  , P.try (string "<") >> return LT
  , P.try (string ">") >> return GT
  , P.try (string "==") >> return EQ
  , P.try (string "!=") >> return NE
  , P.try (string "&") >> return AND
  , P.try (string "|") >> return OR
  , P.try (string "^") >> return XOR
  ]

-- Book Parser
-- -----------

parseBook :: Parser Book
parseBook = M.fromList <$> P.many parseDef

parseDef :: Parser (String, Term)
parseDef = do
  name <- parseName
  typ <- P.optionMaybe $ do
    char ':'
    t <- parseTerm
    return t
  char '='
  val <- parseTerm
  (_, uses) <- P.getState
  let name' = expandUses uses name
  case typ of
    Nothing -> return (name', val)
    Just t  -> return (name', bind (genMetas (Ann False val t)) [])

parseUses :: Parser Uses
parseUses = P.many $ P.try $ do
  string "use "
  long <- parseName
  string "as "
  short <- parseName
  return (short, long)

expandUses :: Uses -> String -> String
expandUses uses name =
  case filter (\(short, _) -> short `isPrefixOf` name) uses of
    (short, long):_ -> long ++ drop (length short) name
    []              -> name

-- Syntax Sugars
-- -------------

-- TODO: implement a parser for Kind's do-notation:
-- do Name { // this starts a do-block
--   ask x = exp0 // this is parsed as a monadic binder
--   ask exp1     // this is parsed as a monadic sequencer
--   ret-val      // this is the monadic return
-- } // this ends a do block

-- The do-notation above is desugared to:
-- (Name/Monad/bind _ _ exp0 λx
-- (Name/Monad/bind _ _ exp1 λ_
-- ret-val))
-- Note this is just a series of applications:
-- (App (App (App (App (Ref "Name/Monad/bind") (Met 0 [])) (Met 0 [])) exp0) (Lam "x" λx ...

-- To make the code cleaner, create a DoBlock type.
-- Then, create a 'parseDoSugar' parser, that returns a DoBlock.
-- Then, create a 'desugarDo' function, that converts a DoBlock into a Term.
-- Finally, create a 'parseDo' parser, that parses a do-block as a Term.

-- actually, let's add another option:
-- - optionally, the user can end the block in 'wrap value'
-- - if they do, the end value will be `((Name/Monad/bind _) value)` instead of just `value`
-- rewrite the commented out code above to add this feature. keep all else the same. do it now:

-- this 'isDoWrap' logic is ugly. clean up the code above to avoid pattern-matching on (App (App ...)) like that. implement the wrap functionality in a more elegant fashion. rewrite the code now.

-- TODO: rewrite the code above to apply the expand-uses functionality to the generated refs. also, append just "bind" and "pure" (instad of "/Monad/bind" etc.)

-- Do-Notation:
-- ------------

data DoBlck = DoBlck String [DoStmt] Bool Term -- bool used for wrap
data DoStmt = DoBind String Term | DoSeq Term

parseDoSugar :: Parser DoBlck
parseDoSugar = do
  string "do "
  name <- parseName
  char '{'
  parseTrivia
  stmts <- P.many (P.try parseDoStmt)
  (wrap, ret) <- parseDoReturn
  char '}'
  return $ DoBlck name stmts wrap ret

parseDoStmt :: Parser DoStmt
parseDoStmt = P.try parseDoBind <|> parseDoSeq

parseDoBind :: Parser DoStmt
parseDoBind = do
  string "ask "
  name <- parseName
  char '='
  exp <- parseTerm
  return $ DoBind name exp

parseDoSeq :: Parser DoStmt
parseDoSeq = do
  string "ask "
  exp <- parseTerm
  return $ DoSeq exp

parseDoReturn :: Parser (Bool, Term)
parseDoReturn = do
  wrap <- P.optionMaybe (P.try (string "ret "))
  term <- parseTerm
  return (maybe False (const True) wrap, term)

desugarDo :: DoBlck -> Parser Term
desugarDo (DoBlck name stmts wrap ret) = do
  (_, uses) <- P.getState
  let exName = expandUses uses name
  let mkBind = \ x exp acc -> App (App (App (App (Ref (exName ++ "bind")) (Met 0 [])) (Met 0 [])) exp) (Lam x (\_ -> acc))
  let mkWrap = \ ret -> App (App (Ref (exName ++ "pure")) (Met 0 [])) ret
  return $ foldr (\stmt acc ->
    case stmt of
      DoBind x exp -> mkBind x exp acc
      DoSeq exp -> mkBind "_" exp acc
    ) (if wrap then mkWrap ret else ret) stmts

parseDo :: Parser Term
parseDo = parseDoSugar >>= desugarDo

-- Match
-- -----

-- Let's now implement the 'parseMatch' sugar. The following syntax:
-- 'match x { #Foo: foo #Bar: bar ... }'
-- desugars to:
-- '(λ{ #Foo: foo #Bar: bar ... } x)
-- it parses the cases identically to parseMat.
parseMatch :: Parser Term
parseMatch = withSrc $ do
  P.try $ string "match "
  x <- parseTerm
  char '{'
  parseTrivia
  cse <- P.many $ do
    char '#'
    cnam <- parseName
    char ':'
    cbod <- parseTerm
    return (cnam, cbod)
  char '}'
  return $ App (Mat cse) x

-- Match
-- -----

-- Nat: the '#123' expression is parsed into (Nat 123)

parseNat :: Parser Term
parseNat = withSrc $ P.try $ do
  char '#'
  num <- P.many1 digit
  return $ Nat (read num)
