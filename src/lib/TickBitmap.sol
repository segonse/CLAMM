// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./BitMath.sol";

library TickBitmap {
    function position(
        int24 tick
    ) private pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8);
        bitPos = uint8(uint24(tick % 256));
    }

    function flipTick(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing
    ) internal {
        require(tick % tickSpacing == 0);
        (int16 wordPos, uint8 bitPos) = position(tick);
        uint256 mask = 1 << bitPos;
        self[wordPos] ^= mask;
    }

    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--;

        (int16 wordPos, uint8 bitPos) = position(tick);

        if (lte) {
            // bitPos所在位及右边都设置为1，bitPos为uint8，正好可以表示256个数，对应self[wordPos]的uint
            // 256每一位
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            // 寻找当前wordPos范围内的tick更小的tick（刻度向左，但在uint256中是右边更小的位）是否有
            // 被初始化过的tick
            // tick初始化意味着在当前tick具有流动性，通过位图快速查找定位下一个可用的tick而不需要遍历
            // 所有tick
            uint256 masked = self[wordPos] & mask;

            bool initialized = masked != 0;

            // BitMath.mostSignificantBit(masked)应该一定小于等于bitPos？
            // 1.如果当前bitPos左边刻度存在初始化过的tick，则寻找当前bitPos和最近的初始化Tick偏移量
            // 2.如果不存在，则寻找当前bitPos到当前wordPos最左侧刻度的偏移量
            next = initialized
                ? (compressed -
                    int24(
                        uint24(bitPos - BitMath.mostSignificantBit(masked))
                    )) * tickSpacing
                : (compressed - int24(uint24(bitPos))) * tickSpacing;
        } else {
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = self[wordPos] & mask;

            bool initialized = masked != 0;

            // nextTick必须大于currentTicky，所以compressed必须加1？
            next = initialized
                ? (compressed +
                    1 +
                    int24(
                        uint24(BitMath.leastSignificantBit(masked) - bitPos)
                    )) * tickSpacing
                : (compressed + 1 + int24(type(uint8).max - uint24(bitPos))) *
                    tickSpacing;
        }
    }
}
