module ViperVM.Arch.X86_64.Assembler.Addressing
   ( Addr(..)
   , getAddr
   , getRegRegister
   , getRMRegister
   , Op(..)
   , getRMOp
   , getEffectiveOperandSize
   , getEffectiveAddressSize
   )
where

import Data.Bits
import Data.Word

import ViperVM.Arch.X86_64.Assembler.Mode
import ViperVM.Arch.X86_64.Assembler.ModRM
import ViperVM.Arch.X86_64.Assembler.Size
import ViperVM.Arch.X86_64.Assembler.Registers
import ViperVM.Arch.X86_64.Assembler.X86Dec
import ViperVM.Arch.X86_64.Assembler.LegacyPrefix

-- The X86 architecture supports different kinds of memory addressing. The
-- available addressing modes depend on the execution mode.
-- The most complicated addressing has:
--    - a base register
--    - an index register with a scaling factor (1, 2, 4 or 8)
--    - an offset (displacement)
--
-- Base and index registers can be extended in 64-bit mode to access new registers.
-- Offset size depends on the address size and on the execution mode.

data Addr = Addr
   { addrBase  :: Maybe Register
   , addrIndex :: Maybe Register
   , addrDisp  :: Maybe SizedValue
   , addrScale :: Maybe Scale
   }
   deriving (Show,Eq)

-- | Read the memory addressing in r/m field
getAddr :: ModRM -> X86Dec Addr
getAddr modrm = do
   baseExt  <- getBaseRegExt
   indexExt <- getIndexRegExt
   useExtendedRegisters <- getUseExtRegs
   asize    <- getAddressSize
   mode     <- getMode

   -- depending on the r/m field in ModRM and on the address size, we know if
   -- we must read a SIB byte
   sib   <- case useSIB asize modrm of
      True  -> Just . SIB <$> nextWord8
      False -> return Nothing

   -- depending on the mod field and the r/m in ModRM and on the address size,
   -- we know if we must read a displacement and its size
   disp <- case useDisplacement asize modrm of
      Nothing     -> return Nothing
      Just Size8  -> Just . SizedValue8  <$> nextWord8
      Just Size16 -> Just . SizedValue16 <$> nextWord16
      Just Size32 -> Just . SizedValue32 <$> nextWord32
      Just _      -> error "Invalid displacement size"

   return $ case asize of
      -- if we are in 16-bit addressing mode, we don't care about the base
      -- register extension
      AddrSize16 -> case (modField modrm, rmField modrm) of
         (_,0) -> Addr (Just R_BX) (Just R_SI) disp Nothing
         (_,1) -> Addr (Just R_BX) (Just R_DI) disp Nothing
         (_,2) -> Addr (Just R_BP) (Just R_SI) disp Nothing
         (_,3) -> Addr (Just R_BP) (Just R_DI) disp Nothing
         (_,4) -> Addr (Just R_SI) Nothing     disp Nothing
         (_,5) -> Addr (Just R_DI) Nothing     disp Nothing
         (0,6) -> Addr Nothing     Nothing     disp Nothing
         (_,6) -> Addr (Just R_BP) Nothing     disp Nothing
         (_,7) -> Addr (Just R_BX) Nothing     disp Nothing
         _     -> error "Invalid 16-bit addressing"

      
      -- 32-bit and 64-bit addressing
      _ -> Addr baseReg indexReg disp scale
         where
            -- size of the operand
            sz   = case asize of
               AddrSize16 -> error "Invalid address size"
               AddrSize32 -> Size32
               AddrSize64 -> Size64

            -- associate base/index register
            makeReg =  regFromCode RF_GPR (Just sz) useExtendedRegisters

            -- the extended base register is either in SIB or in r/m. In some
            -- cases, there is no base register or it is implicitly RIP/EIP
            baseReg = case (modField modrm, rmField modrm) of
               (0,5)
                  | isLongMode mode -> case asize of
                     AddrSize32 -> Just R_EIP
                     AddrSize64 -> Just R_RIP
                     AddrSize16 -> error "Invalid address size"
                  | otherwise -> Nothing
               _ -> Just . makeReg $ (baseExt `shiftL` 3) .|. br
                  where
                     br = case sib of
                        Nothing -> rmField modrm
                        Just s  -> baseField s

            -- if there is an index field, it is in sib
            indexReg = makeReg . ((indexExt `shiftL` 3) .|.) . indexField <$> sib

            -- if there is a scale, it is in sib
            scale = scaleField <$> sib

getRegister :: RegFamily -> Maybe Size -> Word8 -> X86Dec Register
getRegister fm size code = do
   useExtRegs <- getUseExtRegs
   return (regFromCode fm size useExtRegs code)

getRMRegister :: RegFamily -> Maybe Size -> ModRM -> X86Dec Register
getRMRegister fm size modrm = do
   ext <- getBaseRegExt
   getRegister fm size ((ext `shiftL` 3) .|. rmField modrm)

getRegRegister :: RegFamily -> Maybe Size -> ModRM -> X86Dec Register
getRegRegister fm size modrm = do
   ext <- getRegExt
   getRegister fm size ((ext `shiftL` 3) .|. regField modrm)

data Op
   = OpReg Register
   | OpMem Addr
   | OpImm SizedValue
   deriving (Show,Eq)

getRMOp :: RegFamily -> Maybe Size -> ModRM -> X86Dec Op
getRMOp fm size m = case rmRegMode m of
   True  -> OpReg <$> getRMRegister fm size m
   False -> OpMem <$> getAddr m

-- | Return effective operand size
--
-- See Table 1-2 "Operand-Size Overrides" in AMD Manual v3
getEffectiveOperandSize :: X86Dec OperandSize
getEffectiveOperandSize = do
   mode     <- getMode
   prefixes <- fmap toLegacyPrefix <$> getLegacyPrefixes
   osize    <- getOperandSize
   opSize64 <- getOpSize64

   let isOverrided = PrefixOperandSizeOverride `elem` prefixes

   return $ case (mode, osize, isOverrided, opSize64) of
      (LongMode Long64bitMode, _, _, True)         -> OpSize64
      (LongMode Long64bitMode, def, False, False)  -> def
      (LongMode Long64bitMode, _, True, False)     -> OpSize16
      (_, OpSize16, False, _)                      -> OpSize16
      (_, OpSize32, False, _)                      -> OpSize32
      (_, OpSize32, True, _)                       -> OpSize16
      (_, OpSize16, True, _)                       -> OpSize32
      _ -> error "Invalid combination of modes and operand sizes"

-- | Return effective address size
--
-- See Table 1-1 "Address-Size Overrides" in AMD Manual v3
--
-- The prefix also changes the size of RCX when it is implicitly accessed
--
-- Address size for implicit accesses to the stack segment is determined by D
-- bit in the stack segment descriptor or is 64 bit in 64 bit mode.
--
getEffectiveAddressSize :: X86Dec AddressSize
getEffectiveAddressSize = do
   mode        <- getMode
   asize       <- getAddressSize
   prefixes    <- fmap toLegacyPrefix <$> getLegacyPrefixes

   let isOverrided = PrefixAddressSizeOverride `elem` prefixes
   
   return $ case (mode, asize, isOverrided) of
      (LongMode Long64bitMode, _, False)     -> AddrSize64
      (LongMode Long64bitMode, _, True)      -> AddrSize32
      (_, AddrSize16, False)                 -> AddrSize16
      (_, AddrSize32, False)                 -> AddrSize32
      (_, AddrSize32, True)                  -> AddrSize16
      (_, AddrSize16, True)                  -> AddrSize32
      _ -> error "Invalid combination of modes and address sizes"
   

