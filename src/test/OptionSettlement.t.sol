// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "ds-test/test.sol";
// TODO(is this really useful for testing)
import "forge-std/stdlib.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IWETH.sol";
import "../OptionSettlement.sol";

/// @notice Receiver hook utility for NFT 'safe' transfers
abstract contract NFTreceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return 0x150b7a02;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return 0xbc197c81;
    }
}

contract OptionSettlementTest is DSTest, NFTreceiver {
    // These are just happy path functional tests ATM
    // TODO(Fuzzing)
    // TODO(correctness)
    Vm public constant VM = Vm(HEVM_ADDRESS);
    IWETH public weth;
    IERC20 public dai;
    OptionSettlementEngine public engine;

    using stdStorage for StdStorage;
    StdStorage stdstore;

    function writeTokenBalance(
        address who,
        address token,
        uint256 amt
    ) internal {
        stdstore
            .target(token)
            .sig(IERC20(token).balanceOf.selector)
            .with_key(who)
            .checked_write(amt);
    }

    function setUp() public {
        // Setup WETH
        weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        // Setup DAI
        dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        // Setup settlement engine
        engine = new OptionSettlementEngine();
        Option memory info = Option({
            underlyingAsset: address(weth),
            exerciseAsset: address(dai),
            settlementSeed: 1,
            underlyingAmount: 1 ether,
            exerciseAmount: 3000 ether,
            exerciseTimestamp: uint64(block.timestamp),
            expiryTimestamp: (uint64(block.timestamp) + 604800)
        });
        engine.newChain(info);
        // Now we have 1B DAI
        writeTokenBalance(address(this), address(dai), 1000000000 * 1e18);
        // And 10 M WETH
        writeTokenBalance(address(this), address(weth), 10000000 * 1e18);
        // Issue approvals
        IERC20(weth).approve(address(engine), type(uint256).max);
        IERC20(dai).approve(address(engine), type(uint256).max);
    }

    function testNewChain(uint256 settlementSeed) public {
        Option memory info = Option({
            underlyingAsset: address(weth),
            exerciseAsset: address(dai),
            settlementSeed: settlementSeed,
            underlyingAmount: 1 ether,
            exerciseAmount: 3100 ether,
            exerciseTimestamp: uint64(block.timestamp),
            expiryTimestamp: (uint64(block.timestamp) + 604800)
        });
        engine.newChain(info);
    }

    function testFailDuplicateChain() public {
        // This should fail to create the second and duplicate options chain
        Option memory info = Option({
            underlyingAsset: address(weth),
            exerciseAsset: address(dai),
            settlementSeed: 1,
            underlyingAmount: 1 ether,
            exerciseAmount: 3000 ether,
            exerciseTimestamp: uint64(block.timestamp),
            expiryTimestamp: (uint64(block.timestamp) + 604800)
        });
        engine.newChain(info);
    }

    function testUri() public view {
        engine.uri(0);
    }

    function testFailUri() public view {
        engine.uri(1);
    }

    // TODO(Why is gas report not working on this function)
    function testWrite(uint16 amountToWrite) public {
        engine.write(0, uint256(amountToWrite));
        // Assert that we have the contracts
        assert(engine.balanceOf(address(this), 0) == amountToWrite);
        // Assert that we have the claim
        assert(engine.balanceOf(address(this), 1) == 1);
    }

    function testExercise(uint16 amountToWrite) public {
        engine.write(0, uint256(amountToWrite));
        // Assert that we have the contracts
        assert(engine.balanceOf(address(this), 0) == amountToWrite);
        // Assert that we have the claim
        assert(engine.balanceOf(address(this), 1) == 1);
        uint256 bal = IERC20(weth).balanceOf(address(this));
        engine.exercise(0, amountToWrite);
        uint256 newBal = IERC20(weth).balanceOf(address(this));
        assert(newBal == (bal + (1 ether * uint256(amountToWrite))));
    }
}
