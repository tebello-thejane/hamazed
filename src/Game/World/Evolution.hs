{-# LANGUAGE NoImplicitPrelude #-}

module Game.World.Evolution
           ( mkTextAnimLeft
           , getDeltaTime
           , renderEvolutions
           , mkWorldAnimation
           ) where

import           Imajuscule.Prelude

import           Game.World.Types

import           Game.World.Frame

import           Render

import           Text.ColorString

import           Timing

renderEvolutions :: WorldEvolutions -> Frame -> IO ()
renderEvolutions
 we@(WorldEvolutions frameE upDown left)
 frame = do
  let (relFrameFrameE, relFrameUD, relFrameLeft) = getFrames we frame
  renderWorldFrame frameE relFrameFrameE
  renderAnimatedTextCharAnchored upDown relFrameUD
  renderAnimatedTextStringAnchored left relFrameLeft

getDeltaTime :: WorldEvolutions -> Frame -> Maybe Float
getDeltaTime we@(WorldEvolutions frameE (TextAnimation _ _ (EaseClock upDown)) (TextAnimation _ _ (EaseClock left))) frame =
  let (relFrameFrameE, relFrameUD, relFrameLeft) = getFrames we frame
  in evolveDeltaTime frameE relFrameFrameE
    <|> evolveDeltaTime upDown relFrameUD -- todo in TextAnimation we should have a fake evolution just for timing
    <|> evolveDeltaTime left relFrameLeft

getFrames :: WorldEvolutions -> Frame -> (Frame, Frame, Frame)
getFrames (WorldEvolutions (Evolution _ lastFrameFrameE _ _)
                           (TextAnimation _ _ (EaseClock (Evolution _ lastFrameUD _ _))) _) frame =
  let relFrameFrameE = max 0 frame
      relFrameUD = max 0 (relFrameFrameE - lastFrameFrameE)
      relFrameLeft = max 0 (relFrameUD - lastFrameUD)
  in (relFrameFrameE, relFrameUD, relFrameLeft)


mkWorldAnimation :: (FrameSpec, (([ColorString], [ColorString]), ([ColorString], [ColorString])))
                 -> (FrameSpec, (([ColorString], [ColorString]), ([ColorString], [ColorString])))
                 -> UTCTime
                 -- ^ time at which the animation starts
                 -> WorldAnimation
mkWorldAnimation (from, ((f1,f2),(f3,f4))) (to, ((t1,t2),(t3,t4))) t =
  WorldAnimation evolutions deadline (Iteration (Speed 1, zeroFrame))
 where
  frameE = mkEvolution2 (FrameAnimationParallel4 from) (FrameAnimationParallel4 to) 1
  (ta1,ta2) = createInterpolations from to (f1++t1, f2++t2, f3++t3, f4++t4) 1
  evolutions = WorldEvolutions frameE ta1 ta2
  deadline =
    maybe
      Nothing
      (\dt -> Just $ KeyTime $ addUTCTime (floatSecondsToNominalDiffTime dt) t)
      $ getDeltaTime evolutions zeroFrame


createInterpolations :: FrameSpec
                     -> FrameSpec
                     -> ([ColorString],[ColorString],[ColorString],[ColorString])
                     -- ^ Upper text, Lower text, Left text 1, Left text 2
                     -> Float
                     -> (TextAnimation AnchorChars, TextAnimation AnchorStrings)
createInterpolations from to (ups, downs, left1s, left2s) duration =
    let ta1 = mkTextAnimUpDown from to (ups, downs) duration
        ta2 = mkTextAnimLeft from to (left1s, left2s) duration
    in (ta1, ta2)


mkTextAnimLeft :: FrameSpec
               -> FrameSpec
               -> ([ColorString], [ColorString])
               -> Float
               -> TextAnimation AnchorStrings
mkTextAnimLeft from to (txtLeft1s, txtLeft2s)
               duration =
    let (_, _, leftMiddleFrom) = computeRSForInfos from
        (_, _, leftMiddleTo) = computeRSForInfos to

        rightAlignLeft = alignTxt RightAligned

        rightAlignLeft2 x = move 2 Down . rightAlignLeft x

        leftMiddle1FromAligned = rightAlignLeft (head txtLeft1s) leftMiddleFrom
        leftMiddle1ToAligned = rightAlignLeft (last txtLeft1s) leftMiddleTo

        leftMiddle2FromAligned = rightAlignLeft2 (head txtLeft2s) leftMiddleFrom
        leftMiddle2ToAligned = rightAlignLeft2 (last txtLeft2s) leftMiddleTo

    in  mkSequentialTextTranslationsStringAnchored
          [(txtLeft1s, leftMiddle1FromAligned, leftMiddle1ToAligned),
           (txtLeft2s, leftMiddle2FromAligned, leftMiddle2ToAligned)]
          duration

mkTextAnimUpDown :: FrameSpec
                 -> FrameSpec
                 -> ([ColorString], [ColorString])
                 -> Float
                 -> TextAnimation AnchorChars
mkTextAnimUpDown from to (txtUppers, txtLowers)
                 duration =
    let (centerUpFrom, centerDownFrom, _) = computeRSForInfos from
        (centerUpTo, centerDownTo, _) = computeRSForInfos to

        alignTxtCentered = alignTxt Centered

        centerUpFromAligned = alignTxtCentered (head txtUppers) centerUpFrom
        centerUpToAligned = alignTxtCentered (last txtUppers) centerUpTo

        centerDownFromAligned = alignTxtCentered (head txtLowers) centerDownFrom
        centerDownToAligned = alignTxtCentered (last txtLowers) centerDownTo
    in  mkSequentialTextTranslationsCharAnchored
          [(txtUppers, centerUpFromAligned, centerUpToAligned),
           (txtLowers, centerDownFromAligned, centerDownToAligned)]
          duration

alignTxt :: Alignment -> ColorString -> RenderState -> RenderState
alignTxt al txt = uncurry move $ align al $ countChars txt


computeRSForInfos :: FrameSpec -> (RenderState, RenderState, RenderState)
computeRSForInfos (FrameSpec (WorldSize (Coords (Row rs) (Col cs))) upperLeft) =
  (centerUp, centerDown, leftMiddle)
 where
  addWallSize = (+ 2)
  half = flip quot 2
  mkSizes s = (addWallSize s, half s)
  (rFull, rHalf) = mkSizes rs
  (_    , cHalf) = mkSizes cs

  centerUp   = translate (Row $ -1)        (Col $ cHalf + 1) upperLeft
  centerDown = translate (Row $ rFull + 1) (Col $ cHalf + 1) upperLeft
  leftMiddle = translate (Row $ rHalf + 1) (Col $ -1)  upperLeft
