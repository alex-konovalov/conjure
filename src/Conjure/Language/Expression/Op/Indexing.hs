{-# LANGUAGE DeriveGeneric, DeriveDataTypeable, DeriveFunctor, DeriveTraversable, DeriveFoldable #-}

module Conjure.Language.Expression.Op.Indexing where

import Conjure.Prelude
import Conjure.Bug
import Conjure.Language.Expression.Op.Internal.Common


data OpIndexing x = OpIndexing x x
    deriving (Eq, Ord, Show, Data, Functor, Traversable, Foldable, Typeable, Generic)

instance Serialize x => Serialize (OpIndexing x)
instance Hashable  x => Hashable  (OpIndexing x)
instance ToJSON    x => ToJSON    (OpIndexing x) where toJSON = genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpIndexing x) where parseJSON = genericParseJSON jsonOptions

instance (TypeOf x, Show x, Pretty x, ExpressionLike x, ReferenceContainer x) => TypeOf (OpIndexing x) where
    typeOf p@(OpIndexing m i) = do
        tyM <- typeOf m
        -- tyI <- typeOf i
        let tyI = TypeAny
        case tyM of
            TypeMatrix tyIndex inn
                | typesUnify [tyIndex, tyI] -> return inn
                | otherwise -> fail $ "Indexing with inappropriate type:" <++> vcat
                    [ "The expression:"  <+> pretty p
                    , "Indexing:"        <+> pretty m
                    , "Expected type of index:" <+> pretty tyIndex
                    , "Actual type of index  :" <+> pretty tyI
                    ]
            TypeList inn
                | typesUnify [TypeInt, tyI] -> return inn
                | otherwise -> fail $ "Indexing with inappropriate type:" <++> vcat
                    [ "The expression:"  <+> pretty p
                    , "Indexing:"        <+> pretty m
                    , "Expected type of index:" <+> pretty TypeInt
                    , "Actual type of index  :" <+> pretty tyI
                    ]
            TypeTuple inns   -> do
                TypeInt{} <- typeOf i
                iInt <- intOut i
                return (at inns (fromInteger (iInt-1)))
            TypeRecord inns  -> do
                nm <- nameOut i
                case lookup nm inns of
                    Nothing -> fail $ "Record indexing with non-member field:" <++> vcat
                        [ "The expression:" <+> pretty p
                        , "Indexing:"       <+> pretty m
                        , "With type:"      <+> pretty tyM
                        ]
                    Just ty -> return ty
            TypeVariant inns -> do
                nm <- nameOut i
                case lookup nm inns of
                    Nothing -> fail $ "Variant indexing with non-member field:" <++> vcat
                        [ "The expression:" <+> pretty p
                        , "Indexing:"       <+> pretty m
                        , "With type:"      <+> pretty tyM
                        ]
                    Just ty -> return ty
            _ -> fail $ "Indexing something other than a matrix or a tuple:" <++> vcat
                    [ "The expression:" <+> pretty p
                    , "Indexing:"       <+> pretty m
                    , "With type:"      <+> pretty tyM
                    ]

instance (Pretty x, ExpressionLike x, DomainOf x x, TypeOf x) => DomainOf (OpIndexing x) x where
    domainOf (OpIndexing m i) = do
        iType <- typeOf i
        case iType of
            TypeBool{} -> return ()
            TypeInt{} -> return ()
            _ -> fail "domainOf, OpIndexing, not a bool or int index"
        mDom <- domainOf m
        case mDom of
            DomainMatrix _ inner -> return inner
            DomainTuple inners -> do
                iInt <- intOut i
                return $ atNote "domainOf" inners (fromInteger (iInt-1))
            _ -> fail "domainOf, OpIndexing, not a matrix or tuple"

instance EvaluateOp OpIndexing where
    evaluateOp (OpIndexing m@(ConstantAbstract (AbsLitMatrix (DomainInt index) vals)) (ConstantInt x)) = do
        ty   <- typeOf m
        tyTo <- case ty of TypeMatrix _ tyTo -> return tyTo
                           TypeList tyTo     -> return tyTo
                           _ -> fail "evaluateOp{OpIndexing}"
        indexVals <- valuesInIntDomain index
        case [ v | (i, v) <- zip indexVals vals, i == x ] of
            [v] -> return v
            []  -> return $ mkUndef tyTo $ vcat
                    [ "Matrix is not defined at this point:" <+> pretty x
                    , "Matrix value:" <+> pretty m
                    ]
            _   -> return $ mkUndef tyTo $ vcat
                    [ "Matrix is multiply defined at this point:" <+> pretty x
                    , "Matrix value:" <+> pretty m
                    ]
    evaluateOp (OpIndexing (ConstantAbstract (AbsLitTuple vals)) (ConstantInt x)) = return (at vals (fromInteger (x-1)))
    evaluateOp rec@(OpIndexing (ConstantAbstract (AbsLitRecord vals)) (ConstantField name _)) =
        case lookup name vals of
            Nothing -> bug $ vcat
                    [ "Record doesn't have a member with this name:" <+> pretty name
                    , "Record:" <+> pretty rec
                    ]
            Just val -> return val
    evaluateOp var@(OpIndexing (ConstantAbstract (AbsLitVariant _ name' x)) (ConstantField name ty)) =
        if name == name'
            then return x
            else return $ mkUndef ty $ vcat
                    [ "Variant isn't set to a member with this name:" <+> pretty name
                    , "Variant:" <+> pretty var
                    ]
    evaluateOp op = na $ "evaluateOp{OpIndexing}:" <++> pretty (show op)

instance SimplifyOp OpIndexing x where
    simplifyOp _ = na "simplifyOp{OpIndexing}"

instance Pretty x => Pretty (OpIndexing x) where
    prettyPrec _ (OpIndexing  a b) = pretty a <> prBrackets (pretty b)
