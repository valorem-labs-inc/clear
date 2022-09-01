// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "../libraries/Volatility.sol";
import "../libraries/UniV3Oracle.sol";
import "../VolatilityOracle.sol";

contract VolatilityTest is Test {
    function testCachePoolMetadata() public {
        IUniswapV3Pool pool = IUniswapV3Pool(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8);

        VolatilityOracle oracle = new VolatilityOracle();

        oracle.cachePoolMetadata(pool);

        (uint32 maxSecondsAgo, uint24 gamma0, uint24 gamma1, int24 tickSpacing) = oracle.cachedPoolMetadata(pool);

        assertEq(maxSecondsAgo, 138487);
        assertEq(gamma0, 3000);
        assertEq(gamma1, 3000);
        assertEq(tickSpacing, 60);
    }

    function testVolatilityForPool() public {
        IUniswapV3Pool pool = IUniswapV3Pool(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8);

        VolatilityOracle oracle = new VolatilityOracle();

        oracle.cachePoolMetadata(pool);

        uint256 iv = oracle.volatilityForPool(pool);
        assertEq(iv, 8329695708861862);

        (uint256 feeGrowthGlobal0, uint256 feeGrowthGlobal1, uint256 timestamp) = oracle.feeGrowthGlobals(pool, 1);
        assertEq(feeGrowthGlobal0, 2632765082876750956909549161655207);
        assertEq(feeGrowthGlobal1, 1138771352674128276125939260909996260194545);
        assertEq(timestamp, 1661876584);
    }
}
