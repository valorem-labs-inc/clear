// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "../interfaces/IUniswapV3Pool.sol";

library UniV3Oracle {
    function consult(IUniswapV3Pool pool, uint32 secondsAgo)
        internal
        view
        returns (int24 arithmeticMeanTick, uint160 secondsPerLiquidityX128)
    {
        require(secondsAgo != 0, "BP");

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
            pool.observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        arithmeticMeanTick = int24(tickCumulativesDelta / int32(secondsAgo));
        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int32(secondsAgo) != 0)) {
            arithmeticMeanTick--;
        }

        secondsPerLiquidityX128 = secondsPerLiquidityCumulativeX128s[1] - secondsPerLiquidityCumulativeX128s[0];
    }

    function getMaxSecondsAgo(IUniswapV3Pool pool, uint16 observationIndex, uint16 observationCardinality)
        internal
        view
        returns (uint32 secondsAgo)
    {
        require(observationCardinality != 0, "NI");

        unchecked {
            (uint32 observationTimestamp,,, bool initialized) =
                pool.observations((observationIndex + 1) % observationCardinality);

            // The next index might not be initialized if the cardinality is in the process of increasing
            // In this case the oldest observation is always in index 0
            if (!initialized) {
                (observationTimestamp,,,) = pool.observations(0);
            }

            secondsAgo = uint32(block.timestamp) - observationTimestamp;
        }
    }
}
