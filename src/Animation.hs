
module Animation
    ( Animation(..)
    , mkAnimation
    , stepClosest
    , earliestAnimationTime
    , simpleExplosion
    , quantitativeExplosion
    , renderAnimations
    , WorldSize(..)
    ) where


import           Control.Monad( filterM )

import           Data.List( partition )
import           Data.Time( addUTCTime
                          , NominalDiffTime
                          , UTCTime )
import           Data.Maybe(isJust)
import           System.Random( getStdRandom
                              , randomR )


import           Console( RenderState(..)
                        , renderChar_ )
import           Geo( Coords(..)
                    , sumCoords
                    , translatedFullCircle
                    , translatedFullCircleFromQuarterArc )
import           WorldSize( WorldSize(..)
                          , Location(..)
                          , location )


data Animation = Animation {
    _animationNextTime :: !UTCTime
  , _animationCounter  :: !Int
  , _animationRender :: !(Animation -> WorldSize -> RenderState -> IO (Maybe Animation))
}

data AnimationProgress = AnimationInProgress
                       | AnimationDone
                       deriving(Eq, Show)

mkAnimation :: (Animation -> WorldSize -> RenderState -> IO (Maybe Animation))
            -> UTCTime
            -> Animation
mkAnimation render currentTime = Animation (addUTCTime animationPeriod currentTime) 0 render


simpleExplosionPure :: Coords -> Animation -> [Coords]
simpleExplosionPure center (Animation _ iteration _) =
  let radius = fromIntegral iteration :: Float
      resolution = 8
  in translatedFullCircleFromQuarterArc center radius 0 resolution

quantitativeExplosionPure :: Int -> Coords -> Animation -> [Coords]
quantitativeExplosionPure number center (Animation _ iteration _) =
  let numRand = 10 :: Int
      rnd = 2 :: Int -- TODO store the random number in the state of the animation
  -- rnd <- getStdRandom $ randomR (0,numRand-1)
      radius = fromIntegral iteration :: Float
      firstAngle = (fromIntegral rnd :: Float) * 2*pi / (fromIntegral numRand :: Float)
  in translatedFullCircle center radius firstAngle number

animationPeriod :: Data.Time.NominalDiffTime
animationPeriod = 0.02

timeOf :: Animation -> UTCTime
timeOf (Animation t _ _) = t

-- steps the animations which will be done the soonest
stepClosest :: [Animation] -> [Animation]
stepClosest [] = error "should never happen"
stepClosest l = let m = minimum $ map timeOf l
                    (closest, other) = partition (\a -> timeOf a == m) l
                in other ++ map stepAnimation closest

stepAnimation :: Animation -> Animation
stepAnimation (Animation t i f) = Animation (addUTCTime animationPeriod t) (succ i) f

earliestAnimationTime :: [Animation] -> Maybe UTCTime
earliestAnimationTime []         = Nothing
earliestAnimationTime animations = Just $ minimum $ map timeOf animations


--------------------------------------------------------------------------------
-- IO
--------------------------------------------------------------------------------


renderAnimations :: WorldSize -> RenderState -> [Animation] -> IO [Animation]
renderAnimations sz r =
  filterM (\a@(Animation _ _ render) -> (isJust <$> render a sz r))

renderCharIfInFrame :: Char -> Coords -> WorldSize -> RenderState -> IO Location
renderCharIfInFrame char pos sz (RenderState upperLeftCoords) = do
  let loc = location pos sz
  case loc of
    OutsideWorld -> return ()
    InsideWorld -> renderChar_ char $ RenderState $ sumCoords pos upperLeftCoords
  return loc

setRender :: Animation
          -> (Animation -> WorldSize -> RenderState -> IO (Maybe Animation))
          -> Animation
setRender (Animation t i _) = Animation t i

simpleExplosion :: Coords -> Animation -> WorldSize -> RenderState -> IO (Maybe Animation)
simpleExplosion center a = do
  let points = simpleExplosionPure center a
  renderAnimation points $ setRender a $ simpleExplosion center

quantitativeExplosion :: Int -> Coords -> Animation -> WorldSize -> RenderState -> IO (Maybe Animation)
quantitativeExplosion number center a = do
  let points = quantitativeExplosionPure number center a
  renderAnimation points $ setRender a $ quantitativeExplosion number center

renderAnimation :: [Coords] -> Animation -> WorldSize -> RenderState -> IO (Maybe Animation)
renderAnimation points a sz state = do
  loc <- renderPoints points '.' sz state
  return $ if loc == OutsideWorld then Nothing else Just a

renderPoints :: [Coords] -> Char -> WorldSize -> RenderState -> IO Location
renderPoints points char sz state = do
  locations <- mapM (\c -> renderCharIfInFrame char c sz state) points
  return $ if all (== OutsideWorld) locations then OutsideWorld else InsideWorld