{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

-- | Event polling
module Haskus.Arch.Linux.EventPoll
   ( EventPollFlag(..)
   , sysEventPollCreate
   )
where

import Haskus.Arch.Linux.ErrorCode
import Haskus.Arch.Linux.Syscalls
import Haskus.Arch.Linux.Handle
import Haskus.Format.Binary.Word (Word64)
import Haskus.Format.Binary.Bits ((.|.))
import Haskus.Utils.List (foldl')
import Haskus.Utils.Flow

-- | Polling flag
data EventPollFlag
   = EventPollCloseOnExec
   deriving (Show,Eq)

fromFlag :: EventPollFlag -> Word64
fromFlag EventPollCloseOnExec = 0x80000

fromFlags :: [EventPollFlag] -> Word64
fromFlags = foldl' (.|.) 0 . fmap fromFlag

-- | Create event poller
sysEventPollCreate :: MonadIO m => [EventPollFlag] -> Flow m '[Handle,ErrorCode]
sysEventPollCreate flags =
   liftIO (syscall @"epoll_create1" (fromFlags flags))
      ||> toErrorCodePure (Handle . fromIntegral)
