{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Test.Cardano.Api.Orphans
  (
  ) where

import           Cardano.Api

import           Cardano.Crypto.DSIGN.Class (SignKeyDSIGN)

import           Cardano.Prelude

import           Shelley.Spec.Ledger.Crypto (DSIGN)
import           Shelley.Spec.Ledger.Keys (SKey (..))

import           Test.Cardano.Crypto.Orphans ()

deriving instance Eq KeyPair
deriving instance Eq PublicKey
deriving instance Eq ShelleyVerificationKey
deriving instance Eq (SignKeyDSIGN (DSIGN crypto)) => Eq (SKey crypto)
