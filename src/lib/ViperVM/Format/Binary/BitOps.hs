module ViperVM.Format.Binary.BitOps
   ( makeMask
   , maskLeastBits
   , bitOffset
   , byteOffset
   , reverseBitsGeneric
   , reverseLeastBits
   , bitsToString
   , bitsFromString
   , BitReversable (..)
   )
where

import Data.Word
import Data.Bits
import Data.List (foldl')

import ViperVM.Format.Binary.BitOps.BitReverse

-- | makeMask 3 = 00000111
makeMask :: (Bits a, Num a) => Int -> a
makeMask n = (1 `shiftL` fromIntegral n) - 1
{-# SPECIALIZE makeMask :: Int -> Int #-}
{-# SPECIALIZE makeMask :: Int -> Word #-}
{-# SPECIALIZE makeMask :: Int -> Word8 #-}
{-# SPECIALIZE makeMask :: Int -> Word16 #-}
{-# SPECIALIZE makeMask :: Int -> Word32 #-}
{-# SPECIALIZE makeMask :: Int -> Word64 #-}

-- | Keep only the n least-significant bits of the given value
maskLeastBits :: (Bits a, Num a) => Int -> a -> a
maskLeastBits n v = v .&. makeMask n
{-# INLINE maskLeastBits #-}

-- | Compute bit offset (equivalent to x `mod` 8 but faster)
bitOffset :: Int -> Int
bitOffset n = makeMask 3 .&. n
{-# INLINE bitOffset #-}

-- | Compute byte offset (equivalent to x `div` 8 but faster)
byteOffset :: Int -> Int
byteOffset n = n `shiftR` 3
{-# INLINE byteOffset #-}

-- | Reverse the @n@ least important bits of the given value. The higher bits
-- are set to 0.
reverseLeastBits :: (FiniteBits a, BitReversable a) => Int -> a -> a
reverseLeastBits n value = reverseBits value `shiftR` (finiteBitSize value - n)


bitsToString :: FiniteBits a => a -> String
bitsToString x = fmap b [s, s-1 .. 0]
   where
      s   = finiteBitSize x - 1
      b v = if testBit x v then '1' else '0'


bitsFromString :: Bits a => String -> a
bitsFromString xs = foldl' b zeroBits (reverse xs `zip` [0..])
   where
      b x ('0',i) = clearBit x i
      b x ('1',i) = setBit x i
      b _ (c,_)   = error $ "Invalid character in the string: " ++ [c]


-- | Reverse bits in a Word
reverseBitsGeneric :: (FiniteBits a, Integral a) => a -> a
reverseBitsGeneric = liftReverseBits reverseBits4Ops

-- | Data whose bits can be reversed
class BitReversable w where
   reverseBits :: w -> w

instance BitReversable Word8 where
   reverseBits = reverseBits4Ops

instance BitReversable Word16 where
   reverseBits = reverseBits5LgN

instance BitReversable Word32 where
   reverseBits = reverseBits5LgN

instance BitReversable Word64 where
   reverseBits = reverseBits5LgN

instance BitReversable Word where
   reverseBits = reverseBits5LgN
