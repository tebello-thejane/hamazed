{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE LambdaCase #-}

module Game.Event
    ( Event(..)
    , userEventPriority
    , priority
    , eventFromChar
    , TimedEvent(..)
    , ActionTarget(..)
    , getKeyTime
    , coordsForActionTargets
    , Step(..)
    , Meta(..)
    ) where


import           Imajuscule.Prelude

import           Data.List( foldl' )
import           Data.Maybe( mapMaybe )

import           Geo.Discrete.Types( Coords(..), Direction(..))
import           Geo.Discrete( coordsForDirection
                             , sumCoords
                             , zeroCoords)

import           IO.Types

import           Timing( KeyTime
                       , UTCTime )

data TimedEvent = TimedEvent Event UTCTime

data Event =  Action ActionTarget Direction
            | Timeout Step KeyTime
            | Explosion Int
            | GravityExplosion
            | StartLevel Int
            | EndGame
            | Interrupt Meta
            | Nonsense
            deriving(Eq, Show)

data Meta = Configure
          | Quit
          | Help
          deriving(Eq, Show)

data Step = GameStep
          | AnimationStep
          | MessageStep
          | FrameAnimationStep
          deriving(Eq, Show)

priority :: Step -> Int
priority FrameAnimationStep = -1
priority MessageStep = 0
priority GameStep    = 1
-- userEvent is here (in terms of priority)
priority AnimationStep = 3

userEventPriority :: Int
userEventPriority = 2

data ActionTarget = Ship
                  | Laser
                  deriving(Eq, Show)

eventFromChar :: Either Key Char -> Event
eventFromChar =
  either
    (\case
      Escape -> Interrupt Quit
      _      -> Nonsense)
    (\case
      'k' -> Action Laser Down
      'i' -> Action Laser Up
      'j' -> Action Laser LEFT
      'l' -> Action Laser RIGHT
      'd' -> Action Ship Down
      'e' -> Action Ship Up
      's' -> Action Ship LEFT
      'f' -> Action Ship RIGHT
      ' ' -> Explosion 2
      'g' -> GravityExplosion
      _   -> Nonsense)


getKeyTime :: Event -> Maybe KeyTime
getKeyTime (Timeout _ k) = Just k
getKeyTime _             = Nothing

coordsForActionTargets :: ActionTarget -> [Event] -> Coords
coordsForActionTargets target actions = foldl' sumCoords zeroCoords $ map coordsForDirection $ filterActions target actions

filterActions :: ActionTarget -> [Event] -> [Direction]
filterActions target = mapMaybe (maybeDirectionFor target)

maybeDirectionFor :: ActionTarget -> Event -> Maybe Direction
maybeDirectionFor targetFilter (Action actionTarget dir)
   | actionTarget == targetFilter = Just dir
   | otherwise                    = Nothing
maybeDirectionFor _ _ = Nothing
