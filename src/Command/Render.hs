{-# LANGUAGE RankNTypes #-}
module Command.Render
  ( CmdArgs
  , shortFlag
  , shortArg
  , longFlag
  , longArg
  , arg
  , QuoteChar(..)
  , getRawArgs
  , renderShell
  , renderShellDefault
  , cmdFromList
  ) where

import Data.Semigroup
import Data.String

newtype CmdArg =
  CmdArg String
  deriving (Eq)

instance IsString CmdArg where
  fromString = CmdArg

newtype CmdArgs = CmdArgs
  { unCmdArgs :: forall m. Monoid m => (CmdArg -> m) -> m
  }

instance Eq CmdArgs where
  a == b = getRawArgs a == getRawArgs b

instance Ord CmdArgs where
  a <= b = getRawArgs a <= getRawArgs b

instance Show CmdArgs where
  showsPrec p args =
    showParen (p > 10) (showString "cmdFromList " . shows (getRawArgs args))

instance Read CmdArgs where
  readsPrec p =
    readParen (p > 10) $ \r -> do
      ("cmdFromList", s) <- lex r
      (xs, t) <- reads s
      return (cmdFromList xs, t)

instance Semigroup CmdArgs where
  (CmdArgs f) <> (CmdArgs g) = CmdArgs (\h -> f h `mappend` g h)

instance Monoid CmdArgs where
  mempty = CmdArgs (\_ -> mempty)
  mappend = (<>)

instance IsString CmdArgs where
  fromString = singleton . fromString

singleton :: CmdArg -> CmdArgs
singleton x = CmdArgs (\h -> h x)

getRawArgs :: CmdArgs -> [String]
getRawArgs args = appEndo (unCmdArgs args renderArg) []
  where
    renderArg (CmdArg str) = Endo (str :)

renderEscaped :: (Char -> Maybe String) -> String -> Endo String
renderEscaped escape = foldMap esc
  where
    esc c =
      case escape c of
        Nothing -> Endo (c :)
        Just replacement -> Endo (replacement ++)

data QuoteChar = QuoteSingle | QuoteDouble

renderEscapedQuotes :: QuoteChar -> String -> Endo String
renderEscapedQuotes QuoteSingle = renderEscaped esc
  where
    esc '\'' = Just ['\'', '"', '\'', '"', '\'']
    esc _ = Nothing
renderEscapedQuotes QuoteDouble = renderEscaped esc
  where
    esc '"' = Just ['\\', '"']
    esc '$' = Just ['\\', '$']
    esc '\\' = Just ['\\', '\\']
    esc _ = Nothing
    
renderShell :: QuoteChar -> FilePath -> CmdArgs -> String
renderShell qc fp args =
  appEndo (quoted fp <> unCmdArgs args renderArg) []
  where
    char c = Endo (c :)
    quote =
      case qc of
        QuoteSingle -> char '\''
        QuoteDouble -> char '"'
    space = char ' '
    quoted str = quote <> renderEscapedQuotes qc str <> quote
    renderArg (CmdArg str) = space <> quoted str

renderShellDefault :: FilePath -> CmdArgs -> String
renderShellDefault = renderShell QuoteSingle

arg :: String -> CmdArgs
arg = singleton . CmdArg

shortFlag :: Char -> CmdArgs
shortFlag f = arg ['-', f]

shortArg :: Char -> String -> CmdArgs
shortArg k v = shortFlag k <> arg v

longFlag :: String -> CmdArgs
longFlag f = arg ('-' : '-' : f)

longArg :: String -> String -> CmdArgs
longArg k v = longFlag k <> arg v

cmdFromList :: [String] -> CmdArgs
cmdFromList = foldMap arg
