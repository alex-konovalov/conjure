{-# LANGUAGE DeriveGeneric, DeriveDataTypeable, DeriveFunctor, DeriveTraversable, DeriveFoldable #-}

module Conjure.Language.Ops.Party where

import Conjure.Prelude
import Conjure.Language.Ops.Common


data OpParty x = OpParty x x
    deriving (Eq, Ord, Show, Data, Functor, Traversable, Foldable, Typeable, Generic)

instance Serialize x => Serialize (OpParty x)
instance Hashable  x => Hashable  (OpParty x)
instance ToJSON    x => ToJSON    (OpParty x) where toJSON = genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpParty x) where parseJSON = genericParseJSON jsonOptions

instance (TypeOf x, Pretty x) => TypeOf (OpParty x) where
    typeOf inp@(OpParty x p) = do
        xTy <- typeOf x
        pTy <- typeOf p
        case pTy of
            TypePartition pTyInner | typesUnify [xTy, pTyInner] -> return $ TypeSet $ mostDefined [xTy, pTyInner]
            _ -> raiseTypeError inp

instance EvaluateOp OpParty where
    evaluateOp op@(OpParty x (ConstantAbstract (AbsLitPartition xss))) =
        let
            outSet = [ xs
                     | xs <- xss
                     , x `elem` xs
                     ]
        in
            case outSet of
                [s] -> return $ ConstantAbstract $ AbsLitSet s
                []  -> return $ mkUndef $ "Element not found in partition:" <++> pretty op
                _   -> return $ mkUndef $ "Element found in multiple parts of the partition:" <++> pretty op
    evaluateOp op = na $ "evaluateOp{OpParty}:" <++> pretty (show op)

instance SimplifyOp OpParty where
    simplifyOp _ _ = na "simplifyOp{OpParty}"

instance Pretty x => Pretty (OpParty x) where
    prettyPrec _ (OpParty a b) = "party" <> prettyList prParens "," [a,b]
