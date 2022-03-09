// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "ds-test/test.sol";
// TODO(is this really useful for testing)
import "forge-std/stdlib.sol";
import "../OptionSettlement.sol";

contract OptionSettlementTest is DSTest {
    Vm public constant VM = Vm(HEVM_ADDRESS);
    OptionSettlementEngine public engine;

    function setUp() public {
        engine = new OptionSettlementEngine();
    }

    function testExample() public {
        assertTrue(true);
    }
}
