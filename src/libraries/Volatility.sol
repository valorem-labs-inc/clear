// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "solmate/utils/FixedPointMathLib.sol";

import "./FixedPoint96.sol";
import "./FullMath.sol";
import "./TickMath.sol";

library Volatility {
    struct PoolMetadata {
        // the oldest oracle observation that's been populated by the pool
        uint32 maxSecondsAgo;
        // the overall fee minus the protocol fee for token0, times 1e6
        uint24 gamma0;
        // the overall fee minus the protocol fee for token1, times 1e6
        uint24 gamma1;
        // the pool tick spacing
        int24 tickSpacing;
    }

    struct PoolData {
        // the current price (from pool.slot0())
        uint160 sqrtPriceX96;
        // the current tick (from pool.slot0())
        int24 currentTick;
        // the mean tick over some period (from OracleLibrary.consult(...))
        int24 arithmeticMeanTick;
        // the mean liquidity over some period (from OracleLibrary.consult(...))
        uint160 secondsPerLiquidityX128;
        // the number of seconds to look back when getting mean tick & mean liquidity
        uint32 oracleLookback;
        // the liquidity depth at currentTick (from pool.liquidity())
        uint128 tickLiquidity;
    }

    struct FeeGrowthGlobals {
        // the fee growth as a Q128.128 fees of token0 collected per unit of liquidity for the entire life of the pool
        uint256 feeGrowthGlobal0X128;
        // the fee growth as a Q128.128 fees of token1 collected per unit of liquidity for the entire life of the pool
        uint256 feeGrowthGlobal1X128;
        // the block timestamp at which feeGrowthGlobal0X128 and feeGrowthGlobal1X128 were last updated
        uint32 timestamp;
    }

    function volatilityForPool(
        PoolMetadata memory metadata,
        PoolData memory data,
        FeeGrowthGlobals memory a,
        FeeGrowthGlobals memory b
    ) internal pure returns (uint256) {
        uint256 volumeGamma0Gamma1;

        {
            uint128 revenue0Gamma1 = computeRevenueGamma(
                a.feeGrowthGlobal0X128,
                b.feeGrowthGlobal0X128,
                data.secondsPerLiquidityX128,
                data.oracleLookback,
                metadata.gamma1
            );

            uint128 revenue1Gamma0 = computeRevenueGamma(
                a.feeGrowthGlobal1X128,
                b.feeGrowthGlobal1X128,
                data.secondsPerLiquidityX128,
                data.oracleLookback,
                metadata.gamma0
            );

            // This is an approximation. Ideally the fees earned during each swap would be multiplied by the price
            // *at that swap*. But for prices simulated with GBM and swap sizes either normally or uniformly distributed,
            // the error you get from using geometric mean price is <1% even with high drift and volatility.
            volumeGamma0Gamma1 =
                revenue1Gamma0 +
                amount0ToAmount1(revenue0Gamma1, data.arithmeticMeanTick);
        }

        uint128 sqrtTickTVLX32 = uint128(
            FixedPointMathLib.sqrt(
                computeTickTVLX64(
                    metadata.tickSpacing,
                    data.currentTick,
                    data.sqrtPriceX96,
                    data.tickLiquidity
                )
            )
        );

        uint48 timeAdjustmentX32 = uint48(
            FixedPointMathLib.sqrt(
                (uint256(1 days) << 64) / (b.timestamp - a.timestamp)
            )
        );

        if (sqrtTickTVLX32 == 0) {
            return 0;
        }

        unchecked {
            return
                (uint256(2e18) *
                    uint256(timeAdjustmentX32) *
                    FixedPointMathLib.sqrt(volumeGamma0Gamma1)) /
                sqrtTickTVLX32;
        }
    }

    function amount0ToAmount1(uint128 amount0, int24 tick)
        internal
        pure
        returns (uint256 amount1)
    {
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        uint224 priceX96 = uint224(
            FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96)
        );

        amount1 = FullMath.mulDiv(amount0, priceX96, FixedPoint96.Q96);
    }

    function computeRevenueGamma(
        uint256 feeGrowthGlobalAX128,
        uint256 feeGrowthGlobalBX128,
        uint160 secondsPerLiquidityX128,
        uint32 secondsAgo,
        uint24 gamma
    ) internal pure returns (uint128) {
        unchecked {
            uint256 temp;

            if (feeGrowthGlobalBX128 >= feeGrowthGlobalAX128) {
                // feeGrowthGlobal has increased from time A to time B
                temp = feeGrowthGlobalBX128 - feeGrowthGlobalAX128;
            } else {
                // feeGrowthGlobal has overflowed between time A and time B
                temp =
                    type(uint256).max -
                    feeGrowthGlobalAX128 +
                    feeGrowthGlobalBX128;
            }

            temp = FullMath.mulDiv(
                temp,
                secondsAgo * gamma,
                secondsPerLiquidityX128 * 1e6
            );
            return temp > type(uint128).max ? type(uint128).max : uint128(temp);
        }
    }

    function computeTickTVLX64(
        int24 tickSpacing,
        int24 tick,
        uint160 sqrtPriceX96,
        uint128 liquidity
    ) internal pure returns (uint256 tickTVL) {
        tick = TickMath.floor(tick, tickSpacing);

        // both value0 and value1 fit in uint192
        (uint256 value0, uint256 value1) = _getValuesOfLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tick),
            TickMath.getSqrtRatioAtTick(tick + tickSpacing),
            liquidity
        );
        tickTVL = (value0 + value1) << 64;
    }

    function _getValuesOfLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) private pure returns (uint256 value0, uint256 value1) {
        assert(sqrtRatioAX96 <= sqrtRatioX96 && sqrtRatioX96 <= sqrtRatioBX96);

        unchecked {
            uint224 numerator = uint224(
                FullMath.mulDiv(
                    sqrtRatioX96,
                    sqrtRatioBX96 - sqrtRatioX96,
                    FixedPoint96.Q96
                )
            );

            value0 = FullMath.mulDiv(liquidity, numerator, sqrtRatioBX96);
            value1 = FullMath.mulDiv(
                liquidity,
                sqrtRatioX96 - sqrtRatioAX96,
                FixedPoint96.Q96
            );
        }
    }
}
