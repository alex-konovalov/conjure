{-# LANGUAGE QuasiQuotes, ViewPatterns, OverloadedStrings #-}

module Language.E.TypeOf ( typeCheckSpec, typeOf, innerTypeOf, mostKnown ) where

import Stuff.Generic

import Language.E.Imports
import Language.E.Definition
import Language.E.CompE
import Language.E.TH
import Language.E.Traversals
import {-# SOURCE #-} Language.E.Evaluator.ToInt
import Language.E.Pretty
import Language.E.Parser

import qualified Data.Text as T


typeCheckSpec :: MonadConjure m => Spec -> m ()
typeCheckSpec (Spec _ x) = withBindingScope' $
    forM_ (statementAsList x) $ \ st -> do
        introduceStuff st
        let tyExpected = case st of
                [xMatch| _ := topLevel.suchThat  |] -> Just tyBool
                [xMatch| _ := topLevel.objective |] -> Just tyInt
                [xMatch| _ := topLevel.where     |] -> Just tyBool
                _ -> Nothing
        case tyExpected of
            Nothing  -> return ()
            Just ty' -> do
                ty <- typeOf st
                if ty `typeUnify` ty'
                    then return ()
                    else typeErrorIn st


typeUnify :: E -> E -> Bool
typeUnify [xMatch| _ := type.unknown |] _ = True
typeUnify _ [xMatch| _ := type.unknown |] = True
typeUnify
    [xMatch| [] := type.bool |]
    [xMatch| [] := type.bool |]
    = True
typeUnify
    [xMatch| [] := type.int  |]
    [xMatch| [] := type.int  |]
    = True
typeUnify
    [xMatch| [Prim (S a)] := type.enum |]
    [xMatch| [Prim (S b)] := type.enum |]
    = a == b
typeUnify
    [xMatch| [a1] := type.matrix.index
           | [b1] := type.matrix.inner
           |]
    [xMatch| [a2] := type.matrix.index
           | [b2] := type.matrix.inner
           |] = typeUnify a1 a2 && typeUnify b1 b2
typeUnify
    [xMatch| [a] := type.set.inner |]
    [xMatch| [b] := type.set.inner |]
    = typeUnify a b
typeUnify
    [xMatch| [a] := type.mset.inner |]
    [xMatch| [b] := type.mset.inner |]
    = typeUnify a b
typeUnify
    [xMatch| [aFr] := type.function.innerFrom
           | [aTo] := type.function.innerTo
           |]
    [xMatch| [bFr] := type.function.innerFrom
           | [bTo] := type.function.innerTo
           |]
    = typeUnify aFr bFr && typeUnify aTo bTo
typeUnify
    [xMatch| [a1,b1] := mapping |]
    [xMatch| [a2,b2] := mapping |]
    = typeUnify a1 a2 && typeUnify b1 b2
typeUnify
    [xMatch| as := type.tuple.inners |]
    [xMatch| bs := type.tuple.inners |]
    = if length as == length bs
        then and $ zipWith typeUnify as bs
        else False
typeUnify
    [xMatch| as := type.relation.inners |]
    [xMatch| bs := type.relation.inners |]
    = if length as == length bs
        then and $ zipWith typeUnify as bs
        else False
typeUnify
    [xMatch| [a] := type.partition.inner |]
    [xMatch| [b] := type.partition.inner |]
    = typeUnify a b
typeUnify x y = trace ( show $ vcat [ "missing:typeUnify"
                                    , pretty x <+> "~~" <+> pretty y
                                    -- , prettyAsPaths x
                                    -- , prettyAsPaths y
                                    ]
                      )
                      (x == y)

mostKnown :: MonadConjure m => E -> E -> m E
mostKnown [xMatch| _ := type.unknown |] x = return x
mostKnown x [xMatch| _ := type.unknown |] = return x
mostKnown [xMatch| [a] := type.set.inner |]
          [xMatch| [b] := type.set.inner |] = do
              x <- mostKnown a b
              return [xMake| type.set.inner := [x] |]
mostKnown [xMatch| [a] := type.mset.inner |]
          [xMatch| [b] := type.mset.inner |] = do
              x <- mostKnown a b
              return [xMake| type.mset.inner := [x] |]
mostKnown [xMatch| [aF] := type.function.innerFrom
                 | [aT] := type.function.innerTo
                 |]
          [xMatch| [bF] := type.function.innerFrom
                 | [bT] := type.function.innerTo
                 |] = do
              xF <- mostKnown aF bF
              xT <- mostKnown aT bT
              return [xMake| type.function.innerFrom := [xF]
                           | type.function.innerTo   := [xT]
                           |]
mostKnown x y = do
    mkLog "missing:mostKnown" $ pretty x <+> "~~" <+> pretty y
    return x


_testTypeOf :: T.Text -> IO ()
_testTypeOf t = do
    let res = runLexerAndParser (inCompleteFile parseExpr) "" t
    case res of
        Left  e -> print e
        Right x -> do
            print $ pretty x
            y <- (handleInIOSingle <=< runCompEIOSingle "testTypeOf") (typeOf x)
            print $ pretty y


typeErrorIn :: MonadConjure m => E -> m a
typeErrorIn p = typeErrorIn' p ""

typeErrorIn' :: MonadConjure m => E -> Doc -> m a
typeErrorIn' p d = err ErrFatal $ "Type error in: " <+> vcat [ pretty p
                                                             -- , prettyAsTree p
                                                             -- , prettyAsPaths p
                                                             , d
                                                             ]


typeOf :: MonadConjure m => E -> m E

-- typeOf p | trace ("typeOf: " ++ (show $ pretty p)) False = undefined

typeOf [xMatch| [x] := topLevel.suchThat             |] = typeOf x
typeOf [xMatch| [x] := topLevel.where                |] = typeOf x
typeOf [xMatch| [x] := topLevel.objective.minimising |] = typeOf x
typeOf [xMatch| [x] := topLevel.objective.maximising |] = typeOf x

typeOf (Prim (B {})) = return tyBool
typeOf (Prim (I {})) = return [xMake| type.int  := [] |]

typeOf p@[xMatch| _ := type |] = return p

typeOf [xMatch| [Prim (S "_")] := reference |] = return [xMake| type.unknown := [] |]
typeOf [xMatch| [Prim (S i  )] := reference |] = do
    x <- errMaybeT "typeOf" lookupReference i
    typeOf x

typeOf [xMatch| [Prim (S i)] := metavar |] = do
    x <- errMaybeT "typeOf" lookupMetaVar i
    typeOf x

typeOf [xMatch| [i] := structural.single |] = typeOf i

typeOf [xMatch| [d] := topLevel.declaration.find .domain  |] = typeOf d
typeOf [xMatch| [d] := topLevel.declaration.given.domain  |] = typeOf d
typeOf [xMatch| [d] := topLevel.declaration.dim  .domain  |] = typeOf d
typeOf [xMatch| [ ] := topLevel.declaration.given.typeInt |] = return tyInt
typeOf [xMatch| [Prim (S nm)] := topLevel.letting.name.reference
              | _             := topLevel.letting.typeEnum
              |] = return [xMake| type.enum := [Prim (S nm)] |]

typeOf [xMatch| [d] := typed.right |] = typeOf d

-- domain.*

typeOf [xMatch| [d] := domainInExpr |] = typeOf d

typeOf [xMatch| [lhs] := domain.binOp.left
              | [rhs] := domain.binOp.right
              | [Prim (S op)] := domain.binOp.operator
              |] | op `elem` ["-", "union", "intersect"] = do
    lhsTy <- typeOf lhs
    rhsTy <- typeOf rhs
    mostKnown lhsTy rhsTy

typeOf [xMatch| _ := domain.bool |] = return tyBool
typeOf [xMatch| _ := domain.int  |] = return [xMake| type.int  := [] |]

typeOf [xMatch| [Prim (S nm)] := domain.enum.name.reference
              |] = return [xMake| type.enum := [Prim (S nm)] |]

typeOf [xMatch| [index] := domain.matrix.index
              | [inner] := domain.matrix.inner
              |] = do
    tIndex <- typeOf index
    tInner <- typeOf inner
    return [xMake| type.matrix.index := [tIndex]
                 | type.matrix.inner := [tInner]
                 |]

typeOf [xMatch| ds := domain.tuple.inners |] = do
    ts <- mapM typeOf ds
    return [xMake| type.tuple.inners := ts |]

typeOf [xMatch| [fr] := domain.function.innerFrom
              | [to] := domain.function.innerTo
              |] = do
    frTy <- typeOf fr
    toTy <- typeOf to
    return [xMake| type.function.innerFrom := [frTy]
                 | type.function.innerTo   := [toTy]
                 |]

typeOf [xMatch| [i] := domain.set.inner |] = do
    ti <- typeOf i
    return [xMake| type.set.inner := [ti] |]

typeOf [xMatch| [i] := domain.mset.inner |] = do
    ti <- typeOf i
    return [xMake| type.mset.inner := [ti] |]

typeOf [xMatch| xs := domain.relation.inners |] = do
    txs <- mapM typeOf xs
    return [xMake| type.relation.inners := txs |]

typeOf [xMatch| [i] := domain.partition.inner |] = do
    ti <- typeOf i
    return [xMake| type.partition.inner := [ti] |]

-- value.*

typeOf [xMatch| [i] := value.literal |] = typeOf i

typeOf [xMatch| xs := value.tuple.values |] = do
    txs <- mapM typeOf xs
    return [xMake| type.tuple.inners := txs |]

typeOf [xMatch| xs := value.matrix.values |] = do
    let tInt = tyInt
    txs <- mapM typeOf xs
    return [xMake| type.matrix.index := [tInt]
                 | type.matrix.inner := [head txs]
                 |]

typeOf   [xMatch| [] := value.set.values |] = return [xMake| type.set.inner.type.unknown := [] |]
typeOf p@[xMatch| xs := value.set.values |] = do
    (tx:txs) <- mapM typeOf xs
    if and (map (tx `typeUnify`) txs)
        then return [xMake| type.set.inner := [tx] |]
        else typeErrorIn p

typeOf   [xMatch| [] := value.mset.values |] = return [xMake| type.mset.inner.type.unknown := [] |]
typeOf p@[xMatch| xs := value.mset.values |] = do
    (tx:txs) <- mapM typeOf xs
    if and (map (tx `typeUnify`) txs)
        then return [xMake| type.mset.inner := [tx] |]
        else typeErrorIn p

typeOf   [xMatch| [] := value.function.values |] = return [xMake| type.function.innerFrom.type.unknown := []
                                                                | type.function.innerTo  .type.unknown := []
                                                                |]
typeOf p@[xMatch| xs := value.function.values |] = do
    (tx:txs) <- mapM typeOf xs
    if and (map (tx `typeUnify`) txs)
        then case tx of
            [xMatch| [i,j] := mapping |] ->
                return [xMake| type.function.innerFrom := [i]
                             | type.function.innerTo   := [j]
                             |]
            _ -> typeErrorIn p
        else typeErrorIn p

typeOf   [xMatch| [] := value.relation.values |] = return [xMake| type.relation.inners := [] |]
typeOf p@[xMatch| xs := value.relation.values |] = do
    (tx:txs) <- mapM typeOf xs
    if and (map (tx `typeUnify`) txs)
        then case tx of
            [xMatch| is := type.tuple.inners |] -> return [xMake| type.relation.inners := is |]
            _ -> typeErrorIn p
        else typeErrorIn p

typeOf   [xMatch| [] := value.partition.values |] = return [xMake| type.partition.inner.type.unknown := [] |]
typeOf p@[xMatch| xs := value.partition.values |] = do
    (tx:txs) <- mapM typeOf xs
    if and (map (tx `typeUnify`) txs)
        then return [xMake| type.partition.inner := [tx] |]
        else typeErrorIn p

typeOf   [xMatch| [] := part |] = return [xMake| type.unknown := [] |]
typeOf p@[xMatch| xs := part |] = do
    (tx:txs) <- mapM typeOf xs
    if and (map (tx `typeUnify`) txs)
        then return tx
        else typeErrorIn p


-- expressions

typeOf [xMatch| [x] := unaryOp.negate |] = typeOf x

typeOf [xMatch| [i,j] := mapping |] = do
    iType <- typeOf i
    jType <- typeOf j
    return [xMake| mapping := [iType, jType] |]

typeOf p@[eMatch| &a = &b |] = do
    tya <- typeOf a
    tyb <- typeOf b
    if tya `typeUnify` tyb
        then return tyBool
        else typeErrorIn p

typeOf p@[eMatch| &a != &b |] = do
    tya <- typeOf a
    tyb <- typeOf b
    if tya `typeUnify` tyb
        then return tyBool
        else typeErrorIn p

typeOf p@[eMatch| ! &a |] = do
    tya <- typeOf a
    case tya of
        [xMatch| [] := type.bool |] -> return tyBool
        _ -> typeErrorIn p

typeOf p@[eMatch| allDiff(&a) |] = do
    tya <- typeOf a
    case tya of
        [xMatch| _ := type.matrix |] -> return tyBool
        _ -> typeErrorIn p

typeOf p@[eMatch| toInt(&a) |] = do
    tya <- typeOf a
    case tya of
        [xMatch| [] := type.bool |] -> return tyInt
        _ -> typeErrorIn p

typeOf p@[eMatch| parts(&x) |] = do
    tyx <- typeOf x
    case tyx of
        [xMatch| [i] := type.partition.inner |] ->
            return [xMake| type.set.inner.type.set.inner := [i] |]
        _ -> typeErrorIn p

typeOf p@[eMatch| hist(&m, &n) |] = do
    tym <- typeOf m
    tyn <- typeOf n
    case (tym, tyn) of
        ( [xMatch| [mInner] := type.matrix.inner |]
         , [xMatch| [nIndex] := type.matrix.index
                  | [nInner] := type.matrix.inner
                  |]
          ) | mInner `typeUnify` nInner ->
                let tInt = tyInt
                in  return [xMake| type.matrix.index := [ nIndex ]
                                 | type.matrix.inner := [ tInt   ]
                                 |]
        _ -> typeErrorIn p


typeOf [xMatch| [i] := quanVar.within.quantified.quanOverDom |] = typeOf i

typeOf [xMatch| [i] := quanVar.within.quantified.quanOverExpr
              | [ ] := quanVar.within.quantified.quanOverOp.binOp.in
              |] = do
    ti <- typeOf i
    case innerTypeOf ti of
        Nothing -> err ErrFatal $ "Cannot determine the inner type of: " <+> prettyAsPaths ti
        Just j  -> return j

typeOf [xMatch| [i] := quanVar.within.quantified.quanOverExpr
              | [ ] := quanVar.within.quantified.quanOverOp.binOp.subset
              |] = typeOf i

typeOf [xMatch| [i] := quanVar.within.quantified.quanOverExpr
              | [ ] := quanVar.within.quantified.quanOverOp.binOp.subsetEq
              |] = typeOf i

typeOf [xMatch| [Prim (S "forAll")] := quantified.quantifier.reference |] =
    return tyBool

typeOf [xMatch| [Prim (S "exists")] := quantified.quantifier.reference |] =
    return tyBool

typeOf [xMatch| [Prim (S "sum")] := quantified.quantifier.reference |] =
    return tyInt

typeOf p@[xMatch| [x] := operator.twoBars |] = do
    tx <- typeOf x
    case tx of
        [xMatch| [] := type.int      |] -> return tyInt
        [xMatch| _  := type.set      |] -> return tyInt
        [xMatch| _  := type.mset     |] -> return tyInt
        [xMatch| _  := type.function |] -> return tyInt
        _ -> typeErrorIn p

typeOf p@[xMatch| [m,i'] := operator.indices |] = do
    i <- case i' of
        [xMatch| [Prim (I i)] := value.literal |] -> return i
        _ -> typeErrorIn p
    tm <- typeOf m

    let
        getIndex 0 [xMatch| [indexTy] := type.matrix.index
                          |] = return indexTy
        getIndex n [xMatch| [innerTy] := type.matrix.inner
                          |] = getIndex (n-1) innerTy
        getIndex _ _ = typeErrorIn p

    getIndex i tm

typeOf p@[eMatch| toSet(&x) |] = do
    tx <- typeOf x
    case tx of
        [xMatch| [innerTy] := type.mset.inner |] -> return [xMake| type.set.inner := [innerTy] |]
        [xMatch| innerTys  := type.relation.inners |] -> return [xMake| type.set.inner.type.tuple.inners := innerTys |]
        [xMatch| [innerFr] := type.function.innerFrom
               | [innerTo] := type.function.innerTo
               |] -> return [xMake| type.set.inner.type.tuple.inners := [innerFr,innerTo] |]
        _ -> typeErrorIn p

typeOf p@[eMatch| toMSet(&x) |] = do
    tx <- typeOf x
    case tx of
        [xMatch| [innerTy] := type.set.inner |] -> return [xMake| type.mset.inner := [innerTy] |]
        [xMatch| innerTys  := type.relation.inners |] -> return [xMake| type.mset.inner.type.tuple.inners := innerTys |]
        [xMatch| [innerFr] := type.function.innerFrom
               | [innerTo] := type.function.innerTo
               |] -> return [xMake| type.mset.inner.type.tuple.inners := [innerFr,innerTo] |]
        _ -> typeErrorIn p

typeOf p@[eMatch| toRelation(&x) |] = do
    tx <- typeOf x
    case tx of
        [xMatch| [innerFr] := type.function.innerFrom
               | [innerTo] := type.function.innerTo
               |] -> return [xMake| type.relation.inners := [innerFr,innerTo] |]
        _ -> typeErrorIn p

typeOf p@[eMatch| freq(&m,&i) |]  = do
    tm <- typeOf m
    ti <- typeOf i
    case tm of
        [xMatch| [tmInner] := type.mset.inner |] -> do
            if typeUnify tmInner ti
                then return tyInt
                else typeErrorIn p
        [xMatch| [tmInner] := type.matrix.inner |] -> do
            if typeUnify tmInner ti
                then return tyInt
                else typeErrorIn p
        _ -> typeErrorIn p

typeOf p@[eMatch| &a intersect &b |] = do
    ta <- typeOf a
    tb <- typeOf b
    case (ta, tb) of
        ([xMatch| [ia] := type.set.inner |], [xMatch| [ib] := type.set.inner |]) -> do
            if typeUnify ia ib
                then mostKnown ta tb
                else typeErrorIn p
        ([xMatch| [ia] := type.mset.inner |], [xMatch| [ib] := type.mset.inner |]) -> do
            if typeUnify ia ib
                then mostKnown ta tb
                else typeErrorIn p
        ([xMatch| [iaF] := type.function.innerFrom
                | [iaT] := type.function.innerTo
                |], [xMatch| [ibF] := type.function.innerFrom
                           | [ibT] := type.function.innerTo
                           |]) -> do
            let resF = typeUnify iaF ibF
            let resT = typeUnify iaT ibT
            if resF && resT
                then mostKnown ta tb
                else typeErrorIn p
        _ -> typeErrorIn p

typeOf p@[eMatch| &a union &b |] = do
    ta <- typeOf a
    tb <- typeOf b
    case (ta, tb) of
        ([xMatch| [ia] := type.set.inner |], [xMatch| [ib] := type.set.inner |]) -> do
            if typeUnify ia ib
                then mostKnown ta tb
                else typeErrorIn p
        ([xMatch| [ia] := type.mset.inner |], [xMatch| [ib] := type.mset.inner |]) -> do
            if typeUnify ia ib
                then mostKnown ta tb
                else typeErrorIn p
        ([xMatch| [iaF] := type.function.innerFrom
                | [iaT] := type.function.innerTo
                |], [xMatch| [ibF] := type.function.innerFrom
                           | [ibT] := type.function.innerTo
                           |]) -> do
            let resF = typeUnify iaF ibF
            let resT = typeUnify iaT ibT
            if resF && resT
                then mostKnown ta tb
                else typeErrorIn p
        _ -> typeErrorIn p

typeOf p@[eMatch| &a - &b |] = do
    ta <- typeOf a
    tb <- typeOf b
    case (ta, tb) of
        ([xMatch| [] := type.int |], [xMatch| [] := type.int |]) -> return tyInt
        ([xMatch| [ia] := type.set.inner |], [xMatch| [ib] := type.set.inner |]) -> do
            if typeUnify ia ib
                then mostKnown ta tb
                else typeErrorIn p
        ([xMatch| [ia] := type.mset.inner |], [xMatch| [ib] := type.mset.inner |]) -> do
            if typeUnify ia ib
                then mostKnown ta tb
                else typeErrorIn p
        ([xMatch| [iaF] := type.function.innerFrom
                | [iaT] := type.function.innerTo
                |], [xMatch| [ibF] := type.function.innerFrom
                           | [ibT] := type.function.innerTo
                           |]) -> do
            let resF = typeUnify iaF ibF
            let resT = typeUnify iaT ibT
            if resF && resT
                then mostKnown ta tb
                else typeErrorIn p
        _ -> typeErrorIn p

typeOf p@[xMatch| [Prim (S operator)] := binOp.operator
                | [a] := binOp.left
                | [b] := binOp.right
                |] | operator `elem` T.words "subset subsetEq supset supsetEq" = do
    tya <- typeOf a
    tyb <- typeOf b
    case (tya, tyb) of
        ( [xMatch| [aInner] := type. set.inner |] , [xMatch| [bInner] := type. set.inner |] ) ->
            if typeUnify aInner bInner
                then return tyBool
                else typeErrorIn p
        ( [xMatch| [aInner] := type.mset.inner |] , [xMatch| [bInner] := type.mset.inner |] ) ->
            if typeUnify aInner bInner
                then return tyBool
                else typeErrorIn p
        _ -> typeErrorIn p

typeOf p@[xMatch| [Prim (S operator)] := binOp.operator
                | [a] := binOp.left
                | [b] := binOp.right
                |] | operator `elem` T.words "+ - * / % **" = do
    tya <- typeOf a
    tyb <- typeOf b
    case (tya, tyb) of
        ( [xMatch| [] := type.int |] , [xMatch| [] := type.int |] ) -> return tyInt
        _ -> typeErrorIn p

typeOf p@[xMatch| [Prim (S operator)] := binOp.operator
                | [a] := binOp.left
                | [b] := binOp.right
                |] | operator `elem` T.words "> >= < <=" = do
    tya <- typeOf a
    tyb <- typeOf b
    case (tya, tyb) of
        ( [xMatch| [] := type.int |] , [xMatch| [] := type.int |] ) -> return tyBool
        _ -> typeErrorIn p

typeOf p@[xMatch| [Prim (S operator)] := binOp.operator
                | [a] := binOp.left
                | [b] := binOp.right
                |] | operator `elem` T.words "/\\ \\/ => <=>" = do
    tya <- typeOf a
    tyb <- typeOf b
    case (tya, tyb) of
        ( [xMatch| [] := type.bool |] , [xMatch| [] := type.bool |] ) -> return tyBool
        _ -> typeErrorIn p

typeOf p@[eMatch| &a in &b |] = do
    tya <- typeOf a
    tyb <- typeOf b
    case innerTypeOf tyb of
        Nothing -> typeErrorIn p
        Just tybInner ->
            if typeUnify tya tybInner
                then return tyBool
                else typeErrorIn p

typeOf p@[eMatch| max(&a) |] = do
    ta <- typeOf a
    case ta of
        [xMatch| [] := type. set.inner.type.int |] -> return tyInt
        [xMatch| [] := type.mset.inner.type.int |] -> return tyInt
        _ -> typeErrorIn p

typeOf p@[eMatch| max(&a,&b) |] = do
    ta <- typeOf a
    tb <- typeOf b
    case (ta,tb) of
        ( [xMatch| [] := type.int |] , [xMatch| [] := type.int |] ) -> return tyInt
        _ -> typeErrorIn p

typeOf p@[eMatch| min(&a) |] = do
    ta <- typeOf a
    case ta of
        [xMatch| [] := type. set.inner.type.int |] -> return tyInt
        [xMatch| [] := type.mset.inner.type.int |] -> return tyInt
        _ -> typeErrorIn p

typeOf p@[eMatch| min(&a,&b) |] = do
    ta <- typeOf a
    tb <- typeOf b
    case (ta,tb) of
        ( [xMatch| [] := type.int |] , [xMatch| [] := type.int |] ) -> return tyInt
        _ -> typeErrorIn p

typeOf [xMatch| [i] := withLocals.actual
              | js  := withLocals.locals |] = mapM_ introduceStuff js >> typeOf i

typeOf p@[xMatch| [f] := functionApply.actual
                | [x] := functionApply.args
                |] = do
    tyF <- typeOf f
    tyX <- typeOf x
    case tyF of
        [xMatch| [fr] := type.function.innerFrom
               | [to] := type.function.innerTo
               |] | fr `typeUnify` tyX -> return to
        _ -> typeErrorIn p

typeOf p@[xMatch| [rel] := functionApply.actual
                | args  := functionApply.args
                |] = do
    tyRel  <- typeOf rel
    tyArgs <- mapM typeOf args
    case tyRel of
        [xMatch| tyRels := type.relation.inners |] -> do
            outTypes <- forM (zip3 tyRels args tyArgs) $ \ (relType, arg, argType) ->
                if arg == [eMake| _ |]
                    then return (Just relType)
                    else if relType `typeUnify` argType
                            then return Nothing
                            else typeErrorIn p
            return [xMake| type.relation.inners := (catMaybes outTypes) |]
        _ -> typeErrorIn p

typeOf p@[eMatch| preImage(&f,&x) |] = do
    tyF <- typeOf f
    tyX <- typeOf x
    case tyF of
        [xMatch| [fr] := type.function.innerFrom
               | [to] := type.function.innerTo
               |] | to `typeUnify` tyX -> return [xMake| type.set.inner := [fr] |]
        _ -> typeErrorIn p

typeOf p@[xMatch| [f] := operator.defined |] = do
    tyF <- typeOf f
    case tyF of
        [xMatch| [fr] := type.function.innerFrom
               |] -> return [xMake| type.set.inner := [fr] |]   
        _ -> typeErrorIn p

typeOf p@[xMatch| [f] := operator.range |] = do
    tyF <- typeOf f
    case tyF of
        [xMatch| [to] := type.function.innerTo
               |] -> return [xMake| type.set.inner := [to] |]
        _ -> typeErrorIn p

typeOf   [xMatch| [m] := operator.index.left
                | [ ] := operator.index.right.slicer
                |] = typeOf m
typeOf p@[xMatch| [m] := operator.index.left
                | [i] := operator.index.right
                |] = do
    tyM <- typeOf m
    tyI <- typeOf i
    case tyM of
        [xMatch| [ind] := type.matrix.index
               | [inn] := type.matrix.inner
               |] | ind `typeUnify` tyI -> return inn
        [xMatch| ts := type.tuple.inners |] -> do
            mint <- toInt i
            case mint of
                Just (int, _) | int >= 1 && int <= genericLength ts -> return $ ts `genericIndex` (int - 1)
                _ -> typeErrorIn p
        _ -> typeErrorIn p

typeOf p = typeErrorIn' p "default case"



innerTypeOf :: E -> Maybe E
innerTypeOf [xMatch| [ty] := type. set.inner |] = return ty
innerTypeOf [xMatch| [ty] := type.mset.inner |] = return ty
innerTypeOf _ = Nothing




tyBool :: E
tyBool = [xMake| type.bool := [] |]

tyInt :: E
tyInt = [xMake| type.int := [] |]

