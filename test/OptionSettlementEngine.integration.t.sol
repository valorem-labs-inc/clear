// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

import "./utils/BaseEngineTest.sol";

/// @notice Integration tests for OptionSettlementEngine
contract OptionSettlementIntegrationTest is BaseEngineTest {
    // address internal constant address(WETHLIKE) = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // address internal constant address(DAILIKE) = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    // address internal constant address(USDCLIKE) = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // IERC20 internal constant DAI = IERC20(address(DAILIKE));
    // IERC20 internal constant WETH = IERC20(address(WETHLIKE));
    // IERC20 internal constant USDC = IERC20(address(USDCLIKE));

    function setUp() public override {
        super.setUp();

        // Fork mainnet
        // vm.createSelectFork(vm.envString("RPC_URL"), 15_000_000);
    }

    function testInitial() public {
        assertEq(engine.feeTo(), FEE_TO);
        assertEq(engine.feesEnabled(), true);
    }
}
