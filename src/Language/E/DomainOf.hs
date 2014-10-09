{-# LANGUAGE QuasiQuotes, ViewPatterns, OverloadedStrings #-}

module Language.E.DomainOf
    ( errDomainOf
    , domainOf
    , innerDomainOf
    ) where

import Conjure.Prelude
import Conjure.Bug
import Language.E.Definition
import Language.E.CompE
import Language.E.Pretty
import {-# SOURCE #-} Language.E.Evaluator.ToInt


errDomainOf :: MonadConjure m => E -> m E
errDomainOf p = do
    bsText <- bindersDoc
    err ErrFatal $ vcat [ "Cannot calculate the domain of" <+> prettyAsPaths p
                        , bsText
                        ]

class DomainOf a where
    domainOf :: MonadConjure m => a -> m (Domain () E)

instance DomainOf E where

    domainOf (D d) = return d

    domainOf [xMatch| [Prim (S i)] := reference |] =
        if i `elem` ["_", "forAll", "exists", "sum"]
            then bug $ "domainOf:" <+> pretty i
            else do
                x <- errMaybeT "domainOf" lookupReference i
                domainOf x

    domainOf p@[xMatch| [Prim (S i)] := metavar |] = do
        mx <- runMaybeT $ lookupMetaVar i
        case mx of
            Just x  -> domainOf x
            Nothing -> bug $ "domainOf:" <+> pretty p
            -- Nothing -> return (DomainHack p) -- this is for hasDomain pattern matching in rules to work

    domainOf [xMatch| [x] := topLevel.declaration.find .domain |] = domainOf x
    domainOf [xMatch| [x] := topLevel.declaration.given.domain |] = domainOf x

    domainOf [xMatch| [x] := domainInExpr |] = domainOf x

    domainOf [xMatch| [x] := structural.single |] = domainOf x

    domainOf [xMatch| [Prim (S n1)] := quanVar.name
                    | [Prim (S n2)] := quanVar.within.quantified.quanVar.structural.single.reference
                    | [D d]         := quanVar.within.quantified.quanOverDom
                    |] | n1 == n2 = return d

    domainOf inp@[xMatch| [Prim (S n1)] := quanVar.name
                        | [Prim (S n2)] := quanVar.within.quantified.quanVar.structural.single.reference
                        | []            := quanVar.within.quantified.quanOverDom
                        | []            := quanVar.within.quantified.quanOverOp.binOp.in
                        | [x]           := quanVar.within.quantified.quanOverExpr
                        |] | n1 == n2 = do
        domX <- domainOf x
        case innerDomainOf domX of
            Just i -> return i
            Nothing -> bug $ "domainOf:" <+> pretty inp
                -- mkLog "missing:domainOf" $ "Cannot calculate the inner domain of" <+> pretty domX
                -- return (DomainHack inp)

    domainOf p@[xMatch| [] := quanVar |] = bug $ "domainOf:" <+> pretty p

    domainOf p@[xMatch| [x] := operator.index.left
                      | [y] := operator.index.right
                      |] = do
        xDom <- domainOf x
        case xDom of
            DomainMatrix _ innerDom -> return innerDom
            DomainTuple innerDoms -> do
                yInt <- toInt y
                case yInt of
                    Just (int, _)
                        | int >= 1 && int <= genericLength innerDoms
                        -> return $ innerDoms `genericIndex` (int - 1)
                    _ -> bug $ "domainOf:" <+> pretty p
            _ -> bug $ "domainOf:" <+> pretty p

    domainOf p@[xMatch| [f] := operator.range |] = do
        fDom <- domainOf f
        case fDom of
            DomainFunction _ _ _ innerDom -> do
                let out = DomainSet () def innerDom
                mkLog "domainOf returning" $ pretty out
                return out
            _ -> bug $ "domainOf:" <+> pretty p

    domainOf x = do
        mkLog "missing:domainOf" (pretty x)
        bug $ "domainOf:" <+> pretty x


innerDomainOf :: Domain r a -> Maybe (Domain r a)
innerDomainOf (DomainSet _ _ inner) = return inner
innerDomainOf (DomainMSet _ _ inner) = return inner
innerDomainOf (DomainFunction _ _ fr to) = return (DomainTuple [fr,to])
innerDomainOf (DomainRelation _ _ inners) = return (DomainTuple inners)
innerDomainOf _ = Nothing


