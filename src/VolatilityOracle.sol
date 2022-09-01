// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "./interfaces/IUniswapV3Pool.sol";
import "./libraries/Volatility.sol";
import "./libraries/UniV3Oracle.sol";

import "forge-std/Test.sol";

contract VolatilityOracle {
    struct Indices {
        uint8 read;
        uint8 write;
    }

    mapping(IUniswapV3Pool => Volatility.PoolMetadata)
        public cachedPoolMetadata;

    mapping(IUniswapV3Pool => Volatility.FeeGrowthGlobals[25])
        public feeGrowthGlobals;

    mapping(IUniswapV3Pool => Indices) public feeGrowthGlobalsIndices;

    function cachePoolMetadata(IUniswapV3Pool pool) external {
        Volatility.PoolMetadata memory poolMetadata;

        (
            ,
            ,
            uint16 observationIndex,
            uint16 observationCardinality,
            ,
            uint8 feeProtocol,

        ) = pool.slot0();

        poolMetadata.maxSecondsAgo =
            (UniV3Oracle.getMaxSecondsAgo(
                pool,
                observationIndex,
                observationCardinality
            ) * 3) /
            5;

        uint24 fee = pool.fee();
        poolMetadata.gamma0 = fee;
        poolMetadata.gamma1 = fee;
        if (feeProtocol % 16 != 0) {
            poolMetadata.gamma0 -= fee / (feeProtocol % 16);
        }

        if (feeProtocol >> 4 != 0) {
            poolMetadata.gamma1 -= fee / (feeProtocol >> 4);
        }

        poolMetadata.tickSpacing = pool.tickSpacing();

        cachedPoolMetadata[pool] = poolMetadata;
    }

    function volatilityForPool(IUniswapV3Pool pool)
        external
        returns (uint256 IV)
    {
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();

        Volatility.FeeGrowthGlobals[25]
            storage feeGrowthGlobal = feeGrowthGlobals[pool];

        Indices memory idxs = _loadIndicesAndSelectRead(pool, feeGrowthGlobal);

        Volatility.FeeGrowthGlobals memory current;
        (IV, current) = _volatilityForPool(
            pool,
            sqrtPriceX96,
            tick,
            feeGrowthGlobal[idxs.read]
        );

        // Write to storage
        if (
            current.timestamp - 1 hours > feeGrowthGlobal[idxs.write].timestamp
        ) {
            idxs.write = (idxs.write + 1) % 25;
            feeGrowthGlobals[pool][idxs.write] = current;
        }

        feeGrowthGlobalsIndices[pool] = idxs;
    }

    function _volatilityForPool(
        IUniswapV3Pool _pool,
        uint160 _sqrtPriceX96,
        int24 _tick,
        Volatility.FeeGrowthGlobals memory _previous
    )
        private
        view
        returns (uint256 IV, Volatility.FeeGrowthGlobals memory current)
    {
        Volatility.PoolMetadata memory poolMetadata = cachedPoolMetadata[_pool];

        uint32 secondsAgo = poolMetadata.maxSecondsAgo;
        require(secondsAgo >= 1 hours, "Valorem: need more data");

        if (secondsAgo > 1 days) {
            secondsAgo = 1 days;
        }
        // Throws if secondsAgo == 0
        (
            int24 arithmeticMeanTick,
            uint160 secondsPerLiquidityX128
        ) = UniV3Oracle.consult(_pool, secondsAgo);

        current = Volatility.FeeGrowthGlobals(
            _pool.feeGrowthGlobal0X128(),
            _pool.feeGrowthGlobal1X128(),
            uint32(block.timestamp)
        );

        IV = Volatility.volatilityForPool(
            poolMetadata,
            Volatility.PoolData(
                _sqrtPriceX96,
                _tick,
                arithmeticMeanTick,
                secondsPerLiquidityX128,
                secondsAgo,
                _pool.liquidity()
            ),
            _previous,
            current
        );
    }

    function _loadIndicesAndSelectRead(
        IUniswapV3Pool _pool,
        Volatility.FeeGrowthGlobals[25] storage _feeGrowthGlobal
    ) private view returns (Indices memory) {
        Indices memory idxs = feeGrowthGlobalsIndices[_pool];
        uint32 timingError = _timingError(
            block.timestamp - _feeGrowthGlobal[idxs.read].timestamp
        );

        for (
            uint8 counter = idxs.read + 1;
            counter < idxs.read + 25;
            counter++
        ) {
            uint8 newReadIndex = counter % 25;
            uint32 newTimingError = _timingError(
                block.timestamp - _feeGrowthGlobal[newReadIndex].timestamp
            );

            if (newTimingError < timingError) {
                idxs.read = newReadIndex;
                timingError = newTimingError;
            } else break;
        }

        return idxs;
    }

    function _timingError(uint256 _age) private pure returns (uint32) {
        return uint32(_age < 24 hours ? 24 hours - _age : _age - 24 hours);
    }
}
