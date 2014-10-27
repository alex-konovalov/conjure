{-# LANGUAGE FlexibleContexts #-}

module Conjure.Language.Instantiate
    ( instantiateExpression
    , instantiateDomain
    ) where

-- conjure
import Conjure.Prelude
import Conjure.Bug
import Conjure.Language.Definition
import Conjure.Language.Pretty


instantiateExpression
    :: MonadFail m
    => [(Name, Expression)]
    -> Expression
    -> m Constant
instantiateExpression ctxt x = evalStateT (instantiateE x) ctxt


instantiateDomain
    :: ( MonadFail m
       , Show r
       )
    => [(Name, Expression)]
    -> Domain r Expression
    -> m (Domain r Constant)
instantiateDomain ctxt x = evalStateT (instantiateD x) ctxt


instantiateE
    :: ( MonadFail m
       , MonadState [(Name, Expression)] m
       )
    => Expression
    -> m Constant
instantiateE (Constant c) = return c
instantiateE (AbstractLiteral lit) = instantiateAbsLit lit
instantiateE (Reference name _) = do
    ctxt <- gets id
    case name `lookup` ctxt of
        Nothing -> fail $ vcat
            $ ("No value for:" <+> pretty name)
            : "Bindings in context:"
            : prettyContext ctxt
        Just x -> instantiateE x
instantiateE x = fail $ "instantiateE:" <+> pretty (show x)


instantiateAbsLit
    :: ( MonadFail m
       , MonadState [(Name, Expression)] m
       )
    => AbstractLiteral Expression
    -> m Constant
instantiateAbsLit (AbsLitTuple xs) = ConstantTuple <$> mapM instantiateE xs
instantiateAbsLit (AbsLitMatrix index vals) = ConstantMatrix <$> instantiateD index <*> mapM instantiateE vals
instantiateAbsLit (AbsLitSet vals) = ConstantSet <$> mapM instantiateE vals
instantiateAbsLit (AbsLitMSet vals) = ConstantMSet <$> mapM instantiateE vals
instantiateAbsLit (AbsLitFunction vals) = ConstantFunction <$> forM vals (\ (a,b) -> do a' <- instantiateE a
                                                                                        b' <- instantiateE b
                                                                                        return (a',b')
                                                                         )
instantiateAbsLit (AbsLitRelation vals) = ConstantRelation <$> mapM (mapM instantiateE) vals
instantiateAbsLit (AbsLitPartition vals) = ConstantPartition <$> mapM (mapM instantiateE) vals


instantiateD
    :: ( MonadFail m
       , MonadState [(Name, Expression)] m
       , Show r
       )
    => Domain r Expression
    -> m (Domain r Constant)
instantiateD DomainBool = return DomainBool
instantiateD (DomainInt ranges) = DomainInt <$> mapM instantiateR ranges
instantiateD (DomainEnum nm rs) = return (DomainEnum nm rs)
instantiateD (DomainUnnamed nm) = return (DomainUnnamed nm)
instantiateD (DomainTuple inners) = DomainTuple <$> mapM instantiateD inners
instantiateD (DomainMatrix index inner) = DomainMatrix <$> instantiateD index <*> instantiateD inner
instantiateD (DomainSet       r attrs inner) = DomainSet r <$> instantiateSetAttr attrs <*> instantiateD inner
instantiateD (DomainMSet      r attrs inner) = DomainMSet r <$> instantiateDAs attrs <*> instantiateD inner
instantiateD (DomainFunction  r attrs innerFr innerTo) = DomainFunction r <$> instantiateDAs attrs <*> instantiateD innerFr <*> instantiateD innerTo
instantiateD (DomainRelation  r attrs inners) = DomainRelation r <$> instantiateDAs attrs <*> mapM instantiateD inners
instantiateD (DomainPartition r attrs inner) = DomainPartition r <$> instantiateDAs attrs <*> instantiateD inner
instantiateD (DomainOp {}) = bug "instantiateD DomainOp"
instantiateD (DomainHack x) = DomainHack <$> instantiateE x


instantiateSetAttr
    :: ( MonadFail m
       , MonadState [(Name, Expression)] m
       )
    => SetAttr Expression
    -> m (SetAttr Constant)
instantiateSetAttr SetAttrNone = return SetAttrNone
instantiateSetAttr (SetAttrSize x) = SetAttrSize <$> instantiateE x
instantiateSetAttr (SetAttrMinSize x) = SetAttrMinSize <$> instantiateE x
instantiateSetAttr (SetAttrMaxSize x) = SetAttrMaxSize <$> instantiateE x
instantiateSetAttr (SetAttrMinMaxSize x y) = SetAttrMinMaxSize <$> instantiateE x <*> instantiateE y


instantiateDAs
    :: ( MonadFail m
       , MonadState [(Name, Expression)] m
       )
    => DomainAttributes Expression
    -> m (DomainAttributes Constant)
instantiateDAs (DomainAttributes xs) = DomainAttributes <$> mapM instantiateDA xs


instantiateDA
    :: ( MonadFail m
       , MonadState [(Name, Expression)] m
       )
    => DomainAttribute Expression
    -> m (DomainAttribute Constant)
instantiateDA (DAName n) = return (DAName n)
instantiateDA (DANameValue n x) = DANameValue n <$> instantiateE x
instantiateDA DADotDot = return DADotDot


instantiateR
    :: ( MonadFail m
       , MonadState [(Name, Expression)] m
       )
    => Range Expression
    -> m (Range Constant)
instantiateR RangeOpen = return RangeOpen
instantiateR (RangeSingle x) = RangeSingle <$> instantiateE x
instantiateR (RangeLowerBounded x) = RangeLowerBounded <$> instantiateE x
instantiateR (RangeUpperBounded x) = RangeUpperBounded <$> instantiateE x
instantiateR (RangeBounded x y) = RangeBounded <$> instantiateE x <*> instantiateE y

