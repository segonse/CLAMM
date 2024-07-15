// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./SqrtPriceMath.sol";
import "./FullMath.sol";

library SwapMath {
    function computeSwapStep(
        uint160 sqrtRatioCurrentX96,
        uint160 sqrtRatioTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        // 1 bip = 1/100 * 1% = 1/1e4
        // 1e6 = 100%
        uint24 feePips
    )
        internal
        pure
        returns (
            uint160 sqrtRatioNextX96,
            uint256 amountIn,
            uint256 amountOut,
            uint256 feeAmount
        )
    {
        bool zeroForOne = sqrtRatioCurrentX96 >= sqrtRatioTargetX96;
        bool exactIn = amountRemaining >= 0;

        // Calculate max amount in or out and next sqrt ratio
        if (exactIn) {
            uint256 amountRemainingLessFee = FullMath.mulDiv(
                uint256(amountRemaining),
                1e6 - feePips,
                1e6
            );

            // Calculate max amount in, round up amount in
            // 如果价格变低，就是0换1，amountIn就是token0，反之
            amountIn = zeroForOne
                ? SqrtPriceMath.getAmount0Delta(
                    sqrtRatioTargetX96,
                    sqrtRatioCurrentX96,
                    liquidity,
                    true
                )
                : SqrtPriceMath.getAmount1Delta(
                    sqrtRatioCurrentX96,
                    sqrtRatioTargetX96,
                    liquidity,
                    true
                );

            //Calculate next sqrt ratio
            // 如果最大amount小于等于剩余amount，则价格可以推到目标，否则计算剩余amount可以推到的价格
            if (amountRemainingLessFee >= amountIn) {
                sqrtRatioNextX96 = sqrtRatioTargetX96;
                // amountRemainingLessFee -= amountIn;
            } else {
                sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                    sqrtRatioCurrentX96,
                    liquidity,
                    amountRemainingLessFee,
                    zeroForOne
                );
            }
        } else {
            // Calculate max amount out, round down amount out
            amountOut = zeroForOne
                ? SqrtPriceMath.getAmount1Delta(
                    sqrtRatioTargetX96,
                    sqrtRatioCurrentX96,
                    liquidity,
                    false
                )
                : SqrtPriceMath.getAmount0Delta(
                    sqrtRatioCurrentX96,
                    sqrtRatioTargetX96,
                    liquidity,
                    false
                );

            //Calculate next sqrt ratio
            if (uint256(-amountRemaining) >= amountIn) {
                sqrtRatioNextX96 = sqrtRatioTargetX96;
            } else {
                sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromOutput(
                    sqrtRatioCurrentX96,
                    liquidity,
                    uint256(-amountRemaining),
                    zeroForOne
                );
            }
        }

        // Calculate amount in and out between sqrt current and next
        bool max = sqrtRatioTargetX96 == sqrtRatioNextX96;
        // max and exactIn   --> in = amountIn
        //                       out= need to calculate
        // max and !exactIn   --> in = need to calculate
        //                        out= amountOut
        // !max and exactIn   --> in = need to calculate
        //                        out= need to calculate
        // !max and !exactIn   --> in = need to calculate
        //                         out= need to calculate
        if (zeroForOne) {
            amountIn = max && exactIn
                ? amountIn
                : SqrtPriceMath.getAmount0Delta(
                    sqrtRatioNextX96,
                    sqrtRatioCurrentX96,
                    liquidity,
                    true
                );
            amountOut = max && !exactIn
                ? amountOut
                : SqrtPriceMath.getAmount1Delta(
                    sqrtRatioNextX96,
                    sqrtRatioCurrentX96,
                    liquidity,
                    false
                );
        } else {
            amountIn = max && exactIn
                ? amountIn
                : SqrtPriceMath.getAmount1Delta(
                    sqrtRatioCurrentX96,
                    sqrtRatioNextX96,
                    liquidity,
                    true
                );
            amountOut = max && !exactIn
                ? amountOut
                : SqrtPriceMath.getAmount0Delta(
                    sqrtRatioCurrentX96,
                    sqrtRatioNextX96,
                    liquidity,
                    false
                );
        }

        // 当精确输出的情况下(此时剩余amount代表的才是输出)，限制amountOut不超过剩余amount
        if (!exactIn && amountOut > uint256(-amountRemaining)) {
            amountOut = uint256(-amountRemaining);
        }

        // Calculate fee on amount in
        if (exactIn && sqrtRatioNextX96 != sqrtRatioTargetX96) {
            feeAmount = uint256(amountRemaining) - amountIn;
        } else {
            // exactIn && sqrtRatioNextX96 = sqrtRatioTargetX96
            // !exactIn && sqrtRatioNextX96 != sqrtRatioTargetX96
            // !exactIn && sqrtRatioNextX96 = sqrtRatioTargetX96

            // a = amountIn
            // f = feePips
            // x = Amount in needed to put amountIn + fee
            // fee = x * f

            // solve for x
            // x = a + fee = a + x * f
            // a = x * (1 - f)
            // x = a / (1 - f)

            // Calculate fee
            // fee = x * f = a / (1 - f) * f

            feeAmount = FullMath.mulDivRoundingUp(
                amountIn,
                feePips,
                1e6 - feePips
            );
        }
    }
}
