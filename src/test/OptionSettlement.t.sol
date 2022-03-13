// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "ds-test/test.sol";
// TODO(is this really useful for testing)
import "forge-std/stdlib.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IWETH.sol";
import "../OptionSettlement.sol";

contract OptionSettlementTest is DSTest {
    // These are just happy path functional tests ATM
    // TODO(Fuzzing)
    // TODO(correctness)
    Vm public constant VM = Vm(HEVM_ADDRESS);
    IWETH public weth;
    IERC20 public dai;
    OptionSettlementEngine public engine;

    function setUp() public {
        // Setup WETH
        weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        // Setup DAI
        dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        // Setup settlement engine
        engine = new OptionSettlementEngine();
    }

    function testNewOptionsChain(uint256 settlementSeed) public {
        Option memory info = Option({
            underlyingAsset: address(weth),
            exerciseAsset: address(dai),
            settlementSeed: settlementSeed,
            underlyingAmount: 1 ether,
            exerciseAmount: 3000 ether,
            exerciseTimestamp: block.timestamp,
            expiryTimestamp: (block.timestamp + 604800)
        });
        engine.newOptionsChain(info);
    }
}
