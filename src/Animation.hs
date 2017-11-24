{-# LANGUAGE NoImplicitPrelude #-}

module Animation
    ( Animation(..)
    , mkAnimation
    , mkAnimationTree
    , renderAnimation
    -- | animations
    , animatedNumber
    ) where


import           Imajuscule.Prelude

import           Data.List( length )
import           Data.Maybe( fromMaybe )

import           Control.Exception( assert )

import           Geo( Coords
                    , polyExtremities )


data Animation = Animation {
    _animationRender :: !(Animation  -> IO (Maybe Animation))
}

mkAnimation :: (Animation  -> IO (Maybe Animation))
            -> Animation
mkAnimation = Animation

-- \ This datastructure is used to keep a state of the animation progress, not globally,
--   but locally on each animation point. It is also recursive, so that we can sequence
--   multiple animations.
data Tree = Tree {
    _treeRoot :: !Coords
    -- ^ where the animation begins
  , _treeBranches :: !(Maybe [Coords])
    -- ^ There is one element in the list per animation point.
}

mkAnimationTree :: Coords -> Tree
mkAnimationTree c = Tree c Nothing

combine :: [Coords]
        -> [Coords]
        -> [Coords]
combine points uncheckedPreviousState =
  let previousState = assert (length points == length uncheckedPreviousState) uncheckedPreviousState
  in zipWith combinePoints points previousState

combinePoints :: Coords
              -> Coords
              -> Coords
combinePoints point _ = point

applyAnimation :: (Coords -> [Coords])

               -> Tree
               -> Tree
applyAnimation animation (Tree root branches) =
  let points = animation root
      previousState = fromMaybe (replicate (length points) root) branches
      -- if previousState contains only Left(s), the animation does not need to be computed.
      -- I wonder if lazyness takes care of that or not?
      newBranches = combine points previousState
  in Tree root $ Just newBranches

animateNumberPure :: Int -> Coords -> [Coords]
animateNumberPure nSides _ =
  let startAngle = if odd nSides then pi else pi/4.0
  in polyExtremities startAngle -- replacing startAngle by pi or (pi/4.0) fixes the problem


--------------------------------------------------------------------------------
-- IO
--------------------------------------------------------------------------------

renderAnimation :: Animation -> IO ()
renderAnimation a@(Animation render) =
    void( render a )

setRender :: Animation
          -> (Animation  -> IO (Maybe Animation))
          -> Animation
setRender (Animation _) = Animation

animatedNumber :: Int -> Tree -> Animation  -> IO (Maybe Animation)
animatedNumber n =
  animate' (mkAnimator animateNumberPure animatedNumber n)

data Animator a = Animator {
    _animatorPure :: !(Tree -> Tree)
  , _animatorIO   :: !(Tree -> Animation  -> IO (Maybe Animation))
}

mkAnimator :: (t -> Coords -> [Coords])
           -> (t
               -> Tree
               -> Animation
               -> IO (Maybe Animation))
           -> t
           -> Animator a
mkAnimator pure_ io_ params = Animator (applyAnimation (pure_ params)) (io_ params)

-- when inlining this function the problem disappears
--{-# INLINE animate' #-}
animate' :: Animator a -> Tree -> Animation  -> IO (Maybe Animation)
animate' (Animator pure_ io_) = animate pure_ io_

animate :: (Tree -> Tree)
        -- ^ the pure animation function
        -> (Tree -> Animation  -> IO (Maybe Animation))
        -- ^ the IO animation function
        -> Tree
        -> Animation
        -> IO (Maybe Animation)
animate pureAnim ioAnim state a@(Animation _) = do
  let newState = pureAnim state
  return $ Just (setRender a $ ioAnim newState)
