{-# LANGUAGE DeriveGeneric, DeriveDataTypeable #-}
{-# LANGUAGE MultiParamTypeClasses, FlexibleContexts, FlexibleInstances #-}

module Conjure.Language.Ops where

-- conjure
import Conjure.Prelude
import Conjure.Bug
import Conjure.Language.Type
import Conjure.Language.TypeCheck
import Stuff.Pretty
import Language.E.Lexer
import Language.E.Data

-- aeson
import qualified Data.Aeson as JSON

-- pretty
import Text.PrettyPrint as Pr


class OperatorContainer x where
    injectOp :: Ops x -> x


data Ops x
    = MkOpPlus            (OpPlus x)
    | MkOpMinus           (OpMinus x)
    | MkOpTimes           (OpTimes x)
    | MkOpDiv             (OpDiv x)
    | MkOpMod             (OpMod x)
    | MkOpAbs             (OpAbs x)

    | MkOpEq              (OpEq x)
    | MkOpNeq             (OpNeq x)
    | MkOpLt              (OpLt x)
    | MkOpLeq             (OpLeq x)
    | MkOpGt              (OpGt x)
    | MkOpGeq             (OpGeq x)

    | MkOpLAnd            (OpLAnd x)
    | MkOpLOr             (OpLOr x)

    | MkOpIndexing        (OpIndexing x)
    | MkOpSlicing         (OpSlicing x)

    | MkOpFilter          (OpFilter x)
    | MkOpMapOverDomain   (OpMapOverDomain x)
    | MkOpMapInExpr       (OpMapInExpr x)
    | MkOpMapSubsetExpr   (OpMapSubsetExpr x)
    | MkOpMapSubsetEqExpr (OpMapSubsetEqExpr x)
    | MkOpFunctionImage   (OpFunctionImage x)

    | MkOpTrue            (OpTrue x)
    | MkOpToInt           (OpToInt x)

    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (Ops x)
instance Hashable  x => Hashable  (Ops x)
instance ToJSON    x => ToJSON    (Ops x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (Ops x) where parseJSON = JSON.genericParseJSON jsonOptions

instance TypeOf st (Ops x) where
    typeOf _ = return TypeAny

class BinaryOperator op where
    opLexeme :: proxy op -> Lexeme

-- | just the operator not the arguments
opPretty :: BinaryOperator op => proxy op -> Doc
opPretty = lexemeFace . opLexeme

opFixityPrec :: BinaryOperator op => proxy op -> (Fixity, Int)
opFixityPrec op =
    case [ (f,p) | (l,f,p) <- operators, l == opLexeme op ] of
        [x] -> x
        _ -> bug "opFixityPrec"

instance Pretty x => Pretty (Ops x) where
    prettyPrec prec (MkOpPlus  op@(OpPlus  a b)) = prettyPrecBinOp prec [op] a b
    prettyPrec prec (MkOpMinus op@(OpMinus a b)) = prettyPrecBinOp prec [op] a b
    prettyPrec prec (MkOpTimes op@(OpTimes a b)) = prettyPrecBinOp prec [op] a b
    prettyPrec prec (MkOpDiv   op@(OpDiv   a b)) = prettyPrecBinOp prec [op] a b
    prettyPrec prec (MkOpMod   op@(OpMod   a b)) = prettyPrecBinOp prec [op] a b
    prettyPrec _    (MkOpAbs      (OpAbs   a  )) = "|" <> pretty a <> "|"
    prettyPrec prec (MkOpEq    op@(OpEq    a b)) = prettyPrecBinOp prec [op] a b
    prettyPrec prec (MkOpNeq   op@(OpNeq   a b)) = prettyPrecBinOp prec [op] a b
    prettyPrec prec (MkOpLt    op@(OpLt    a b)) = prettyPrecBinOp prec [op] a b
    prettyPrec prec (MkOpLeq   op@(OpLeq   a b)) = prettyPrecBinOp prec [op] a b
    prettyPrec prec (MkOpGt    op@(OpGt    a b)) = prettyPrecBinOp prec [op] a b
    prettyPrec prec (MkOpGeq   op@(OpGeq   a b)) = prettyPrecBinOp prec [op] a b
    prettyPrec prec (MkOpLAnd  op@(OpLAnd  a b)) = prettyPrecBinOp prec [op] a b
    prettyPrec prec (MkOpLOr   op@(OpLOr   a b)) = prettyPrecBinOp prec [op] a b
    prettyPrec _ (MkOpIndexing (OpIndexing a b)) = pretty a <> "[" <> pretty b <> "]"
    prettyPrec _ (MkOpSlicing  (OpSlicing  a  )) = pretty a <> "[..]"
    prettyPrec _ (MkOpFilter          (OpFilter          a b)) = "filter"            <> prettyList Pr.parens "," [a,b]
    prettyPrec _ (MkOpMapOverDomain   (OpMapOverDomain   a b)) = "map_domain"        <> prettyList Pr.parens "," [a,b]
    prettyPrec _ (MkOpMapInExpr       (OpMapInExpr       a b)) = "map_in_expr"       <> prettyList Pr.parens "," [a,b]
    prettyPrec _ (MkOpMapSubsetExpr   (OpMapSubsetExpr   a b)) = "map_subset_expr"   <> prettyList Pr.parens "," [a,b]
    prettyPrec _ (MkOpMapSubsetEqExpr (OpMapSubsetEqExpr a b)) = "map_subsetEq_expr" <> prettyList Pr.parens "," [a,b]
    prettyPrec _ (MkOpFunctionImage   (OpFunctionImage   a b)) = "function_image"    <> prettyList Pr.parens "," (a:b)
    prettyPrec _ (MkOpTrue  (OpTrue xs)) = "true" <> prettyList Pr.parens "," xs
    prettyPrec _ (MkOpToInt (OpToInt a)) = "toInt" <> Pr.parens (pretty a)


prettyPrecBinOp :: (BinaryOperator op, Pretty x) => Int -> proxy op -> x -> x -> Doc
prettyPrecBinOp envPrec op a b =
    let
        (fixity, prec) = opFixityPrec op
    in
        case fixity of
            FLeft  -> parensIf (envPrec > prec) $ Pr.fsep [ prettyPrec  prec    a
                                                          , opPretty op
                                                          , prettyPrec (prec+1) b
                                                          ]
            FNone  -> parensIf (envPrec > prec) $ Pr.fsep [ prettyPrec (prec+1) a
                                                          , opPretty op
                                                          , prettyPrec (prec+1) b
                                                          ]
            FRight -> parensIf (envPrec > prec) $ Pr.fsep [ prettyPrec  prec    a
                                                          , opPretty op
                                                          , prettyPrec (prec+1) b
                                                          ]


data OpPlus x = OpPlus x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpPlus x)
instance Hashable  x => Hashable  (OpPlus x)
instance ToJSON    x => ToJSON    (OpPlus x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpPlus x) where parseJSON = JSON.genericParseJSON jsonOptions
opPlus :: OperatorContainer x => x -> x -> x
opPlus x y = injectOp (MkOpPlus (OpPlus x y))
instance BinaryOperator (OpPlus x) where
    opLexeme _ = L_Plus


data OpMinus x = OpMinus x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpMinus x)
instance Hashable  x => Hashable  (OpMinus x)
instance ToJSON    x => ToJSON    (OpMinus x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpMinus x) where parseJSON = JSON.genericParseJSON jsonOptions
opMinus :: OperatorContainer x => x -> x -> x
opMinus x y = injectOp (MkOpMinus (OpMinus x y))
instance BinaryOperator (OpMinus x) where
    opLexeme _ = L_Minus


data OpTimes x = OpTimes x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpTimes x)
instance Hashable  x => Hashable  (OpTimes x)
instance ToJSON    x => ToJSON    (OpTimes x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpTimes x) where parseJSON = JSON.genericParseJSON jsonOptions
opTimes :: OperatorContainer x => x -> x -> x
opTimes x y = injectOp (MkOpTimes (OpTimes x y))
instance BinaryOperator (OpTimes x) where
    opLexeme _ = L_Times


data OpDiv x = OpDiv x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpDiv x)
instance Hashable  x => Hashable  (OpDiv x)
instance ToJSON    x => ToJSON    (OpDiv x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpDiv x) where parseJSON = JSON.genericParseJSON jsonOptions
opDiv :: OperatorContainer x => x -> x -> x
opDiv x y = injectOp (MkOpDiv (OpDiv x y))
instance BinaryOperator (OpDiv x) where
    opLexeme _ = L_Div


data OpMod x = OpMod x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpMod x)
instance Hashable  x => Hashable  (OpMod x)
instance ToJSON    x => ToJSON    (OpMod x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpMod x) where parseJSON = JSON.genericParseJSON jsonOptions
opMod :: OperatorContainer x => x -> x -> x
opMod x y = injectOp (MkOpMod (OpMod x y))
instance BinaryOperator (OpMod x) where
    opLexeme _ = L_Mod


data OpAbs x = OpAbs x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpAbs x)
instance Hashable  x => Hashable  (OpAbs x)
instance ToJSON    x => ToJSON    (OpAbs x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpAbs x) where parseJSON = JSON.genericParseJSON jsonOptions
opAbs :: OperatorContainer x => x -> x
opAbs x = injectOp (MkOpAbs (OpAbs x))


data OpEq x = OpEq x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpEq x)
instance Hashable  x => Hashable  (OpEq x)
instance ToJSON    x => ToJSON    (OpEq x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpEq x) where parseJSON = JSON.genericParseJSON jsonOptions
opEq :: OperatorContainer x => x -> x -> x
opEq x y = injectOp (MkOpEq (OpEq x y))
instance BinaryOperator (OpEq x) where
    opLexeme _ = L_Eq


data OpNeq x = OpNeq x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpNeq x)
instance Hashable  x => Hashable  (OpNeq x)
instance ToJSON    x => ToJSON    (OpNeq x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpNeq x) where parseJSON = JSON.genericParseJSON jsonOptions
opNeq :: OperatorContainer x => x -> x -> x
opNeq x y = injectOp (MkOpNeq (OpNeq x y))
instance BinaryOperator (OpNeq x) where
    opLexeme _ = L_Neq


data OpLt x = OpLt x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpLt x)
instance Hashable  x => Hashable  (OpLt x)
instance ToJSON    x => ToJSON    (OpLt x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpLt x) where parseJSON = JSON.genericParseJSON jsonOptions
opLt :: OperatorContainer x => x -> x -> x
opLt x y = injectOp (MkOpLt (OpLt x y))
instance BinaryOperator (OpLt x) where
    opLexeme _ = L_Lt


data OpLeq x = OpLeq x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpLeq x)
instance Hashable  x => Hashable  (OpLeq x)
instance ToJSON    x => ToJSON    (OpLeq x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpLeq x) where parseJSON = JSON.genericParseJSON jsonOptions
opLeq :: OperatorContainer x => x -> x -> x
opLeq x y = injectOp (MkOpLeq (OpLeq x y))
instance BinaryOperator (OpLeq x) where
    opLexeme _ = L_Leq


data OpGt x = OpGt x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpGt x)
instance Hashable  x => Hashable  (OpGt x)
instance ToJSON    x => ToJSON    (OpGt x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpGt x) where parseJSON = JSON.genericParseJSON jsonOptions
opGt :: OperatorContainer x => x -> x -> x
opGt x y = injectOp (MkOpGt (OpGt x y))
instance BinaryOperator (OpGt x) where
    opLexeme _ = L_Gt


data OpGeq x = OpGeq x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpGeq x)
instance Hashable  x => Hashable  (OpGeq x)
instance ToJSON    x => ToJSON    (OpGeq x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpGeq x) where parseJSON = JSON.genericParseJSON jsonOptions
opGeq :: OperatorContainer x => x -> x -> x
opGeq x y = injectOp (MkOpGeq (OpGeq x y))
instance BinaryOperator (OpGeq x) where
    opLexeme _ = L_Geq


data OpLAnd x = OpLAnd x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpLAnd x)
instance Hashable  x => Hashable  (OpLAnd x)
instance ToJSON    x => ToJSON    (OpLAnd x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpLAnd x) where parseJSON = JSON.genericParseJSON jsonOptions
opLAnd :: OperatorContainer x => x -> x -> x
opLAnd x y = injectOp (MkOpLAnd (OpLAnd x y))
instance BinaryOperator (OpLAnd x) where
    opLexeme _ = L_And


data OpLOr x = OpLOr x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpLOr x)
instance Hashable  x => Hashable  (OpLOr x)
instance ToJSON    x => ToJSON    (OpLOr x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpLOr x) where parseJSON = JSON.genericParseJSON jsonOptions
opLOr :: OperatorContainer x => x -> x -> x
opLOr x y = injectOp (MkOpLOr (OpLOr x y))
instance BinaryOperator (OpLOr x) where
    opLexeme _ = L_Or


data OpIndexing x = OpIndexing x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpIndexing x)
instance Hashable  x => Hashable  (OpIndexing x)
instance ToJSON    x => ToJSON    (OpIndexing x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpIndexing x) where parseJSON = JSON.genericParseJSON jsonOptions
opIndexing :: OperatorContainer x => x -> x -> x
opIndexing x y = injectOp (MkOpIndexing (OpIndexing x y))


data OpSlicing x = OpSlicing x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpSlicing x)
instance Hashable  x => Hashable  (OpSlicing x)
instance ToJSON    x => ToJSON    (OpSlicing x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpSlicing x) where parseJSON = JSON.genericParseJSON jsonOptions
opSlicing :: OperatorContainer x => x -> x
opSlicing x = injectOp (MkOpSlicing (OpSlicing x))


data OpFilter x = OpFilter x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpFilter x)
instance Hashable  x => Hashable  (OpFilter x)
instance ToJSON    x => ToJSON    (OpFilter x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpFilter x) where parseJSON = JSON.genericParseJSON jsonOptions
opFilter :: OperatorContainer x => x -> x -> x
opFilter x y = injectOp (MkOpFilter (OpFilter x y))


data OpMapOverDomain x = OpMapOverDomain x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpMapOverDomain x)
instance Hashable  x => Hashable  (OpMapOverDomain x)
instance ToJSON    x => ToJSON    (OpMapOverDomain x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpMapOverDomain x) where parseJSON = JSON.genericParseJSON jsonOptions
opMapOverDomain :: OperatorContainer x => x -> x -> x
opMapOverDomain x y = injectOp (MkOpMapOverDomain (OpMapOverDomain x y))


data OpMapInExpr x = OpMapInExpr x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpMapInExpr x)
instance Hashable  x => Hashable  (OpMapInExpr x)
instance ToJSON    x => ToJSON    (OpMapInExpr x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpMapInExpr x) where parseJSON = JSON.genericParseJSON jsonOptions
opMapInExpr :: OperatorContainer x => x -> x -> x
opMapInExpr x y = injectOp (MkOpMapInExpr (OpMapInExpr x y))


data OpMapSubsetExpr x = OpMapSubsetExpr x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpMapSubsetExpr x)
instance Hashable  x => Hashable  (OpMapSubsetExpr x)
instance ToJSON    x => ToJSON    (OpMapSubsetExpr x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpMapSubsetExpr x) where parseJSON = JSON.genericParseJSON jsonOptions
opMapSubsetExpr :: OperatorContainer x => x -> x -> x
opMapSubsetExpr x y = injectOp (MkOpMapSubsetExpr (OpMapSubsetExpr x y))


data OpMapSubsetEqExpr x = OpMapSubsetEqExpr x x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpMapSubsetEqExpr x)
instance Hashable  x => Hashable  (OpMapSubsetEqExpr x)
instance ToJSON    x => ToJSON    (OpMapSubsetEqExpr x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpMapSubsetEqExpr x) where parseJSON = JSON.genericParseJSON jsonOptions
opMapSubsetEqExpr :: OperatorContainer x => x -> x -> x
opMapSubsetEqExpr x y = injectOp (MkOpMapSubsetEqExpr (OpMapSubsetEqExpr x y))


data OpFunctionImage x = OpFunctionImage x [x]
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpFunctionImage x)
instance Hashable  x => Hashable  (OpFunctionImage x)
instance ToJSON    x => ToJSON    (OpFunctionImage x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpFunctionImage x) where parseJSON = JSON.genericParseJSON jsonOptions
opFunctionImage :: OperatorContainer x => x -> [x] -> x
opFunctionImage x y = injectOp (MkOpFunctionImage (OpFunctionImage x y))


data OpTrue x = OpTrue [x]
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpTrue x)
instance Hashable  x => Hashable  (OpTrue x)
instance ToJSON    x => ToJSON    (OpTrue x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpTrue x) where parseJSON = JSON.genericParseJSON jsonOptions
opTrue :: OperatorContainer x => [x] -> x
opTrue xs = injectOp (MkOpTrue (OpTrue xs))


data OpToInt x = OpToInt x
    deriving (Eq, Ord, Show, Data, Typeable, Generic)
instance Serialize x => Serialize (OpToInt x)
instance Hashable  x => Hashable  (OpToInt x)
instance ToJSON    x => ToJSON    (OpToInt x) where toJSON = JSON.genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpToInt x) where parseJSON = JSON.genericParseJSON jsonOptions
opToInt :: OperatorContainer x => x -> x
opToInt x = injectOp (MkOpToInt (OpToInt x))


mkBinOp :: OperatorContainer x => Text -> x -> x -> x
mkBinOp op a b =
    case textToLexeme op of
        Nothing -> bug ("Unknown binary operator:" <+> pretty op)
        Just l  ->
            case l of
                L_Plus  -> injectOp $ MkOpPlus  $ OpPlus  a b
                L_Minus -> injectOp $ MkOpMinus $ OpMinus a b
                L_Times -> injectOp $ MkOpTimes $ OpTimes a b
                L_Div   -> injectOp $ MkOpDiv   $ OpDiv   a b
                L_Mod   -> injectOp $ MkOpMod   $ OpMod   a b
                L_Eq    -> injectOp $ MkOpEq    $ OpEq    a b
                L_Neq   -> injectOp $ MkOpNeq   $ OpNeq   a b
                L_Lt    -> injectOp $ MkOpLt    $ OpLt    a b
                L_Leq   -> injectOp $ MkOpLeq   $ OpLeq   a b
                L_Gt    -> injectOp $ MkOpGt    $ OpGt    a b
                L_Geq   -> injectOp $ MkOpGeq   $ OpGeq   a b
                _ -> bug ("Unknown lexeme for binary operator:" <+> pretty (show l))


mkOp :: OperatorContainer x => Text -> [x] -> x
mkOp op _xs =
    case textToLexeme op of
        Nothing -> bug ("Unknown operator:" <+> pretty op)
        Just l  ->
            case l of
                -- L_Plus  -> injectOp $ MkOpPlus  $ OpPlus a b
                -- L_Minus -> injectOp $ MkOpMinus $ OpMinus a b
                -- L_Times -> injectOp $ MkOpTimes $ OpTimes a b
                -- L_Div   -> injectOp $ MkOpDiv   $ OpDiv a b
                -- L_Mod   -> injectOp $ MkOpMod   $ OpMod a b
                _ -> bug ("Unknown lexeme for operator:" <+> pretty (show l))

