module ViperVM.Arch.Linux.Syscalls
   ( module X
   )
   where

--TODO: use conditional import here when we will support different
--architectures

import ViperVM.Arch.X86_64.Linux.Syscalls as X