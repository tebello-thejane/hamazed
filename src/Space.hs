{-# LANGUAGE DeriveGeneric #-}

module Space
    ( Space(..)
    , Material(..)
    , getMaterial
    , location
    , mkRectangle
    ) where


import           GHC.Generics( Generic )

import           Numeric.LinearAlgebra.Data( (!)
                                           , fromLists
                                           , Matrix )

import           Foreign.C.Types( CInt(..) )

import           Geo( Coords(..)
                    , Col(..)
                    , Row(..) )
import           WorldSize( Location(..)
                          , WorldSize(..) )

data Space = Space {
    _space :: !(Matrix CInt)
  , _spaceSize :: !WorldSize -- ^ represents the aabb of the Air (TODO support non square aabbs)
}

data Material = Air
              | Wall
              deriving(Generic, Eq, Show)

-- unfortunately I didn't find a Matrix implementation that supports arbitrary types
-- so I need to map my type on a CInt

mapMaterial :: Material -> CInt
mapMaterial Air  = 0
mapMaterial Wall = 1

mapInt :: CInt -> Material
mapInt 0 = Air
mapInt 1 = Wall
mapInt _ = error "mapInt with that should never happen"

-- | creates an empty rectangle of size specified in parameters, with a one-element border
mkRectangle :: Row -> Col -> Space
mkRectangle (Row heightEmptySpace) (Col widthEmptySpace) =
  let ncols = widthEmptySpace + 2

      wall = mapMaterial Wall
      air  = mapMaterial Air

      upperRow = replicate ncols wall
      middleRow = wall : replicate widthEmptySpace air ++ [wall]
      l = [upperRow] ++ replicate heightEmptySpace middleRow ++ [upperRow]
  in Space (fromLists l) (WorldSize $ Coords (Row heightEmptySpace) (Col widthEmptySpace))

-- | 0,0 Coord corresponds to 1,1 matrix
getMaterial :: Coords -> Space -> Material
getMaterial (Coords (Row r) (Col c)) (Space mat (WorldSize (Coords (Row rs) (Col cs))))
  | r < 0 || c < 0 = Wall
  | r > rs-1 || c > cs-1 = Wall
  | otherwise = mapInt $ mat !(r+1) !(c+1)

location :: Coords -> Space -> Location
location c s = case getMaterial c s of
  Wall -> OutsideWorld
  Air  -> InsideWorld

{--

reboundMaxRecurse :: Space -> Int -> Coords -> Maybe Coords
reboundMaxRecurse sz maxRecurse (Coords (Row r) (Col c)) =
  let mayR = reboundIntMaxRecurse sz maxRecurse r
      mayC = reboundIntMaxRecurse sz maxRecurse c
  in  case mayR of
        Nothing -> Nothing
        (Just newR) -> case mayC of
            Nothing -> Nothing
            (Just newC) -> Just $ Coords (Row newR) (Col newC)

reboundIntMaxRecurse :: Space -> Int -> Int -> Maybe Int
reboundIntMaxRecurse s@(WorldSize sz) maxRecurse i
  | maxRecurse == 0 = Nothing
  | i < 0     = reboundIntMaxRecurse s rec $ -i
  | i > sz-1  = reboundIntMaxRecurse s rec $ 2*(sz-1)-i
  | otherwise = Just i
  where rec = pred maxRecurse

rebound :: Space -> Coords -> Coords
rebound sz (Coords (Row r) (Col c)) = Coords (Row $ reboundInt sz r) (Col $ reboundInt sz c)

reboundInt :: Space -> Int -> Int
reboundInt s@(WorldSize sz) i
  | i < 0     = reboundInt s $ -i
  | i > sz-1  = reboundInt s $ 2*(sz-1)-i
  | otherwise = i

--}
