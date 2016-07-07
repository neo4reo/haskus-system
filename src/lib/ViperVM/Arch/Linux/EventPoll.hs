-- | Event polling
module ViperVM.Arch.Linux.EventPoll
   ( EventPollFlag(..)
   , sysEventPollCreate
   )
where

import ViperVM.Arch.Linux.ErrorCode
import ViperVM.Arch.Linux.Syscalls
import ViperVM.Arch.Linux.Handle
import ViperVM.Format.Binary.Word (Word64)

import Data.Bits ((.|.))
import Data.List (foldl')

-- | Polling flag
data EventPollFlag
   = EventPollCloseOnExec
   deriving (Show,Eq)

fromFlag :: EventPollFlag -> Word64
fromFlag EventPollCloseOnExec = 0x80000

fromFlags :: [EventPollFlag] -> Word64
fromFlags = foldl' (.|.) 0 . fmap fromFlag

-- | Create event poller
sysEventPollCreate :: [EventPollFlag] -> SysRet Handle
sysEventPollCreate flags =
   onSuccess (syscall_epoll_create1 (fromFlags flags)) (Handle . fromIntegral)
