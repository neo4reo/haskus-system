-- | Kernel object handle
--
-- File descriptor in original terminology
module Haskus.Arch.Linux.Internals.Handle
   ( Handle (..)
   )
where

-- | Kernel object handle
--
-- (file descriptor in original terminology)
newtype Handle = Handle Word deriving (Show,Eq)
