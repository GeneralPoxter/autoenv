{-|
Module      : AutoEnv
Description : Explicit substitutions
Stability   : experimental


-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use camelCase" #-}
module AutoEnv where

import Prelude hiding (head,tail)
import Data.Type.Equality

import Lib
import Data.Kind
import qualified Data.List as List
import Vec (Vec(..))
import qualified Vec

import Unsafe.Coerce(unsafeCoerce)

-- | An environment (or explicit substitution) that map
-- indices bounded by `m`, to values of type `v n`
-- For now, we represent this directly as a function, 
-- but we might want to change that. So we wrap it in 
-- a newtype to hide the representation.
newtype Env v m n = Env { applyEnv :: Fin m -> v n }

-- | Well-scoped types that can be the range of 
-- an environment. This should generally be the `Var`
-- constructor from the syntax.
class SubstVar (v :: Nat -> Type) where
    var    :: Fin n -> v n

-- | Apply the environment throughout a term of 
-- type `c n`, replacing variables with values 
-- of type `v m`
class SubstVar v => Subst v c where
    applyE :: Env v n m -> c n -> c m


----------------------------------------------
-- operations on environments/substitutions
----------------------------------------------

-- | The empty environment (zero domain)
zeroE :: Env v Z n
zeroE = Env $ \case

-- | A singleton environment (single index domain)
-- maps that single variable to `v n`
oneE :: v n -> Env v (S Z) n
oneE v = Env $ const v

-- | an environment that maps index 0 to v and leaves 
-- all other indices alone. Unlike oneE above, the 
-- domain of the environment must match the number of 
-- variables in the range.
singleton :: SubstVar v => v n -> Env v n n
singleton v = Env $ \ case FZ -> v ; FS y -> var (FS y)

-- | identity environment, any size
idE :: SubstVar v => Env v n n
idE = Env var

-- | composition: do f then g
(.>>) :: Subst v v => Env v p n -> Env v n m -> Env v p m
f .>> g = Env $ applyE g . applyEnv f

-- | `cons` -- extend an environment with a new mapping 
-- for index '0'. All existing mappings are shifted over.
(.:) :: SubstVar v => v m -> Env v n m -> Env v (S n) m
v .: f = Env $ \ case FZ -> v ; (FS x) -> applyEnv f x 

-- | append two environments
-- The `SNatI` constraint is a runtime witness for the length
-- of the domain of the first environment. By using a class
-- constraint, this can be an infix operation. 
(.++) :: (SNatI p, SubstVar v) => 
    Env v p n -> Env v m n -> Env v (Plus p m) n
(.++) = appendE snat

    
-- | append two environments: explicit length `SNat p` required
-- for the domain of the first list
appendE :: SubstVar v =>
        SNat p -> Env v p n -> Env v m n -> Env v (Plus p m) n
appendE SZ e1 e2 = e2 
appendE (SS p1) e1 e2 = head e1 .: appendE p1 (tail e1) e2
      
-- | inverse of `cons` -- remove the first mapping
tail :: SubstVar v => Env v (S n) m -> Env v n m
tail f = Env (applyEnv f . FS )

-- | access value at index 0
head :: SubstVar v => Env v (S n) m -> v m
head f = applyEnv f FZ

-- | increment all free variables by 1
shift1E :: SubstVar v => Env v n (S n)
shift1E = Env (var . FS)

-- | increment all free variables by m
shiftNE :: SubstVar v => SNat m -> Env v n (Plus m n)
shiftNE m = Env (var . shiftN m)

-- | increment all free variables by m, but in the middle
shiftRE :: forall v n1 n2 n. SubstVar v => SNat n2 -> 
    Env v (Plus n1 n) (Plus (Plus n1 n2) n)
shiftRE n2 = Env (var . shiftR @n1 @n2 @n n2)

-- | increment all free variables by m, but at the top
shiftLE :: forall v n1 n2 n. SubstVar v => SNat n1 -> 
    Env v (Plus n2 n) (Plus (Plus n1 n2) n)
shiftLE n1 = Env (var . shiftL @n1 @n2 @n n1)

-- | weaken variables by 1
-- makes their bound bigger but does not change any of their indices
weakenOneE :: SubstVar v => Env v n (S n)
weakenOneE = Env (var . weaken1Fin)

weakenE' :: forall m v n. (SubstVar v) => SNat m -> Env v n (Plus m n)
weakenE' sm = Env (var . weakenFin sm)

----------------------------------------------------------------
-- Single binders
----------------------------------------------------------------
-- | Type for a single binders
-- includes an delayed substitution plus a term with an 
-- extra free variable for the binder
-- n is the number of free variables in the term
data Bind v c (n :: Nat) where
    Bind :: Env v m n -> c (S m) -> Bind v c n

-- | The substitution operation composes the explicit 
-- substitution with the one stored at the binder
instance Subst v v => Subst v (Bind v c) where
    applyE :: Subst v v => Env v n m -> Bind v c n -> Bind v c m
    applyE env1 (Bind env2 m) = Bind (env2 .>> env1) m

-- | create a single binder
bind :: Subst v c => c (S n) -> Bind v c n
bind = Bind idE

-- | instantiate a binder with a term
instantiate :: (Subst v c) => Bind v c n -> v n -> c n
instantiate b v = unbindWith b (\ r e -> applyE (v .: r) e)

-- | apply an environment-parameterized function while
-- instantiating
instantiateWith :: (SubstVar v) =>
         Bind v c n -> v n -> 
         (forall m n. Env v m n -> c m -> c n) ->
         c n
instantiateWith b v f = unbindWith b (\ r e -> f ( v .: r) e)


-- | modify an environment so that it can go under 
-- a binder
up :: Subst v v => Env v m n -> Env v (S m) (S n)
up e = var FZ .: (e .>> shift1E)

-- | access the body of the binder  (inverse of bind)
unbind :: forall v c n. (Subst v v, Subst v c) => Bind v c n -> c (S n)
unbind (Bind r t) = applyE (up r) t

-- | unbind a binder and apply the function to the argument and subterm
unbindWith :: (SubstVar v) => 
    Bind v c n -> 
    (forall m. Env v m n -> c (S m) -> d) ->
    d
unbindWith (Bind r t) f = f r t

-- | apply an environment-parameterized function & environment 
-- underneath a binder
applyUnder :: (Subst v v, Subst v c) =>
        (forall m n. Env v m n -> c m -> c n) -> Env v n1 n2 ->
        Bind v c n1 -> Bind v c n2
applyUnder f r2 (Bind r1 t) = 
    bind (f (up (r1 .>> r2)) t)

-- TODO: this implementation of strengthening for binders is rather inefficient
-- maybe there is a better way to do it???
instance (SubstVar v, Subst v v, Subst v c, Strengthen c) => Strengthen (Bind v c) where
    strengthen' (m :: SNat m) (n :: SNat n) b = 
        case axiom @m @n of
          Refl -> bind <$> strengthen' m (SS n) (unbind b)

----------------------------------------------------------
-- Patterns
----------------------------------------------------------


class Sized (t :: Nat -> Type) where
    type Size t :: Nat
    size :: t n -> SNat (Size t)



----------------------------------------------------------
-- Pattern binding (N-ary binding)
----------------------------------------------------------

-- | A pattern is any type that can be made an instance of the 
-- `Sized` type class. 
-- The `PatBind` type generalizes the definitions above 
-- to bind (Size p) variables. 
-- Patterns can also include free occurrences of variables so 
-- they are also indexed by a scope level.
-- As in `Bind` above, this data structure includes a delayed 
-- substitution for the variables in the body of the binder.
data PatBind v c (pat :: Nat -> Type) (n :: Nat) where
    PatBind :: pat n -> Env v m n -> c (Plus (Size pat) m) 
            -> PatBind v c pat n

-- | Create a `PatBind` with an identity substitution.
patBind :: forall v c pat n . (Sized pat, Subst v c) => 
   pat n -> c (Plus (Size pat) n) -> PatBind v c pat n
patBind pat = PatBind pat idE

-- | Access the pattern of a pattern binding
getPat :: PatBind v c pat n -> pat n
getPat (PatBind pat env t) = pat

-- | Access the body of a pattern binding.
-- The pattern type determines the number of variables
-- bound in the pattern
unPatBind :: forall v c pat n.
    (Sized pat, Subst v v, Subst v c) => PatBind v c pat n 
    -> c (Plus (Size pat) n)
unPatBind (PatBind (pat :: pat n) (env :: Env v m n) t) = 
    applyE @v @c @(Plus (Size pat) m) (upN (size pat) env) t

-- | Shift an environment by size `p` 
upN :: (Subst v v) => 
        SNat p -> Env v m n -> Env v (Plus p m) (Plus p n)
upN SZ = id
upN (SS n) = \ e -> var FZ .: (upN n e .>> shift1E)

-- | Apply a function to the pattern, suspended environment and body
-- in a pattern binding
unPatBindWith ::  (Sized pat, SubstVar v) => 
    (forall m. pat n -> Env v m n -> c (Plus (Size pat) m) -> d) -> PatBind v c pat n -> d
unPatBindWith f (PatBind pat r t) = f pat r t

instantiatePat :: forall v c pat n. (Sized pat, Subst v c) => 
   PatBind v c pat n -> Env v (Size pat) n -> c n
instantiatePat b e = unPatBindWith 
    (\ p r t -> withSNat (size p) $ applyE (e .++ r) t) b

applyPatUnder :: (forall n. Sized pat, Subst v v, Subst v c, Subst v pat) => 
   (forall m n. Env v m n -> c m -> c n) -> Env v n1 n2 ->
        PatBind v c pat n1 -> PatBind v c pat n2
applyPatUnder f r2 (PatBind p r1 t) = 
    PatBind p' idE (f r' t) where
        r' = upN (size p') (r1 .>> r2)
        p' = applyE r2 p

instantiatePatWith :: (Sized pat, SubstVar v) =>
         (forall m n. Env v m n -> c m -> c n) ->
         PatBind v c pat n -> Env v (Size pat) n -> c n
instantiatePatWith f b v = 
    unPatBindWith (\ p r e -> withSNat (size p) $ f (v .++ r) e) b

instance (Subst v p, Subst v v) => Subst v (PatBind v c p) where
    applyE env1 (PatBind p env2 m) = 
        PatBind (applyE env1 p) (env2 .>> env1) m

instance (Sized p, SubstVar v, Subst v v, Subst v c, Strengthen c, Strengthen p) => 
    Strengthen (PatBind v c p) where

    strengthen' (m :: SNat m) (n :: SNat n) b = 
        case axiomM @m @(Size p) @n of
          Refl -> 
            case strengthen' m n (getPat b) of 
                Just p' -> patBind p' <$> strengthen' m (sPlus (size (getPat b)) n) (unPatBind b) 
                Nothing -> Nothing


----------------------------------------------------------------
-- N-ary and double binder
----------------------------------------------------------------

-- A double binder is isomorphic to a pattern binding with 
-- "SNat 2" as the pattern.

data PatN p n where
    PatN :: SNat p -> PatN p n
instance Sized (PatN p) where
    type Size (PatN p) = p
    size (PatN sn) = sn
instance (SubstVar v) => Subst v (PatN p) where
    applyE r (PatN sn) = PatN sn
instance Strengthen (PatN p) where
    strengthen' m n (PatN sn) = Just (PatN sn)

type Bind2 v c n = PatBind v c (PatN N2) n

bind2 :: Subst v c => c (S (S n)) -> Bind2 v c n
bind2 = patBind (PatN s2)

unbind2 :: forall v c n. (Subst v v, Subst v c) => Bind2 v c n -> c (S (S n))
unbind2 = unPatBind

unbind2With :: (SubstVar v) => 
    (forall m. Env v m n -> c (S (S m)) -> d) ->
    Bind2 v c n -> d
unbind2With f = unPatBindWith (const f)

instantiate2 :: (Subst v c) => Bind2 v c n -> v n -> v n -> c n
instantiate2 b v1 v2 = instantiatePat b (v1 .: (v2 .: zeroE))

instantiate2With :: (SubstVar v) =>
         (forall m n. Env v m n -> c m -> c n) ->
         Bind2 v c n -> v n -> v n -> c n
instantiate2With f b v1 v2 = 
    unbind2With (\ r e -> f ( v1 .: (v2 .: r)) e) b

----------------------------------------------------------------
-- For dependently-typed languages

-- This is not weakening --- it increments all variables by one
shiftC :: forall v c n. Subst v c => c n -> c (S n)
shiftC = applyE @v shift1E

type Ctx v n = Env v n n

shiftCtx :: Subst v v => Env v n n -> Env v n (S n)
shiftCtx g = g .>> shift1E

(+++) :: forall v n. Subst v v => Ctx v n -> v n -> Ctx v (S n)
g +++ a = shiftC @v @v a .: shiftCtx g 

----------------------------------------------------------------
toList :: SNatI n => Env v n m -> [v m]
toList r = map (applyEnv r) (enumFin snat)

instance (SNatI n, Show (v m)) => Show (Env v n m) where
    show x = show (toList x)
