// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import "../interfaces/IUniswapV3Pool.sol";
import "../libraries/Volatility.sol";
import "../libraries/UniV3Oracle.sol";
import "../VolatilityOracle.sol";

contract VolatilityTest is Test {
    mapping(IUniswapV3Pool => Volatility.FeeGrowthGlobals[25])
        public feeGrowthGlobals;

    function testSomething() public {
        IUniswapV3Pool pool = IUniswapV3Pool(
            0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168
        );

        VolatilityOracle oracle = new VolatilityOracle();

        oracle.cachePoolMetadata(pool);

        uint256 iv = oracle.volatilityForPool(pool);

        console.log(iv);

        assertTrue(true);
    }
}
