{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}

module Text.ColorString
            ( ColorString(..)
            , colored
            , countChars
            ) where

import           Imajuscule.Prelude

import           System.Console.ANSI(Color8Code(..))

import           Color
import           Color.Interpolation

import qualified Data.List as List(length, splitAt)
import           Data.String(IsString(..))
import           Data.Text( Text, length, pack, unpack )

import           Math

import           Util

newtype ColorString = ColorString [(Text, Color8Code)] deriving(Show)

-- TODO maybe it would be faster to have a representation with Array (Char, Color8Code)
--  (ie the result of simplify)
instance DiscretelyInterpolable ColorString where
  distance c1 c2 =
    let colorDist (_, color) (_, color') = bresenhamColor8Length color color'
        n1 = countChars c1
        n2 = countChars c2
        s1 = simplify c1
        s2 = simplify c2

        (c1', remaining) = interpolateChars c1 c2 countTextChanges
        s1' = simplify $ assert (remaining == 0) c1'
        l = zipWith colorDist s1' s2 -- since color interpolation happends AFTER char changes,
                                     -- we compare colors with result of char interpolation
        colorDistance =
          if null l
            then
              1
            else
              maximum l

        toString = map fst
        str1 = toString s1
        str2 = toString s2
        lPref = List.length $ commonPrefix str1 str2
        lSuff = List.length $ commonSuffix (drop lPref str1) (drop lPref str2)
        countTextChanges = max n1 n2 - (lPref + lSuff)
    in colorDistance + countTextChanges

  interpolate c1 c2 i =
    let (c1', remaining) = interpolateChars c1 c2 i
    in if remaining >= 0
         then
           c1'
          else
            interpolateColors c1' c2 (negate remaining)

interpolateColors :: ColorString
                  -- ^ from
                  -> ColorString
                  -- ^ to
                  -> Int
                  -- ^ progress
                  -> ColorString
interpolateColors c1 c2 i =
  let itp (_, color) (char, color') =
        (pack [char],
        let (IColor8Code res) = interpolate (IColor8Code color) (IColor8Code color') i in res)
  in ColorString $ zipWith itp (simplify c1) (simplify c2)

interpolateChars :: ColorString
                 -- ^ from
                 -> ColorString
                 -- ^ to
                 -> Int
                 -- ^ progress
                 -> (ColorString, Int)
                 -- ^ (result,nSteps)
                 --             | >=0 : "remaining until completion"
                 --             | <0  : "completed since" (using abolute value))
interpolateChars c1 c2 i =
  let n1 = countChars c1
      n2 = countChars c2
      s1 = simplify c1
      s2 = simplify c2

      toString = map fst
      str1 = toString s1
      str2 = toString s2
      lPref = List.length $ commonPrefix str1 str2
      lSuff = List.length $ commonSuffix (drop lPref str1) (drop lPref str2)

      -- common prefix, common suffix

      (commonPref, s1AfterCommonPref) = List.splitAt lPref s1
      commonSuff = drop (n1 - (lSuff + lPref)) s1AfterCommonPref

      -- common differences (ie char changes)

      totalCD = min n1 n2 - (lPref + lSuff)
      nCDReplaced = clamp i 0 totalCD

      s2AfterCommonPref = drop lPref s2
      -- TODO use source color when replacing a char (color will be interpolated later on)
      cdReplaced = take nCDReplaced s2AfterCommonPref

      nCDUnchanged = totalCD - nCDReplaced
      cdUnchanged = take nCDUnchanged $ drop nCDReplaced s1AfterCommonPref

      -- exclusive differences (ie char deletion or insertion)
      -- TODO if n1 > n2, reduce before replacing
      signedTotalExDiff = n2 - n1
      signedNExDiff = signum signedTotalExDiff * clamp (i - totalCD) 0 (abs signedTotalExDiff)
      (nExDiff1,nExDiff2) =
        if signedTotalExDiff >= 0
          then
            (0, signedNExDiff)
          else
            (abs $ signedTotalExDiff - signedNExDiff, 0)
      ed1 = take nExDiff1 $ drop totalCD s1AfterCommonPref
      ed2 = take nExDiff2 $ drop totalCD s2AfterCommonPref

      remaining = (totalCD + abs signedTotalExDiff) - i

  in (ColorString
      $ map (\(char,color) -> (pack [char], color))
      $ commonPref ++ cdReplaced ++ cdUnchanged ++ ed1 ++ ed2 ++ commonSuff
      , assert (remaining == max n1 n2 - (lPref + lSuff) - i) remaining)

instance IsString ColorString where
  fromString str = ColorString [(pack str, white)]


simplify :: ColorString -> [(Char, Color8Code)]
simplify (ColorString []) = []
simplify (ColorString l@(_:_)) =
  let (txt, color) = head l
  in map (\c -> (c,color)) (unpack txt) ++ simplify (ColorString $ tail l)


colored :: Text -> Color8Code -> ColorString
colored t c = ColorString [(t,c)]

countChars :: ColorString -> Int
countChars (ColorString cs) = sum $ map (length . fst) cs

instance Monoid ColorString where
  mempty = ColorString [("", Color8Code 0)]
  mappend (ColorString x) (ColorString y) = ColorString $ x ++ y
