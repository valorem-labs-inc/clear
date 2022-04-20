// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "./interfaces/IERC20.sol";
import "../OptionSettlement.sol";
import "../interfaces/IOptionSettlementEngine.sol";

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

contract OptionSettlementTest is Test, NFTreceiver {
    using stdStorage for StdStorage;

    OptionSettlementEngine public engine;

    // Tokens
    address public constant WETH_A = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI_A = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC_A = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Admin
    address public constant FEE_TO = 0x36273803306a3C22bc848f8Db761e974697ece0d;

    // Users
    address public constant ALICE = address(0xA);
    address public constant BOB = address(0xB);
    address public constant CAROL = address(0xC);
    address public constant DAVE = address(0xD);
    address public constant EVE = address(0xE);

    // Token interfaces
    IERC20 public constant DAI = IERC20(DAI_A);
    IERC20 public constant WETH = IERC20(WETH_A);
    IERC20 public constant USDC = IERC20(USDC_A);

    // Test option
    uint256 public testOptionId;
    uint40 public testExerciseTimestamp;
    uint40 public testExpiryTimestamp;
    uint96 public testUnderlyingAmount = 1 ether;
    uint96 public testExerciseAmount = 3000 ether;
    uint256 public testDuration = 1 days;

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
        engine = new OptionSettlementEngine();

        testExerciseTimestamp = uint40(block.timestamp);
        testExpiryTimestamp = uint40(block.timestamp + testDuration);
        IOptionSettlementEngine.Option memory option = IOptionSettlementEngine
            .Option({
                underlyingAsset: WETH_A,
                exerciseAsset: DAI_A,
                settlementSeed: 1234567,
                underlyingAmount: testUnderlyingAmount,
                exerciseAmount: testExerciseAmount,
                exerciseTimestamp: testExerciseTimestamp,
                expiryTimestamp: testExpiryTimestamp
            });
        testOptionId = engine.newChain(option);

        // pre-load balances and approvals
        address[6] memory recipients = [
            address(engine),
            ALICE,
            BOB,
            CAROL,
            DAVE,
            EVE
        ];
        for (uint256 i = 0; i < 6; i++) {
            address recipient = recipients[i];
            // Now we have 1B in stables and 10M WETH 
            writeTokenBalance(recipient, DAI_A, 1000000000 * 1e18);
            writeTokenBalance(recipient, USDC_A, 1000000000 * 1e6);
            writeTokenBalance(recipient, WETH_A, 10000000 * 1e18);
            vm.startPrank(recipient);
            WETH.approve(address(engine), type(uint256).max);
            DAI.approve(address(engine), type(uint256).max);
            USDC.approve(address(engine), type(uint256).max);
            engine.setApprovalForAll(address(this), true);
            vm.stopPrank();
        }
    }

    // **********************************************************************
    //                            PASS TESTS
    // **********************************************************************

    function testSetFeeTo() public {
        assertEq(engine.feeTo(), FEE_TO);
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.AccessControlViolation.selector, address(this), FEE_TO));
        engine.setFeeTo(ALICE);
        vm.startPrank(FEE_TO);
        engine.setFeeTo(ALICE);
        vm.stopPrank();
        assertEq(engine.feeTo(), ALICE);
    }

    function test_exercise_BeforeExpiry() public {
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        // Fast-forward to just before expiry
        vm.warp(testExpiryTimestamp - 1);
        
        // Bob exercises
        vm.startPrank(BOB);
        engine.exercise(testOptionId, 1);
        vm.stopPrank();
    }

    function test_exercise_AdditionalAmount() public {
        IOptionSettlementEngine.Claim memory claim;

        // Alice writes 1
        vm.startPrank(ALICE);
        uint256 claimId1 = engine.write(testOptionId, 1);
        // Then writes another
        uint256 claimId2 = engine.write(testOptionId, 1);
        vm.stopPrank();

        claim = engine.claim(claimId1);
        assertEq(claim.option, testOptionId);
        assertEq(claim.amountWritten, 1);
        assertEq(claim.amountExercised, 0);
        if (claim.claimed == false) assertTrue(true);
        
        claim = engine.claim(claimId2);
        assertEq(claim.option, testOptionId);
        assertEq(claim.amountWritten, 1);
        assertTrue(!claim.claimed);    
    }

    function test_exercise_WithDifferentDecimals() public {
        // write an option where one of the assets isn't 18 decimals
        IOptionSettlementEngine.Option memory option = IOptionSettlementEngine
            .Option({
                underlyingAsset: USDC_A,
                exerciseAsset: DAI_A,
                settlementSeed: 1234567,
                underlyingAmount: testUnderlyingAmount,
                exerciseAmount: testExerciseAmount,
                exerciseTimestamp: testExerciseTimestamp,
                expiryTimestamp: testExpiryTimestamp
            });
        uint256 optionId = engine.newChain(option);

        vm.startPrank(ALICE);
        engine.write(optionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();
        vm.warp(1);
        vm.startPrank(BOB);
        engine.exercise(optionId, 1);
        vm.stopPrank();
    }


    // **********************************************************************
    //                            FAIL TESTS
    // **********************************************************************
   function testFail_newChain_OptionsChainExists() public {
        IOptionSettlementEngine.Option memory option = IOptionSettlementEngine
            .Option({
                underlyingAsset: WETH_A,
                exerciseAsset: DAI_A,
                settlementSeed: 1234567,
                underlyingAmount: testUnderlyingAmount,
                exerciseAmount: testExerciseAmount,
                exerciseTimestamp: testExerciseTimestamp,
                expiryTimestamp: testExpiryTimestamp
            });
        // TODO: investigate this revert - OptionsChainExists error should be displayed
        //  with an argument, implying this expectRevert would use `abi.encodeWithSelector();
        vm.expectRevert(IOptionSettlementEngine.OptionsChainExists.selector);
        engine.newChain(option);
    }

    function testFail_newChain_ExerciseWindowTooShort() public {
        IOptionSettlementEngine.Option memory option = IOptionSettlementEngine
            .Option({
                underlyingAsset: WETH_A,
                exerciseAsset: WETH_A,
                settlementSeed: 1234567,
                underlyingAmount: testUnderlyingAmount,
                exerciseAmount: testExerciseAmount,
                exerciseTimestamp: testExerciseTimestamp,
                expiryTimestamp: testExpiryTimestamp - 1
            });
        vm.expectRevert(IOptionSettlementEngine.ExerciseWindowTooShort.selector);
        engine.newChain(option);
    }

    // TODO: this test doesn't pass
    // function testFail_newChain_InvalidAssets() public {
    //     IOptionSettlementEngine.Option memory option = IOptionSettlementEngine
    //         .Option({
    //             underlyingAsset: DAI_A,
    //             exerciseAsset: DAI_A,
    //             settlementSeed: 1234567,
    //             underlyingAmount: testUnderlyingAmount,
    //             exerciseAmount: testExerciseAmount,
    //             exerciseTimestamp: testExerciseTimestamp,
    //             expiryTimestamp: testExpiryTimestamp
    //         });
    //     vm.expectRevert(IOptionSettlementEngine.InvalidAssets.selector);
    //     engine.newChain(option);
    // }


    function testFail_assignExercise() public {
        // Exercise an option before anyone has written it        
        vm.expectRevert(IOptionSettlementEngine.NoClaims.selector);
        engine.exercise(testOptionId, 1);
    }

    function testFail_write_InvalidOption() public {
        vm.expectRevert(IOptionSettlementEngine.InvalidOption.selector);
        engine.write(testOptionId + 1, 1);
    }

    function testFail_write_ExpiredOption() public {
        vm.warp(testExpiryTimestamp);
        vm.expectRevert(IOptionSettlementEngine.ExpiredOption.selector);
    }
    
    function testFail_exercise_BeforeExcercise() public {
        IOptionSettlementEngine.Option memory option = IOptionSettlementEngine
            .Option({
                underlyingAsset: WETH_A,
                exerciseAsset: WETH_A,
                settlementSeed: 1234567,
                underlyingAmount: testUnderlyingAmount,
                exerciseAmount: testExerciseAmount,
                exerciseTimestamp: testExerciseTimestamp + 1,
                expiryTimestamp: testExpiryTimestamp + 1
            });
        uint256 badOptionId = engine.newChain(option);

        // Alice writes
        vm.startPrank(ALICE);
        engine.write(badOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, badOptionId, 1, "");
        vm.stopPrank();

        // Bob immediately exercises before exerciseTimestamp
        vm.startPrank(BOB);
        vm.expectRevert(IOptionSettlementEngine.ExpiredOption.selector);
        engine.exercise(badOptionId, 1);
        vm.stopPrank();
    }

    function testFail_exercise_AtExpiry() public {
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        // Fast-forward to at expiry
        vm.warp(testExpiryTimestamp);
    
        // Bob exercises
        vm.startPrank(BOB);
        vm.expectRevert(IOptionSettlementEngine.ExpiredOption.selector);
        engine.exercise(testOptionId, 1);
        vm.stopPrank();
    }

    function testFail_exercise_ExpiredOption() public {
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        // Fast-forward to after expiry
        vm.warp(testExpiryTimestamp + 1);
    
        // Bob exercises
        vm.startPrank(BOB);
        vm.expectRevert(IOptionSettlementEngine.ExpiredOption.selector);
        engine.exercise(testOptionId, 1);
        vm.stopPrank();
    }

    function testFail_redeem_InvalidClaim() public {
        vm.startPrank(ALICE);
        vm.expectRevert(IOptionSettlementEngine.InvalidClaim.selector);
        engine.redeem(69);
    }

    function testFail_redeem_BalanceTooLow() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);
        vm.stopPrank();
        vm.startPrank(BOB);
        vm.expectRevert(IOptionSettlementEngine.BalanceTooLow.selector);
        engine.redeem(claimId);
    }

    function testFail_redeem_AlreadyClaimed() public {
        vm.startPrank(ALICE);
        uint256 claimId1 = engine.write(testOptionId, 1);
        uint256 claimId2 = engine.write(testOptionId, 1);
    }
}
