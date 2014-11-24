{-# LANGUAGE DeriveGeneric, DeriveDataTypeable #-}
{-# LANGUAGE Rank2Types #-}

module Conjure.Rules.Definition
    ( Rule(..), RuleResult, namedRule
    , Question(..), Answer(..)
    , LogOrModel, LogOr
    , Driver, Strategy(..), viewAuto, parseStrategy
    , Config(..)
    , isAtomic, representationOf, hasRepresentation, matchFirst
    ) where

import Conjure.Prelude
import Conjure.Language.Definition
import Conjure.Language.Domain
import Conjure.Language.Ops
import Conjure.Language.DomainOf


type LogOr a = Either (LogLevel, Doc) a
type LogOrModel = LogOr Model

data Question = Question
    { qHole       :: Expression
    , qAscendants :: [Expression]
    , qAnswers    :: [Answer]
    }

data Answer = Answer
    { aText      :: Doc
    , aAnswer    :: Expression
    , aFullModel :: Model
    }

type Driver = (forall m . (MonadIO m, MonadFail m, MonadLog m) => [Question] -> m [Model])

data Strategy
    = PickFirst
    | PickAll
    | Interactive
    -- | AtRandom
    | Auto Strategy
    deriving (Eq, Ord, Show, Read, Data, Typeable)

instance Default Strategy where def = Auto Interactive

viewAuto :: Strategy -> (Strategy, Bool)
viewAuto (Auto s) = second (const True) (viewAuto s)
viewAuto s = (s, False)

parseStrategy :: String -> Maybe Strategy
parseStrategy "f" = return PickFirst
parseStrategy "x" = return PickAll
parseStrategy "i" = return Interactive
parseStrategy ['a',s] = Auto <$> parseStrategy (return s)
parseStrategy _ = Nothing

data Config = Config
    { logLevel                  :: LogLevel
    , verboseTrail              :: Bool
    , logRuleFails              :: Bool
    , logRuleSuccesses          :: Bool
    , logRuleAttempts           :: Bool
    , strategyQ                 :: Strategy
    , strategyA                 :: Strategy
    , outputDirectory           :: FilePath
    , channelling               :: Bool
    , parameterRepresentation   :: Bool
    , limitModels               :: Maybe Int
    }
    deriving (Eq, Ord, Show, Read, Data, Typeable)

instance Default Config where
    def = Config
        { logLevel                  = LogNone
        , verboseTrail              = False
        , logRuleFails              = False
        , logRuleSuccesses          = False
        , logRuleAttempts           = False
        , strategyQ                 = Interactive
        , strategyA                 = Interactive
        , outputDirectory           = "conjure-output"
        , channelling               = True
        , parameterRepresentation   = True
        , limitModels               = Nothing
        }

type RuleResult = ( Doc                     -- describe this transformation
                  , [Name] -> Expression    -- the result
                  , Model -> Model          -- post-application hook
                  )

data Rule = Rule
    { rName  :: Doc
    , rApply :: forall m . MonadFail m => Expression -> m [RuleResult]
                           -- fail in a rule just means that the rule isn't applicable
    }

namedRule
    :: Doc
    -> (forall m . MonadFail m => Expression -> m (Doc, [Name] -> Expression))
    -> Rule
namedRule nm f = Rule
    { rName = nm
    , rApply = \ x -> let addId (d,y) = (d,y,id)
                      in  liftM (return . addId) (f x)
    }


isAtomic :: Expression -> Bool
isAtomic Reference{} = True
isAtomic (Op (MkOpIndexing (OpIndexing a _))) = isAtomic a
isAtomic _ = False


representationOf :: MonadFail m => Expression -> m Name
representationOf x = do
    dom <- domainOf x
    case reprAtTopLevel dom of
        Nothing -> fail "doesn't seem to have a representation"
        Just NoRepresentation -> fail "doesn't seem to have a representation"
        Just (HasRepresentation r) -> return r


hasRepresentation :: MonadFail m => Expression -> m ()
hasRepresentation x = do
    dom <- domainOf x
    case reprAtTopLevel dom of
        Nothing -> fail "doesn't seem to have a representation"
        Just NoRepresentation -> fail "doesn't seem to have a representation"
        Just HasRepresentation{} -> return ()


matchFirst
    :: MonadFail m
    => [a]                  -- list of things to try matching on
    -> (a -> Maybe b)       -- the matcher
    -> m ( [a]              -- befores
         , b                -- the matching one
         , [a]              -- afters
         )
matchFirst = helper []
    where
        helper _ [] _ = fail "No match."
        helper befores (x:xs) f = case f x of
            Nothing -> helper (x:befores) xs f
            Just y  -> return (reverse befores, y, xs)
