{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE ViewPatterns          #-}
module Filter where

import Text.Pandoc.JSON
import Text.Pandoc.Definition ()
import Data.Function(on)
import Data.String (fromString, IsString)
import Data.Text (Text)
import Data.List(groupBy, sortBy)
import Debug.Trace(trace)
import Prelude hiding(getLine)

import Token
import Token.Haskell

data Align =
    ALeft
  | ACenter
  deriving (Eq, Ord, Show)

-- | Records tokenized and converted to common token format.
type Unanalyzed = (MyTok, MyLoc, Maybe Int,              Text)
type Aligned    = (MyTok, MyLoc, Maybe Int, Maybe Align, Text)

findColumns :: Text -> _
findColumns input@(tokenizer -> Nothing    ) = error "Haskell tokenizer failed."
findColumns       (tokenizer -> Just tokens) =
      sortBy (compare `on` getLineCol)
    $ concat
    $ map markBoundaries
    $ grouping getCol
    $ concat
    $ map addLineIndent
    $ grouping getLine tokens
  where
    compareLine = (==) `on` getLine
    getLineCol (_, MyLoc line col, _, _, _) = (line, col)
    getCol  (_, MyLoc _  col, _, _) = col

getCol  (_, MyLoc _  col, _) = col
getLine (_, MyLoc line _, _) = line

markBoundaries :: [Unanalyzed] -> [Aligned]
markBoundaries = fmap markIndent
               . concat
               . map alignBlock
               . blocks
               . sortBy (compare `on` getLine)
  where
    getLine (tok, MyLoc line col, _, _) = line

-- | If first indented token is yet unmarked, mark it as boundary.
markIndent :: Aligned -> Aligned
markIndent (myTok, myLoc@(MyLoc _ col), Just indent, Nothing,    txt) | indent == col =
           (myTok, myLoc              , Just indent, Just ALeft, txt)
markIndent other                                                               = other

withAlign :: Maybe Align -> Unanalyzed -> Aligned
withAlign a (myTok, myLoc, indent, myTxt) = (myTok, myLoc, indent, a, myTxt)

alignBlock :: [Unanalyzed] -> [Aligned]
alignBlock [a]                            = withAlign   Nothing      <$> [a]
alignBlock opList | all isOperator opList = withAlign (Just ACenter) <$> opList
  where
    isOperator (TOperator, _, _, _) = True
    isOperator  _                   = False
alignBlock aList                          = withAlign (Just ALeft  ) <$> aList

-- | Detect uninterrupted stretches that cover consecutive columns.
blocks :: [Unanalyzed] -> [[Unanalyzed]]
blocks (b:bs) = go [b] bs
  where
    getLine (_, MyLoc line _, _, _) = line
    go currentBlock@(getLine . head -> lastCol) (b@(getLine -> nextCol):bs)
      | nextCol - lastCol == 1 = -- add ignoring of unindented (Nothing)
        go (b:currentBlock)         bs
    go (c:currentBlock)                         (blank@(_,_,Nothing, _):bs) =
        go (c:blank:currentBlock)   bs
    go currentBlock                             (b                     :bs) =
        reverse currentBlock:go [b] bs
    go currentBlock                             []                          =
       [reverse currentBlock]

--withGroups k f = map k . grouping k

grouping    :: _
grouping key = groupBy ((==)    `on` key)
             . sortBy  (compare `on` key)

-- | Add line indent to each token in line.
addLineIndent :: [Tokenized] -> [Unanalyzed]
addLineIndent aLine = addIndent indentColumn <$> aLine
  where
    indentColumn :: Maybe Int
    indentColumn = extractColumn $ filter notBlank aLine
    notBlank       (TBlank, _, _)               = False
    notBlank        _                           = True
    extractColumn  []                           = Nothing
    extractColumn  ((_,   MyLoc line col, _):_) = Just col
    addIndent indentCol (tok, myLoc, txt)       = (tok, myLoc, indentCol, txt)
