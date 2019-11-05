{-# LANGUAGE NoImplicitPrelude #-}
{- |
   Module      : Text.Pandoc.Readers.Org.ExportSettings
   Copyright   : © 2016–2019 Albert Krewinkel
   License     : GNU GPL, version 2 or above

   Maintainer  : Albert Krewinkel <tarleb+pandoc@moltkeplatz.de>

Parsers for Org-mode export options.
-}
module Text.Pandoc.Readers.Org.ExportSettings
  ( exportSettings
  ) where

import Prelude
import Text.Pandoc.Class (PandocMonad, report)
-- import Text.Pandoc.Logging (LogMessage (UnknownOrgExportOption)) -- TODO text: restore
import Text.Pandoc.Readers.Org.ParserState
import Text.Pandoc.Readers.Org.Parsing

import Control.Monad (mzero, void)
import Data.Char (toLower)
import Data.Maybe (listToMaybe)

-- TODO text: remove
import Text.Pandoc.Legacy.Logging
--

-- | Read and handle space separated org-mode export settings.
exportSettings :: PandocMonad m => OrgParser m ()
exportSettings = void $ sepBy skipSpaces exportSetting

-- | Setter function for export settings.
type ExportSettingSetter a = a -> ExportSettings -> ExportSettings

-- | Read and process a single org-mode export option.
exportSetting :: PandocMonad m => OrgParser m ()
exportSetting = choice
  [ booleanSetting "^" (\val es -> es { exportSubSuperscripts = val })
  , booleanSetting "'" (\val es -> es { exportSmartQuotes = val })
  , booleanSetting "*" (\val es -> es { exportEmphasizedText = val })
  , booleanSetting "-" (\val es -> es { exportSpecialStrings = val })
  , ignoredSetting ":"
  , ignoredSetting "<"
  , booleanSetting "\\n" (\val es -> es { exportPreserveBreaks = val })
  , archivedTreeSetting "arch" (\val es -> es { exportArchivedTrees = val })
  , booleanSetting "author" (\val es -> es { exportWithAuthor = val })
  , ignoredSetting "c"
  -- org-mode allows the special value `comment` for creator, which we'll
  -- interpret as true as it doesn't make sense in the context of Pandoc.
  , booleanSetting "creator" (\val es -> es { exportWithCreator = val })
  , complementableListSetting "d" (\val es -> es { exportDrawers = val })
  , ignoredSetting "date"
  , ignoredSetting "e"
  , booleanSetting "email" (\val es -> es { exportWithEmail = val })
  , ignoredSetting "f"
  , integerSetting "H" (\val es -> es { exportHeadlineLevels = val })
  , ignoredSetting "inline"
  , ignoredSetting "num"
  , booleanSetting "p" (\val es -> es { exportWithPlanning = val })
  , ignoredSetting "pri"
  , ignoredSetting "prop"
  , ignoredSetting "stat"
  , booleanSetting "tags" (\val es -> es { exportWithTags = val })
  , ignoredSetting "tasks"
  , ignoredSetting "tex"
  , ignoredSetting "timestamp"
  , ignoredSetting "title"
  , ignoredSetting "toc"
  , booleanSetting "todo" (\val es -> es { exportWithTodoKeywords = val })
  , ignoredSetting "|"
  , ignoreAndWarn
  ] <?> "export setting"

genericExportSetting :: Monad m
                     => OrgParser m a
                     -> String
                     -> ExportSettingSetter a
                     -> OrgParser m ()
genericExportSetting optionParser settingIdentifier setter = try $ do
  _     <- string settingIdentifier *> char ':'
  value <- optionParser
  updateState $ modifyExportSettings value
 where
   modifyExportSettings val st =
     st { orgStateExportSettings = setter val . orgStateExportSettings $ st }

-- | A boolean option, either nil (False) or non-nil (True).
booleanSetting :: Monad m => String ->  ExportSettingSetter Bool -> OrgParser m ()
booleanSetting = genericExportSetting elispBoolean

-- | An integer-valued option.
integerSetting :: Monad m => String -> ExportSettingSetter Int -> OrgParser m ()
integerSetting = genericExportSetting parseInt
 where
   parseInt = try $
     many1 digit >>= maybe mzero (return . fst) . listToMaybe . reads

-- | Either the string "headline" or an elisp boolean and treated as an
-- @ArchivedTreesOption@.
archivedTreeSetting :: Monad m
                    => String
                    -> ExportSettingSetter ArchivedTreesOption
                    -> OrgParser m ()
archivedTreeSetting =
  genericExportSetting $ archivedTreesHeadlineSetting <|> archivedTreesBoolean
 where
   archivedTreesHeadlineSetting = try $ do
     _ <- string "headline"
     lookAhead (newline <|> spaceChar)
     return ArchivedTreesHeadlineOnly

   archivedTreesBoolean = try $ do
     exportBool <- elispBoolean
     return $
       if exportBool
       then ArchivedTreesExport
       else ArchivedTreesNoExport

-- | A list or a complement list (i.e. a list starting with `not`).
complementableListSetting :: Monad m
                          => String
                          -> ExportSettingSetter (Either [String] [String])
                          -> OrgParser m ()
complementableListSetting = genericExportSetting $ choice
  [ Left  <$> complementStringList
  , Right <$> stringList
  , (\b -> if b then Left [] else Right []) <$> elispBoolean
  ]
 where
   -- Read a plain list of strings.
   stringList :: Monad m => OrgParser m [String]
   stringList = try $
     char '('
       *> sepBy elispString spaces
       <* char ')'

   -- Read an emacs lisp list specifying a complement set.
   complementStringList :: Monad m => OrgParser m [String]
   complementStringList = try $
     string "(not "
       *> sepBy elispString spaces
       <* char ')'

   elispString :: Monad m => OrgParser m String
   elispString = try $
     char '"'
       *> manyTill alphaNum (char '"')

-- | Read but ignore the export setting.
ignoredSetting :: Monad m => String -> OrgParser m ()
ignoredSetting s = try (() <$ string s <* char ':' <* many1 nonspaceChar)

-- | Read any setting string, but ignore it and emit a warning.
ignoreAndWarn :: PandocMonad m => OrgParser m ()
ignoreAndWarn = try $ do
  opt <- many1 nonspaceChar
  report (UnknownOrgExportOption opt)
  return ()

-- | Read an elisp boolean.  Only NIL is treated as false, non-NIL values are
-- interpreted as true.
elispBoolean :: Monad m => OrgParser m Bool
elispBoolean = try $ do
  value <- many1 nonspaceChar
  return $ case map toLower value of
             "nil" -> False
             "{}"  -> False
             "()"  -> False
             _     -> True
