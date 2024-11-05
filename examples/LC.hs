-- The untyped lambda calculus
-- Evaluation and normalization
module LC where

import Lib
import Subst
import Vec qualified

{-

This is a simple representation of well-scoped lambda calculus terms.
The natural number index `n` is the scoping level -- a bound on the number
of free variables that can appear in the term. If `n` is 0, then the
term must be closed.

The `Var` constructor of this datatype takes an index that must
be strictly less than this bound. The type `Fin (S n)` has `n` different
elements.

The `Lam` constructor binds a variable. The library exports the type
`Bind1` that introduces a binder. The type arguments state that the
binder is for expression variables, inside an expression term, that may
have `n` free variables.

-}

data Exp (n :: Nat) where
  Var :: Fin n -> Exp n
  Lam :: Bind1 Exp Exp n -> Exp n
  App :: Exp n -> Exp n -> Exp n

----------------------------------------------

{-
To work with this library, we need only create two type class instances.
First, we have to tell the library how to construct variables in the expression
type. This class is necessary to construct an indentity substitution---one that
maps each variable to itself.
-}

instance SubstVar Exp where
  var :: Fin n -> Exp n
  var = Var

{- We also need an operation `applyE` that applies an explicit substitution
   to an expression.  The type `Env Exp n m` is the type of an
   "environment" or "explicit substitution". This data structure
   is a substitution with domain `Fin n` to terms of type `Exp m`.

   The implementation of this operation applies the environment to
   variable index in the variable case. All other cases follow
   via recursion.
 -}
instance Subst Exp Exp where
  applyE :: Env Exp n m -> Exp n -> Exp m
  applyE r (Var x) = applyEnv r x
  applyE r (Lam b) = Lam (applyE r b)
  applyE r (App e1 e2) = App (applyE r e1) (applyE r e2)

----------------------------------------------
-- Examples

-- The identity function "λ x. x". With de Bruijn indices
-- we write it as "λ. 0"
t0 :: Exp Z
t0 = Lam (bind1 (Var f0))

-- A larger term "λ x. λy. x (λ z. z z)"
-- λ. λ. 1 (λ. 0 0)
t1 :: Exp Z
t1 =
  Lam
    ( bind1
        ( Lam
            ( bind1
                ( Var f1
                    `App` ( Lam (bind1 (Var f0 `App` Var f0))
                          )
                )
            )
        )
    )

-- To show lambda terms, we can write a simple recursive instance of
-- Haskell's `Show` type class. In the case of a binder, we use the `unbind`
-- operation to access the body of the lambda expression.

-- >>> t0
-- λ. 0

-- >>> t1
-- λ. λ. 1 (λ. 0 0)

instance Show (Exp n) where
  showsPrec :: Int -> Exp n -> String -> String
  showsPrec _ (Var x) = shows (toInt x)
  showsPrec d (App e1 e2) =
    showParen (d > 0) $
      showsPrec 11 e1
        . showString " "
        . showsPrec 11 e2
  showsPrec d (Lam b) =
    showParen (d > 10) $
      showString "λ. "
        . shows (unbind b)

-- To compare binders, we only need to `unbind` them
instance (Eq (Exp n)) => Eq (Bind1 Exp Exp n) where
  b1 == b2 = unbind b1 == unbind b2

-- With the instance above the derivable equality instance
-- is alpha-equivalence
deriving instance (Eq (Exp n))

--------------------------------------------------------

{- We can write the usual operations for evaluating
   lambda terms to values -}

-- big-step evaluation

-- >>> eval t1
-- λ. λ. 1 (λ. 0 0)

-- >>> eval (t1 `App` t0)
-- λ. λ. 0 (λ. 0 0)

{- Breakdown of eval (t1 `App` t0) for my own reference -}

e3 :: Exp (S (S (S Z)))
e3 = Var f0 `App` Var f0

b3 :: Bind1 Exp Exp (S (S Z))
b3 = bind1 e3

e2 :: Exp (S (S Z))
e2 = Var f1 `App` Lam b3

b2 :: Bind1 Exp Exp (S Z)
b2 = bind1 e2

e1 :: Exp (S Z)
e1 = Lam b2

b1 :: Bind1 Exp Exp Z
b1 = bind1 e1

b0 :: Bind1 Exp Exp Z
b0 = bind1 (Var f0)

{- Beta reduction by substituting x for λx.x in the body of t1 -}

-- >>> instantiate b1 t0
-- λ. (λ. 0) (λ. 0 0)

-- >>> applyE (t0 .: idE) e1
-- λ. (λ. 0) (λ. 0 0)

-- >>> Lam (applyE (t0 .: idE) b2)
-- λ. (λ. 0) (λ. 0 0)

-- >>> Lam (Bind1 (idE .>> (t0 .: idE)) e2)
-- λ. (λ. 0) (λ. 0 0)

{- Evaluation stops here. Rest comes from unbinding / showing the result. -}

-- >>> applyE (up (idE .>> (t0 .: idE))) e2
-- (λ. 0) (λ. 0 0)

{- Left side of `App` -}

-- >>> applyE (up (idE .>> (t0 .: idE))) (Var f1)
-- λ. 0

{- Interesting:
    `cons` (.:) in `up` shifts the `Var` index from f1 to f0
    `shift` accordingly shifts any output `Var` indices
      (after performing substitution) up by 1 index b/c
      we are now in the scope of a new lambda
-}
-- >>> applyEnv ((idE .>> (t0 .: idE)) .>> shift) f0
-- λ. 0

-- >>> applyEnv (idE .>> (t0 .: idE)) f0
-- λ. 0

-- >>> applyEnv (t0 .: idE) f0
-- λ. 0

-- >>> applyE (shift :: Env Exp Z (S Z)) t0
-- λ. 0

-- >>> Lam (Bind1 (idE .>> shift) (Var f0))
-- λ. 0

{- Note that because bound environments are not shifted until unbinding,
   bound variables within the exp t0 are protected from the `shift`
   due to the usage of `up` during Lam expression unbinding. -}

{- Right side of `App` -}
-- >>> applyE (up (idE .>> (t0 .: idE))) (Lam b3)
-- λ. 0 0

-- >>> Lam (Bind1 (idE .>> up (idE .>> (t0 .: idE))) e3)
-- λ. 0 0

{- Unbinds recursively by calling `show` in the `Lam` case -}

-- >>> applyE (up (idE .>> up (idE .>> (t0 .: idE)))) e3
-- 0 0

-- >>> applyE (up (idE .>> up (idE .>> (t0 .: idE)))) (Var f0)
-- 0

eval :: Exp n -> Exp n
eval (Var x) = Var x
eval (Lam b) = Lam b
eval (App e1 e2) =
  let v = eval e2
   in case eval e1 of
        Lam b -> eval (instantiate b v)
        t -> App t v

-- small-step evaluation

-- >>> step (t1 `App` t0)
-- Just (λ. λ. 0 (λ. 0 0))

step :: Exp n -> Maybe (Exp n)
step (Var x) = Nothing
step (Lam b) = Nothing
step (App (Lam b) e2) = Just (instantiate b e2)
step (App e1 e2)
  | Just e1' <- step e1 = Just (App e1' e2)
  | Just e2' <- step e2 = Just (App e1 e2')
  | otherwise = Nothing

eval' :: Exp n -> Exp n
eval' e
  | Just e' <- step e = eval' e'
  | otherwise = e

-- full normalization
-- to normalize under a lambda expression, we must first unbind
-- it and then rebind it when finished

-- >>> nf t1
-- λ. λ. 1 (λ. 0 0)

-- >>> nf (t1 `App` t0)
-- λ. (λ. 0) (λ. 0 0)

nf :: Exp n -> Exp n
nf (Var x) = Var x
nf (Lam b) = Lam (bind1 (nf (unbind b)))
nf (App e1 e2) =
  case nf e1 of
    Lam b -> instantiate b (nf e2)
    t -> App t (nf e2)

--------------------------------------------------------
-- We can also write functions that manipulate the
-- environment explicitly. These operations are equivalent
-- to the definitions above, but they provide access to the
-- suspended substitution during the traversal of the term.

-- >>> evalEnv idE t1
-- λ. λ. 1 (λ. 0 0)

-- Below, if n is 0, then this function acts like an
-- "environment-based" bigstep evaluator. The result of
-- evaluating a lambda expression is a closure --- the body
-- of the lambda paired with its environment. That is exactly
-- what the implementation of bind does.

-- In the case of beta-reduction, the `unBindWith` operation
-- applies its argument to the environment and subterm in the
-- closure. In other words, this function calls `evalEnv`
-- recursively with the saved environment and body of the lambda term.

evalEnv :: Env Exp m n -> Exp m -> Exp n
evalEnv r (Var x) = applyEnv r x
evalEnv r (Lam b) = applyE r (Lam b)
evalEnv r (App e1 e2) =
  let v = evalEnv r e2
   in case evalEnv r e1 of
        Lam b ->
          unbindWith (\r' e' -> evalEnv (v .: r') e') b
        t -> App t v

-- To normalize under the binder, the `applyWith` function
-- takes care of the necessary environment manipulation. It
-- composes the given environment r with the environment stored
-- in the binder and also shifts them for the recursive call.
--
-- In the beta-reduction case, we could use `unbindWith` as above
-- but the `instantiateWith` function already captures exactly
-- this pattern.
nfEnv :: Env Exp m n -> Exp m -> Exp n
nfEnv r (Var x) = applyEnv r x
nfEnv r (Lam b) = Lam (applyWith nfEnv r b)
nfEnv r (App e1 e2) =
  let n = nfEnv r e1
   in case nfEnv r e1 of
        Lam b -> instantiateWith nfEnv b n
        t -> App t (nfEnv r e2)

----------------------------------------------------------------
