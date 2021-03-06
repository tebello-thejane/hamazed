{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE DeriveGeneric #-}

module Geo.Types
    ( Direction(..)
    ) where

import           Imajuscule.Prelude

import           GHC.Generics( Generic )

data Direction = Up | Down | LEFT | RIGHT deriving (Generic, Eq, Show)
