// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "./utils/BaseEngineTest.sol";

/// @notice Integration tests for OptionSettlementEngine
contract OptionSettlementIntegrationTest is BaseEngineTest {
    function testInitial() public {
        assertEq(engine.feeTo(), FEE_TO);
        assertEq(engine.feesEnabled(), true);
    }
}
