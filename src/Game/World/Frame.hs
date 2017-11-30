{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE LambdaCase #-}

module Game.World.Frame
    ( renderWorldFrame
    , FrameAnimation(..)
    , mkFrameAnimation
    , maxNumberOfSteps
    ) where

import           Imajuscule.Prelude

import           Animation.Types

import           Data.List( mapAccumL, zip )

import           Color

import           Game.World.Size

import           Geo.Discrete hiding( move )

import           Render
import           Render.Console

import           Timing

data FrameAnimation = FrameAnimation {
    _frameAnimationPrevSize :: !WorldSize
  , _frameAnimationStart :: !UTCTime
  , _frameAnimationEase :: !(Float -> Float)
  , _frameAnimationNSteps :: !Int -- in number of frames
  , _frameAnimationProgress :: !Iteration
  , _frameAnimationDeadline :: !(Maybe KeyTime)
}

mkFrameAnimation :: WorldSize -- ^ previous world size
                 -> UTCTime -- ^ time at which the animation starts
                 -> (Float -> Float) -- inverse ease function
                 -> Int -- ^ number of steps
                 -> FrameAnimation
mkFrameAnimation prev t ease nsteps =
  FrameAnimation prev t ease nsteps (Iteration (Speed 1, startFrame)) (Just $ KeyTime t)
 where
  startFrame = Frame (-1)

countWorldFrameChars :: WorldSize -> Int
countWorldFrameChars s =
  2 * countWorlFrameHorizontal s + 2 * countWorlFrameVertical s

countWorlFrameHorizontal :: WorldSize -> Int
countWorlFrameHorizontal (WorldSize (Coords _ (Col cs))) =
  cs + 2

countWorlFrameVertical :: WorldSize -> Int
countWorlFrameVertical (WorldSize (Coords (Row rs) _)) =
  rs

renderPartialWorldFrame :: WorldSize -> (RenderState, Int, Int) -> IO ()
renderPartialWorldFrame sz r =
  renderUpperWall sz r
    >>= renderRightWall sz
    >>= renderLowerWall sz
    >>= renderLeftWall sz
    >> return ()

renderRightWall :: WorldSize -> (RenderState, Int, Int) -> IO (RenderState, Int, Int)
renderRightWall sz (upperRight, from, to) = do
  let countMax = countWorlFrameVertical sz
      (actualFrom, actualTo) = actualRange countMax (from, to)
      countChars = 1 + actualTo - actualFrom
      rightWallCoords = map (\n -> move n Down upperRight) [actualFrom..actualTo]
      nextR = move countMax Down upperRight
  mapM_ (renderChar_ '|') rightWallCoords
  if countChars <= 0
    then
      return (nextR, from - countMax, to - countMax)
    else
      return (nextR, from + countChars - countMax, to - countMax)

renderLeftWall :: WorldSize -> (RenderState, Int, Int) -> IO (RenderState, Int, Int)
renderLeftWall sz (lowerLeft, from, to) = do
  let countMax = countWorlFrameVertical sz
      (actualFrom, actualTo) = actualRange countMax (from, to)
      countChars = 1 + actualTo - actualFrom
      leftWallCoords = map (\n -> move n Up lowerLeft) [actualFrom..actualTo]
      nextR = move countMax Up lowerLeft
  mapM_ (renderChar_ '|') leftWallCoords
  if countChars <= 0
    then
      return (nextR, from - countMax, to - countMax)
    else
      return (nextR, from + countChars - countMax, to - countMax)

-- 0 is upper left
renderUpperWall :: WorldSize -> (RenderState, Int, Int) -> IO (RenderState, Int, Int)
renderUpperWall sz (upperLeft, from, to) = do
  let countMax = countWorlFrameHorizontal sz
      (actualFrom, actualTo) = actualRange countMax (from, to)
      countChars = 1 + actualTo - actualFrom
      nextR = go Down $ move (countMax - 1) RIGHT upperLeft
  if countChars <= 0
    then
      return (nextR, from - countMax, to - countMax)
    else
      renderChars countChars '_' (move actualFrom RIGHT upperLeft)
       >> return (nextR, from + countChars - countMax, to - countMax)

renderLowerWall :: WorldSize -> (RenderState, Int, Int) -> IO (RenderState, Int, Int)
renderLowerWall sz (lowerRight, from, to) = do
  let countMax = countWorlFrameHorizontal sz
      (actualFrom, actualTo) = actualRange countMax (from, to)
      countChars = 1 + actualTo - actualFrom
      nextR = go Up $ move (countMax - 1) LEFT lowerRight
  if countChars <= 0
    then
      return (nextR, from - countMax, to - countMax)
    else
      renderChars countChars 'T' (move actualTo LEFT lowerRight)
       >> return (nextR, from + countChars - countMax, to - countMax)

actualRange :: Int -> (Int, Int) -> (Int, Int)
actualRange countMax (from, to) =
  (max 0 from, min to $ pred countMax)

renderWorldFrame :: Maybe FrameAnimation -- ^ contains previous size
                 -> WorldSize -- ^ new size
                 -> RenderState -- ^ wrt new size
                 -> IO RenderState
renderWorldFrame mayAnim sz upperLeft = do
  fg <- setRawForeground worldFrameColor
  maybe
    (renderPartialWorldFrame sz (upperLeft, 0, countWorldFrameChars sz - 1))
    (\(FrameAnimation szBefore _ _ _ (Iteration (_, Frame i)) _) -> do
      let diff@(RenderState (Coords _ (Col dc))) = diffUpperLeft sz szBefore
          n = maxNumberOfSteps sz szBefore
          upperLeftBefore = sumRS diff upperLeft
          render diBefore di = do
            renderFrom Extremities (n-(i+diBefore)) szBefore upperLeftBefore
            renderFrom Middle      (n-(i+di))       sz       upperLeft
      if dc >= 0
        then
          -- expanding animation
          render dc 0
        else
          -- shrinking animation
          render 0 (negate dc)
    ) mayAnim
  restoreForeground fg
  return $ go Down $ go RIGHT upperLeft

-- | Includes start and end steps, ie if animation consists of no change, it returns 1.
--   If animation consists of a single change, it returns 2.
maxNumberOfSteps :: WorldSize -> WorldSize -> Int
maxNumberOfSteps s s' = 1 + quot (1 + max (maxDim s) (maxDim s')) 2

data BuildFrom = Middle
               | Extremities -- generates the complement

ranges :: Int -> WorldSize -> BuildFrom -> [(Int, Int)]
ranges progress sz =
  let h = countWorlFrameVertical sz
      w = countWorlFrameHorizontal sz

      diff = quot (w - h) 2 -- vertical and horizontal animations should start at the same time

      extW = rangeByRemovingFromTotal progress w
      extH = rangeByRemovingFromTotal (max 0 $ progress-diff) h

      exts = [extW, extH, extW, extH]
      lengths = [w,h,w,h]

      (total, starts) = mapAccumL (\acc v -> (acc + v, acc)) 0 lengths
      res = map (\(ext, s) -> ext s) $ zip exts starts
  in \case
        Middle      -> res
        Extremities -> complement 0 (total-1) res

renderFrom :: BuildFrom -> Int -> WorldSize -> RenderState -> IO ()
renderFrom rangeType progress sz r = do
  let rs = ranges progress sz rangeType
  mapM_ (\(min_, max_) -> renderPartialWorldFrame sz (r, min_, max_)) rs

complement :: Int -> Int -> [(Int, Int)] -> [(Int, Int)]
complement a max_ []          = [(a, max_)]
complement a max_ l@((b,c):_) = (a, pred b) : complement (succ c) max_ (tail l)

rangeByRemovingFromTotal :: Int -> Int -> Int -> (Int, Int)
rangeByRemovingFromTotal remove total start =
  let min_ = remove
      max_ = total - 1 - remove
  in (start + min_, start + max_)
