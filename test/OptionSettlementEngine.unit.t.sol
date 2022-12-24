// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

import "solmate/utils/FixedPointMathLib.sol";
import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "./utils/BaseEngineTest.sol";

contract OptionSettlementUnitTest is BaseEngineTest {
    /*//////////////////////////////////////////////////////////////
    //  function option(uint256 tokenId) external view returns (Option memory optionInfo)
    //////////////////////////////////////////////////////////////*/

    function test_option_returnsOptionInfo() public {
        IOptionSettlementEngine.Option memory optionInfo = engine.option(testOptionId);
        assertEq(optionInfo.underlyingAsset, testUnderlyingAsset);
        assertEq(optionInfo.underlyingAmount, testUnderlyingAmount);
        assertEq(optionInfo.exerciseAsset, testExerciseAsset);
        assertEq(optionInfo.exerciseAmount, testExerciseAmount);
        assertEq(optionInfo.exerciseTimestamp, testExerciseTimestamp);
        assertEq(optionInfo.expiryTimestamp, testExpiryTimestamp);
    }

    // Negative behavior

    function testRevert_option_whenOptionDoesNotExist() public {
        uint256 badOptionId = 123;
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, badOptionId));
        engine.option(badOptionId);
    }

    /*//////////////////////////////////////////////////////////////
    //  function claim(uint256 claimId) external view returns (Claim memory claimInfo)
    //////////////////////////////////////////////////////////////*/

    function test_claim_whenWrittenOnce() public {
        uint112 amountWritten = 69;
        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);

        IOptionSettlementEngine.Claim memory claim = engine.claim(claimId);
        assertEq(claim.amountWritten, amountWritten * WAD);
        assertEq(claim.amountExercised, 0);
        assertEq(claim.optionId, testOptionId);
        // TODO(Why do we need this if claim() reverts when it does not exist?) See L64 below
        assertEq(claim.unredeemed, true);

        vm.warp(testOption.exerciseTimestamp);
        vm.prank(ALICE);
        engine.exercise(testOptionId, 1);

        claim = engine.claim(claimId);
        assertEq(claim.amountWritten, amountWritten * WAD);
        assertEq(claim.amountExercised, 1 * WAD);
        assertEq(claim.optionId, testOptionId);

        vm.warp(testOption.exerciseTimestamp);
        vm.prank(ALICE);
        engine.exercise(testOptionId, 68);

        claim = engine.claim(claimId);
        assertEq(claim.amountWritten, amountWritten * WAD);
        assertEq(claim.amountExercised, amountWritten * WAD);
        assertEq(claim.optionId, testOptionId);

        vm.warp(testOption.expiryTimestamp);
        vm.prank(ALICE);
        engine.redeem(claimId);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, claimId));
        claim = engine.claim(claimId);
    }

    function test_claim_whenWrittenMultiple() public {
        uint112 amountWritten = 69;
        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);

        IOptionSettlementEngine.Claim memory claim = engine.claim(claimId);
        assertEq(claim.amountWritten, amountWritten * WAD);
        assertEq(claim.amountExercised, 0);
        assertEq(claim.optionId, testOptionId);

        vm.warp(testOption.exerciseTimestamp);
        vm.prank(ALICE);
        engine.exercise(testOptionId, 1);

        claim = engine.claim(claimId);
        assertEq(claim.amountWritten, amountWritten * WAD);
        assertEq(claim.amountExercised, 1 * WAD);
        assertEq(claim.optionId, testOptionId);

        vm.prank(ALICE);
        engine.write(claimId, amountWritten);

        claim = engine.claim(claimId);
        assertEq(claim.amountWritten, amountWritten * 2 * WAD);
        assertEq(claim.amountExercised, 1 * WAD);
        assertEq(claim.optionId, testOptionId);

        vm.prank(ALICE);
        engine.exercise(testOptionId, 137);

        claim = engine.claim(claimId);
        assertEq(claim.amountWritten, amountWritten * 2 * WAD);
        assertEq(claim.amountExercised, amountWritten * 2 * WAD);
        assertEq(claim.optionId, testOptionId);

        vm.warp(testOption.expiryTimestamp);
        vm.prank(ALICE);
        engine.redeem(claimId);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, claimId));
        claim = engine.claim(claimId);
    }

    function test_claim_whenWrittenMultipleTimesOnMultipleClaims() public {
        vm.startPrank(ALICE);

        uint256 claimId1 = engine.write(testOptionId, 1);
        IOptionSettlementEngine.Claim memory claim1 = engine.claim(claimId1);
        assertEq(claim1.amountWritten, WAD);
        assertEq(claim1.amountExercised, 0);

        uint256 claimId2 = engine.write(testOptionId, 1);
        IOptionSettlementEngine.Claim memory claim2 = engine.claim(claimId2);
        assertEq(claim1.amountWritten, WAD);
        assertEq(claim1.amountExercised, 0);
        assertEq(claim2.amountWritten, WAD);
        assertEq(claim2.amountExercised, 0);

        engine.write(claimId2, 1);
        claim2 = engine.claim(claimId2);
        assertEq(claim1.amountWritten, WAD);
        assertEq(claim1.amountExercised, 0);
        assertEq(claim2.amountWritten, 2 * WAD);
        assertEq(claim2.amountExercised, 0);

        vm.warp(testExerciseTimestamp);

        engine.exercise(testOptionId, 2);
        claim1 = engine.claim(claimId1);
        claim2 = engine.claim(claimId2);
        assertEq(claim1.amountWritten, WAD);
        // exercised ratio in the bucket is 2/3
        assertEq(
            // 1 option is written in this claim, two options are exercised in the bucket, and in
            // total, 3 options are written
            claim1.amountExercised,
            FixedPointMathLib.divWadDown(1 * 2, 3)
        );
        assertEq(claim2.amountWritten, 2 * WAD);
        assertEq(
            // 2 options are written in this claim, two options are exercised in the bucket, and in
            // total, 3 options are written
            claim2.amountExercised,
            FixedPointMathLib.divWadDown(2 * 2, 3)
        );
    }

    // Negative behavior

    function testRevert_claim_whenClaimDoesNotExist() public {
        uint256 badClaimId = testOptionId + 69;
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, badClaimId));
        engine.claim(badClaimId);
    }

    /*//////////////////////////////////////////////////////////////
    //  function position(uint256 tokenId) external view returns (Position memory positionInfo);
    //////////////////////////////////////////////////////////////*/

    function test_position_whenOption() public {
        IOptionSettlementEngine.Position memory position = engine.position(testOptionId);
        assertEq(position.underlyingAsset, testUnderlyingAsset);
        assertEq(position.underlyingAmount, int256(uint256(testUnderlyingAmount)));
        assertEq(position.exerciseAsset, testExerciseAsset);
        assertEq(position.exerciseAmount, -int256(uint256(testExerciseAmount)));

        vm.warp(testOption.expiryTimestamp);
        // The token is now expired/worthless, and this should revert.
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );
        position = engine.position(testOptionId);
    }

    function test_position_whenUnexercisedClaim() public {
        uint112 amountWritten = 69;
        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);

        IOptionSettlementEngine.Position memory position = engine.position(claimId);
        assertEq(position.underlyingAsset, testUnderlyingAsset);
        assertEq(position.underlyingAmount, int256(uint256(testUnderlyingAmount) * amountWritten));
        assertEq(position.exerciseAsset, testExerciseAsset);
        assertEq(position.exerciseAmount, int256(0));
    }

    function test_position_whenPartiallyExercisedClaim() public {
        uint112 amountWritten = 69;
        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);

        vm.prank(ALICE);
        engine.exercise(testOptionId, 1);

        vm.prank(ALICE);
        engine.write(claimId, amountWritten);

        amountWritten = amountWritten * 2;

        IOptionSettlementEngine.Position memory position = engine.position(claimId);
        assertEq(position.underlyingAsset, testUnderlyingAsset);
        assertEq(
            position.underlyingAmount,
            int256(uint256((amountWritten - 1) * testUnderlyingAmount * amountWritten) / amountWritten)
        );
        assertEq(position.exerciseAsset, testExerciseAsset);
        assertEq(position.exerciseAmount, int256(uint256(1 * testExerciseAmount * amountWritten) / amountWritten));
    }

    function test_position_whenFullyExercisedClaim() public {
        uint112 amountWritten = 69;
        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);

        vm.prank(ALICE);
        engine.exercise(testOptionId, amountWritten);

        IOptionSettlementEngine.Position memory position = engine.position(claimId);
        assertEq(position.underlyingAsset, testUnderlyingAsset);
        assertEq(position.underlyingAmount, int256(uint256(0)));
        assertEq(position.exerciseAsset, testExerciseAsset);
        assertEq(position.exerciseAmount, int256(uint256(amountWritten * testExerciseAmount)));
    }

    // Negative behavior

    function testRevert_position_whenTokenNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, 1));
        engine.position(1);
    }

    function testRevert_position_whenExpiredOption() public {
        vm.warp(testExpiryTimestamp);
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );
        engine.position(testOptionId);
    }

    /*//////////////////////////////////////////////////////////////
    //  function tokenType(uint256 tokenId) external view returns (TokenType typeOfToken)
    //////////////////////////////////////////////////////////////*/

    function test_tokenType_returnsNone() public {
        _assertTokenIsNone(127);
    }

    function test_tokenType_returnsOption() public {
        _assertTokenIsOption(testOptionId);
    }

    function test_tokenType_returnsClaim() public {
        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);
        _assertTokenIsClaim(claimId);
    }

    /*//////////////////////////////////////////////////////////////
    //  function tokenURIGenerator() external view returns (ITokenURIGenerator uriGenerator)
    //////////////////////////////////////////////////////////////*/

    function test_tokenURIGenerator() public view {
        assertEq(address(engine.tokenURIGenerator()), address(generator));
    }

    /*//////////////////////////////////////////////////////////////
    //  function feeBalance(address token) external view returns (uint256)
    //////////////////////////////////////////////////////////////*/

    function test_feeBalance_whenFeeOn() public {
        assertEq(engine.feeBalance(testUnderlyingAsset), 0);
        assertEq(engine.feeBalance(testExerciseAsset), 0);

        vm.prank(ALICE);
        engine.write(testOptionId, 2);

        // Fee is recorded on the exercise asset
        uint256 underlyingAmount = 2 * testUnderlyingAmount;
        uint256 underlyingFee = (underlyingAmount * engine.feeBps()) / 10_000;
        assertEq(engine.feeBalance(address(WETHLIKE)), underlyingFee);

        vm.prank(ALICE);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 2, "");

        // Bob exercises 2
        vm.warp(testExerciseTimestamp);
        vm.prank(BOB);
        engine.exercise(testOptionId, 2);

        // Fee is recorded on the exercise asset
        uint256 exerciseAmount = 2 * testExerciseAmount;
        uint256 exerciseFee = (exerciseAmount * engine.feeBps()) / 10_000;
        assertEq(engine.feeBalance(address(DAILIKE)), exerciseFee);
    }

    function test_feeBalance_whenFeeOff() public {
        assertEq(engine.feeBalance(testUnderlyingAsset), 0);
        assertEq(engine.feeBalance(testExerciseAsset), 0);

        vm.prank(FEE_TO);
        engine.setFeesEnabled(false);

        vm.prank(ALICE);
        engine.write(testOptionId, 2);

        assertEq(engine.feeBalance(address(WETHLIKE)), 0);

        vm.prank(ALICE);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 2, "");

        // Bob exercises 2
        vm.warp(testExerciseTimestamp);
        vm.prank(BOB);
        engine.exercise(testOptionId, 2);

        assertEq(engine.feeBalance(address(DAILIKE)), 0);
    }

    function test_feeBalance_whenMinimum() public {
        vm.startPrank(ALICE);
        uint256 optionId = engine.newOptionType(
            address(ERC20A), 1, address(ERC20B), 15, uint40(block.timestamp), uint40(block.timestamp + 30 days)
        );
        engine.write(optionId, 1);
        assertEq(engine.feeBalance(address(ERC20A)), 1);

        engine.safeTransferFrom(ALICE, BOB, optionId, 1, "");
        vm.stopPrank();

        // Warp right before expiry time and Bob exercises
        vm.warp(block.timestamp + 30 days - 1 seconds);
        vm.prank(BOB);
        engine.exercise(optionId, 1);

        // Check balances after exercise
        assertEq(engine.feeBalance(address(ERC20B)), 1);
    }

    /*//////////////////////////////////////////////////////////////
    //  function feeBps() external view returns (uint8 fee)
    //////////////////////////////////////////////////////////////*/

    function test_feeBps() public {
        assertEq(engine.feeBps(), 5);
    }

    /*//////////////////////////////////////////////////////////////
    //  function feesEnabled() external view returns (bool enabled)
    //////////////////////////////////////////////////////////////*/

    function test_feesEnabled() public {
        assertEq(engine.feesEnabled(), true);
    }

    /*//////////////////////////////////////////////////////////////
    //  function feeTo() external view returns (address)
    //////////////////////////////////////////////////////////////*/

    function test_feeTo() public {
        assertEq(engine.feeTo(), FEE_TO);
    }

    /*//////////////////////////////////////////////////////////////
    // function newOptionType(
    //        address underlyingAsset,
    //        uint96 underlyingAmount,
    //        address exerciseAsset,
    //        uint96 exerciseAmount,
    //        uint40 exerciseTimestamp,
    //        uint40 expiryTimestamp
    //    ) external returns (uint256 optionId)
    //////////////////////////////////////////////////////////////*/

    function test_newOptionType() public {
        IOptionSettlementEngine.Option memory optionInfo = IOptionSettlementEngine.Option({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(WETHLIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp,
            settlementSeed: 0,
            nextClaimKey: 0
        });

        uint256 expectedOptionId = _createOptionIdFromStruct(optionInfo);

        vm.expectEmit(true, true, true, true);
        emit NewOptionType(
            expectedOptionId,
            address(WETHLIKE),
            address(DAILIKE),
            testExerciseAmount,
            testUnderlyingAmount,
            testExerciseTimestamp,
            testExpiryTimestamp
            );

        engine.newOptionType(
            address(DAILIKE),
            testUnderlyingAmount,
            address(WETHLIKE),
            testExerciseAmount,
            testExerciseTimestamp,
            testExpiryTimestamp
        );
    }

    // Negative behavior

    function testRevert_newOptionType_whenOptionsTypeExists() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.OptionsTypeExists.selector, testOptionId));
        _createNewOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
    }

    function testRevert_newOptionType_whenExpiryWindowTooShort() public {
        uint40 tooSoonExpiryTimestamp = uint40(block.timestamp + 1 days - 1 seconds);
        IOptionSettlementEngine.Option memory option = IOptionSettlementEngine.Option({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(WETHLIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: uint40(block.timestamp),
            expiryTimestamp: tooSoonExpiryTimestamp,
            settlementSeed: 0, // default zero for settlement seed
            nextClaimKey: 0 // default zero for next claim id
        });
        _createOptionIdFromStruct(option);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiryWindowTooShort.selector, testExpiryTimestamp - 1)
        );
        engine.newOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp - 1
        });
    }

    function testRevert_newOptionType_whenExerciseWindowTooShort() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExerciseWindowTooShort.selector, uint40(block.timestamp + 1))
        );
        engine.newOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: uint40(block.timestamp + 1),
            expiryTimestamp: testExpiryTimestamp
        });
    }

    function testRevert_newOptionType_whenInvalidAssets() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.InvalidAssets.selector, address(DAILIKE), address(DAILIKE))
        );
        engine.newOptionType({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
    }

    function testRevert_newOptionType_whenTotalSuppliesAreTooLowToExercise() public {
        uint96 underlyingAmountExceedsTotalSupply = uint96(DAILIKE.totalSupply() + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.InvalidAssets.selector, address(DAILIKE), address(WETHLIKE))
        );

        engine.newOptionType({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: underlyingAmountExceedsTotalSupply,
            exerciseAsset: address(WETHLIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });

        uint96 exerciseAmountExceedsTotalSupply = uint96(USDCLIKE.totalSupply() + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.InvalidAssets.selector, address(USDCLIKE), address(WETHLIKE))
        );

        engine.newOptionType({
            underlyingAsset: address(USDCLIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(WETHLIKE),
            exerciseAmount: exerciseAmountExceedsTotalSupply,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
    }

    /*//////////////////////////////////////////////////////////////
    // function write(uint256 tokenId, uint112 amount) external returns (uint256 claimId)
    //////////////////////////////////////////////////////////////*/

    function test_write_whenNewClaim() public {
        uint112 amountWritten = 5;
        uint256 expectedFee = _calculateFee(testUnderlyingAmount * amountWritten);

        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(testOptionId, testUnderlyingAsset, ALICE, expectedFee);

        vm.expectEmit(true, true, true, true);
        emit OptionsWritten(testOptionId, ALICE, testOptionId + 1, amountWritten);

        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);

        assertEq(claimId, testOptionId + 1, "claimId");
        assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice Claim NFT"); // 1 Claim NFT
        assertEq(engine.balanceOf(ALICE, testOptionId), amountWritten, "Alice Option tokens"); // 5 fungible Option tokens
        assertEq(
            IERC20(testUnderlyingAsset).balanceOf(ALICE),
            STARTING_BALANCE_WETH - (testUnderlyingAmount * amountWritten) - expectedFee,
            "Alice underlying"
        );
        assertEq(IERC20(testExerciseAsset).balanceOf(ALICE), STARTING_BALANCE, "Alice exercise"); // no change
        assertEq(engine.feeBalance(testUnderlyingAsset), expectedFee, "Fee balance underlying");
        assertEq(engine.feeBalance(testExerciseAsset), 0, "Fee balance exercise"); // no fee assessed on exercise asset during write()
    }

    function test_write_whenExistingClaim() public {
        // Alice writes 1 option
        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);

        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(testOptionId, testUnderlyingAsset, ALICE, _calculateFee(testUnderlyingAmount * 5));

        vm.expectEmit(true, true, true, true);
        emit OptionsWritten(testOptionId, ALICE, claimId, 5);

        // Alice writes 5 more options on existing claim
        vm.prank(ALICE);
        uint256 existingClaimId = engine.write(claimId, 5);

        uint256 expectedFee = _calculateFee(testUnderlyingAmount * 6);
        assertEq(existingClaimId, claimId, "claimId"); // same Claim NFT tokenId
        assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice Claim NFT"); // still just 1 Claim NFT
        assertEq(engine.balanceOf(ALICE, testOptionId), 6, "Alice Option tokens"); // 6 fungible Option tokens
        assertEq(
            IERC20(testUnderlyingAsset).balanceOf(ALICE),
            STARTING_BALANCE_WETH - (testUnderlyingAmount * 6) - expectedFee,
            "Alice underlying"
        );
        assertEq(IERC20(testExerciseAsset).balanceOf(ALICE), STARTING_BALANCE, "Alice exercise"); // no change
        assertEq(engine.feeBalance(testUnderlyingAsset), expectedFee, "Fee balance underlying");
        assertEq(engine.feeBalance(testExerciseAsset), 0, "Fee balance exercise"); // no fee assessed on exercise asset during write()
    }

    function test_write_whenFeeOff() public {
        vm.prank(FEE_TO);
        engine.setFeesEnabled(false);

        vm.expectEmit(true, true, true, true);
        emit OptionsWritten(testOptionId, ALICE, testOptionId + 1, 5);

        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, 5);

        assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice Claim NFT");
        assertEq(engine.balanceOf(ALICE, testOptionId), 5, "Alice Option tokens");
        assertEq(
            IERC20(testUnderlyingAsset).balanceOf(ALICE),
            STARTING_BALANCE_WETH - (testUnderlyingAmount * 5), // no fee assessed when fee is off
            "Alice underlying"
        );
        assertEq(engine.feeBalance(testUnderlyingAsset), 0, "Fee balance underlying"); // no fee assessed when fee is off
        // sanity check on additional balance assertions when fee is off
        assertEq(claimId, testOptionId + 1, "claimId");
        assertEq(IERC20(testExerciseAsset).balanceOf(ALICE), STARTING_BALANCE, "Alice exercise");
        assertEq(engine.feeBalance(testExerciseAsset), 0, "Fee balance exercise");
    }

    // Negative behavior

    function testRevert_write_whenAmountWrittenCannotBeZero() public {
        uint112 invalidWriteAmount = 0;

        vm.expectRevert(IOptionSettlementEngine.AmountWrittenCannotBeZero.selector);

        engine.write(testOptionId, invalidWriteAmount);
    }

    function testRevert_write_whenInvalidOption() public {
        // Option ID not 0 in lower 96 b
        uint256 invalidOptionId = testOptionId + 1;
        // Option ID not initialized
        invalidOptionId = encodeTokenId(0x1, 0x0);
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidOption.selector, invalidOptionId));
        engine.write(invalidOptionId, 1);
    }

    function testRevert_write_whenExpiredOption() public {
        vm.warp(testExpiryTimestamp + 1 seconds);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );

        vm.prank(ALICE);
        engine.write(testOptionId, 1);
    }

    function testRevert_write_whenCallerDoesNotOwnClaimId() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.CallerDoesNotOwnClaimId.selector, claimId));

        vm.prank(BOB);
        engine.write(claimId, 1);
    }

    function testRevert_write_whenCallerHoldsInsufficientExerciseAsset() public {
        uint112 amountWritten = 5;

        uint256 optionId = engine.newOptionType({
            underlyingAsset: address(ERC20A),
            underlyingAmount: 1 ether,
            exerciseAsset: address(ERC20B),
            exerciseAmount: 8 ether,
            exerciseTimestamp: uint40(block.timestamp),
            expiryTimestamp: uint40(block.timestamp + 30 days)
        });

        // Approve engine up to max on underlying asset
        address other = address(0xBABE);
        vm.startPrank(other);
        ERC20A.approve(address(engine), type(uint256).max);

        // Check revert when Option Writer has zero underlying asset
        vm.expectRevert("TRANSFER_FROM_FAILED");
        engine.write(optionId, amountWritten);

        uint256 expectedFee = _calculateFee(1 ether) * amountWritten;

        // Check revert when Option Writer has some, but less than required
        _mint(other, MockERC20(address(ERC20A)), (1 ether * amountWritten) + expectedFee - 1);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        engine.write(optionId, amountWritten);

        // Finally, the positive case -- mint 1 more and write should succeed
        _mint(other, MockERC20(address(ERC20A)), 1);
        uint256 claimId = engine.write(optionId, amountWritten);
        vm.stopPrank();

        assertEq(engine.balanceOf(other, claimId), 1, "Other claim NFT");
        assertEq(engine.balanceOf(other, optionId), amountWritten, "Other option tokens");
    }

    function testRevert_write_whenCallerHasNotGrantedSufficientApprovalToEngine() public {
        uint112 amountWritten = 5;

        uint256 optionId = engine.newOptionType({
            underlyingAsset: address(ERC20A),
            underlyingAmount: 1 ether,
            exerciseAsset: address(ERC20B),
            exerciseAmount: 8 ether,
            exerciseTimestamp: uint40(block.timestamp),
            expiryTimestamp: uint40(block.timestamp + 30 days)
        });

        // Mint Other 1000 tokens of underlying asset
        address other = address(0xBABE);
        _mint(other, MockERC20(address(ERC20A)), 1000 ether);

        // Check revert when Option Writer has granted zero approval
        vm.expectRevert("TRANSFER_FROM_FAILED");
        vm.startPrank(other);
        engine.write(optionId, amountWritten);

        uint256 expectedFee = _calculateFee(1 ether) * amountWritten;

        // Check revert when Option Writer has granted some approval, but less than required
        ERC20A.approve(address(engine), (1 ether * amountWritten) + expectedFee - 1);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        engine.write(optionId, amountWritten);

        // Finally, the positive case -- approve 1 more and write should pass
        ERC20A.approve(address(engine), (1 ether * amountWritten) + expectedFee);
        uint256 claimId = engine.write(optionId, amountWritten);
        vm.stopPrank();

        assertEq(engine.balanceOf(other, claimId), 1, "Other claim NFT");
        assertEq(engine.balanceOf(other, optionId), amountWritten, "Other option tokens");
    }

    /*//////////////////////////////////////////////////////////////
    // function redeem(uint256 claimId) external
    //////////////////////////////////////////////////////////////*/

    function test_redeem_whenUnexercised() public {
        uint112 amountWritten = 7;
        uint256 expectedUnderlyingAmount = testUnderlyingAmount * amountWritten;
        uint256 expectedUnderlyingFee = _calculateFee(expectedUnderlyingAmount);

        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);

        // Precondition checks
        assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice claim NFT pre redeem");
        assertEq(engine.balanceOf(ALICE, testOptionId), 7, "Alice option tokens pre redeem");
        assertEq(
            WETHLIKE.balanceOf(ALICE),
            STARTING_BALANCE_WETH - expectedUnderlyingAmount - expectedUnderlyingFee,
            "Alice underlying pre redeem"
        );
        assertEq(DAILIKE.balanceOf(ALICE), STARTING_BALANCE, "Alice exercise pre redeem");

        vm.warp(testExpiryTimestamp);

        vm.expectEmit(true, true, true, true);
        emit ClaimRedeemed({
            claimId: claimId,
            optionId: testOptionId,
            redeemer: ALICE,
            exerciseAmountRedeemed: 0,
            underlyingAmountRedeemed: expectedUnderlyingAmount
        });

        vm.prank(ALICE);
        engine.redeem(claimId);

        // Check balances after redeem
        assertEq(engine.balanceOf(ALICE, claimId), 0, "Alice claim NFT post redeem"); // Claim NFT has been burned
        assertEq(engine.balanceOf(ALICE, testOptionId), 7, "Alice option tokens post redeem"); // no change
        assertEq(
            WETHLIKE.balanceOf(ALICE), STARTING_BALANCE_WETH - expectedUnderlyingFee, "Alice underlying post redeem"
        ); // gets all underlying back
        assertEq(DAILIKE.balanceOf(ALICE), STARTING_BALANCE, "Alice exercise post redeem"); // no change
    }

    function test_redeem_whenPartiallyExercised() public {
        uint112 amountWritten = 7;
        uint112 amountExercised = 3;
        uint256 expectedUnderlyingFee = _calculateFee(testUnderlyingAmount);
        uint256 expectedExerciseFee = _calculateFee(testExerciseAmount);

        // Alice writes 7 and transfers 3 to Bob
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, amountExercised, "");
        vm.stopPrank();

        // Bob exercises 3
        vm.warp(testExerciseTimestamp);
        vm.prank(BOB);
        engine.exercise(testOptionId, amountExercised);

        // Precondition checks
        assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice claim NFT pre redeem");
        assertEq(
            engine.balanceOf(ALICE, testOptionId), amountWritten - amountExercised, "Alice option tokens pre redeem"
        );
        assertEq(
            WETHLIKE.balanceOf(ALICE),
            STARTING_BALANCE_WETH - (testUnderlyingAmount * amountWritten) - (expectedUnderlyingFee * amountWritten),
            "Alice underlying pre redeem"
        );
        assertEq(DAILIKE.balanceOf(ALICE), STARTING_BALANCE, "Alice exercise pre redeem"); // none of the exercise asset yet (until she redeems her claim)
        assertEq(engine.balanceOf(BOB, testOptionId), 0, "Bob option tokens pre redeem"); // all 3 options have been burned
        assertEq(
            WETHLIKE.balanceOf(BOB),
            STARTING_BALANCE_WETH + (testUnderlyingAmount * amountExercised),
            "Bob underlying pre redeem"
        );
        assertEq(
            DAILIKE.balanceOf(BOB),
            STARTING_BALANCE - (testExerciseAmount * amountExercised) - (expectedExerciseFee * amountExercised),
            "Bob exercise pre redeem"
        );

        vm.warp(testExpiryTimestamp);

        vm.expectEmit(true, true, true, true);
        emit ClaimRedeemed({
            claimId: claimId,
            optionId: testOptionId,
            redeemer: ALICE,
            exerciseAmountRedeemed: testExerciseAmount * amountExercised,
            underlyingAmountRedeemed: testUnderlyingAmount * (amountWritten - amountExercised)
        });

        vm.prank(ALICE);
        engine.redeem(claimId);

        // Check balances after redeem
        assertEq(engine.balanceOf(ALICE, claimId), 0, "Alice claim NFT post redeem"); // Claim NFT has been burned
        assertEq(
            engine.balanceOf(ALICE, testOptionId), amountWritten - amountExercised, "Alice option tokens post redeem"
        ); // no change
        assertEq(
            WETHLIKE.balanceOf(ALICE),
            STARTING_BALANCE_WETH - (testUnderlyingAmount * amountExercised) - (expectedUnderlyingFee * amountWritten),
            "Alice underlying post redeem"
        ); // gets back underlying for options written, less options exercised
        assertEq(
            DAILIKE.balanceOf(ALICE),
            STARTING_BALANCE + (testExerciseAmount * amountExercised),
            "Alice exercise post redeem"
        );
        assertEq(engine.balanceOf(BOB, testOptionId), 0, "Bob option tokens post redeem"); // no change
        assertEq(
            WETHLIKE.balanceOf(BOB),
            STARTING_BALANCE_WETH + (testUnderlyingAmount * amountExercised),
            "Bob underlying post redeem"
        );
        assertEq(
            DAILIKE.balanceOf(BOB),
            STARTING_BALANCE - (testExerciseAmount * amountExercised) - (expectedExerciseFee * amountExercised),
            "Bob exercise post redeem"
        );
    }

    function test_redeem_whenFullyExercised() public {
        uint112 amountWritten = 7;
        uint112 amountExercised = 7;
        uint256 expectedUnderlyingFee = _calculateFee(testUnderlyingAmount);
        uint256 expectedExerciseFee = _calculateFee(testExerciseAmount);

        // Alice writes 7 and transfers 7 to Bob
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, amountExercised, "");
        vm.stopPrank();

        // Bob exercises 7
        vm.warp(testExerciseTimestamp);
        vm.prank(BOB);
        engine.exercise(testOptionId, amountExercised);

        // Precondition checks
        assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice claim NFT pre redeem");
        assertEq(engine.balanceOf(ALICE, testOptionId), 0, "Alice option tokens pre redeem");
        assertEq(
            WETHLIKE.balanceOf(ALICE),
            STARTING_BALANCE_WETH - (testUnderlyingAmount * amountWritten) - (expectedUnderlyingFee * amountWritten),
            "Alice underlying pre redeem"
        );
        assertEq(DAILIKE.balanceOf(ALICE), STARTING_BALANCE, "Alice exercise pre redeem"); // none of the exercise asset yet (until she redeems her claim)
        assertEq(engine.balanceOf(BOB, testOptionId), 0, "Bob option tokens pre redeem"); // all 3 options have been burned
        assertEq(
            WETHLIKE.balanceOf(BOB),
            STARTING_BALANCE_WETH + (testUnderlyingAmount * amountExercised),
            "Bob underlying pre redeem"
        );
        assertEq(
            DAILIKE.balanceOf(BOB),
            STARTING_BALANCE - (testExerciseAmount * amountExercised) - (expectedExerciseFee * amountExercised),
            "Bob exercise pre redeem"
        );

        vm.warp(testExpiryTimestamp);

        vm.expectEmit(true, true, true, true);
        emit ClaimRedeemed({
            claimId: claimId,
            optionId: testOptionId,
            redeemer: ALICE,
            exerciseAmountRedeemed: testExerciseAmount * amountExercised,
            underlyingAmountRedeemed: testUnderlyingAmount * (amountWritten - amountExercised)
        });

        vm.prank(ALICE);
        engine.redeem(claimId);

        // Check balances after redeem
        assertEq(engine.balanceOf(ALICE, claimId), 0, "Alice claim NFT post redeem"); // Claim NFT has been burned
        assertEq(engine.balanceOf(ALICE, testOptionId), 0, "Alice option tokens post redeem"); // no change
        assertEq(
            WETHLIKE.balanceOf(ALICE),
            STARTING_BALANCE_WETH - (testUnderlyingAmount * amountExercised) - (expectedUnderlyingFee * amountWritten),
            "Alice underlying post redeem"
        ); // gets back underlying for options written, less options exercised
        assertEq(
            DAILIKE.balanceOf(ALICE),
            STARTING_BALANCE + (testExerciseAmount * amountExercised),
            "Alice exercise post redeem"
        );
        assertEq(engine.balanceOf(BOB, testOptionId), 0, "Bob option tokens post redeem"); // no change
        assertEq(
            WETHLIKE.balanceOf(BOB),
            STARTING_BALANCE_WETH + (testUnderlyingAmount * amountExercised),
            "Bob underlying post redeem"
        );
        assertEq(
            DAILIKE.balanceOf(BOB),
            STARTING_BALANCE - (testExerciseAmount * amountExercised) - (expectedExerciseFee * amountExercised),
            "Bob exercise post redeem"
        );
    }

    // Negative behavior

    function testRevert_redeem_whenInvalidClaim() public {
        uint256 badClaimId = encodeTokenId(0xDEADBEEF, 0);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidClaim.selector, badClaimId));

        vm.prank(ALICE);
        engine.redeem(badClaimId);
    }

    function testRevert_redeem_whenCallerDoesNotOwnClaimId() public {
        // Alice writes and transfers to Bob, then Alice tries to redeem
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, claimId, 1, "");

        vm.warp(testExpiryTimestamp);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.CallerDoesNotOwnClaimId.selector, claimId));

        engine.redeem(claimId);
        vm.stopPrank();

        // Carol feels left out and tries to redeem what she can't
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.CallerDoesNotOwnClaimId.selector, claimId));

        vm.prank(CAROL);
        engine.redeem(claimId);

        // Bob redeems, which burns the Claim NFT, and then is unable to redeem a second time
        vm.startPrank(BOB);
        engine.redeem(claimId);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.CallerDoesNotOwnClaimId.selector, claimId));

        engine.redeem(claimId);
        vm.stopPrank();
    }

    function testRevert_redeem_whenClaimTooSoon() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);

        vm.warp(testExerciseTimestamp - 1 seconds);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ClaimTooSoon.selector, claimId, testExpiryTimestamp)
        );

        engine.redeem(claimId);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
    // function exercise(uint256 optionId, uint112 amount) external
    //////////////////////////////////////////////////////////////*/

    function test_exercise() public {
        // Alice writes 5 and transfers 2 to Bob
        vm.startPrank(ALICE);
        engine.write(testOptionId, 5);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 2, "");
        vm.stopPrank();

        // Balance assertions post-transfer, pre-exercise
        uint256 expectedWriteFee = _calculateFee(testUnderlyingAmount * 5);
        assertEq(
            IERC20(testUnderlyingAsset).balanceOf(ALICE),
            STARTING_BALANCE_WETH - (testUnderlyingAmount * 5) - expectedWriteFee,
            "Alice underlying pre"
        );
        assertEq(IERC20(testExerciseAsset).balanceOf(ALICE), STARTING_BALANCE, "Alice exercise pre");
        assertEq(IERC20(testUnderlyingAsset).balanceOf(BOB), STARTING_BALANCE_WETH, "Bob underlying pre");
        assertEq(IERC20(testExerciseAsset).balanceOf(BOB), STARTING_BALANCE, "Bob exercise pre");
        assertEq(engine.balanceOf(ALICE, testOptionId), 3, "Alice Option tokens pre");
        assertEq(engine.balanceOf(BOB, testOptionId), 2, "Bob Option tokens pre");
        assertEq(engine.feeBalance(testUnderlyingAsset), expectedWriteFee, "Fee balance underlying pre");
        assertEq(engine.feeBalance(testExerciseAsset), 0, "Fee balance exercise pre");

        // Warp to exercise
        vm.warp(testExerciseTimestamp);

        uint256 expectedExerciseFee = _calculateFee(testExerciseAmount * 2);
        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(testOptionId, testExerciseAsset, BOB, expectedExerciseFee);

        vm.expectEmit(true, true, true, true);
        emit OptionsExercised(testOptionId, BOB, 2);

        // Bob exercises 2
        vm.prank(BOB);
        engine.exercise(testOptionId, 2);

        // Balance assertions post-exercise
        assertEq(
            IERC20(testUnderlyingAsset).balanceOf(ALICE),
            STARTING_BALANCE_WETH - (testUnderlyingAmount * 5) - expectedWriteFee,
            "Alice underlying post"
        );
        assertEq(IERC20(testExerciseAsset).balanceOf(ALICE), STARTING_BALANCE, "Alice exercise post"); // no change until Alice redeems her Claim
        assertEq(
            IERC20(testUnderlyingAsset).balanceOf(BOB),
            STARTING_BALANCE_WETH + (testUnderlyingAmount * 2),
            "Bob underlying post"
        );
        assertEq(
            IERC20(testExerciseAsset).balanceOf(BOB),
            STARTING_BALANCE - (testExerciseAmount * 2) - expectedExerciseFee,
            "Bob exercise post"
        );
        assertEq(engine.balanceOf(ALICE, testOptionId), 3, "Alice Option tokens post");
        assertEq(engine.balanceOf(BOB, testOptionId), 0, "Bob Option tokens post"); // Bob's Option tokens are burned
        assertEq(engine.feeBalance(testUnderlyingAsset), expectedWriteFee, "Fee balance underlying post");
        assertEq(engine.feeBalance(testExerciseAsset), expectedExerciseFee, "Fee balance exercise post");
    }

    function test_exercise_whenExercisingMultipleTimes() public {
        // Alice writes 10 and transfers 6 to Bob
        vm.startPrank(ALICE);
        engine.write(testOptionId, 10);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 6, "");
        vm.stopPrank();

        // Warp to exercise
        vm.warp(testExerciseTimestamp);

        uint256 expectedWriteFee = _calculateFee(testUnderlyingAmount * 10);
        uint256 expectedExercise2Fee = _calculateFee(testExerciseAmount * 2);
        uint256 expectedExercise3Fee = _calculateFee(testExerciseAmount * 3);

        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(testOptionId, testExerciseAsset, BOB, expectedExercise2Fee);

        vm.expectEmit(true, true, true, true);
        emit OptionsExercised(testOptionId, BOB, 2);

        // Bob exercises 2
        vm.prank(BOB);
        engine.exercise(testOptionId, 2);

        // Balance assertions after exercising 2
        assertEq(
            IERC20(testUnderlyingAsset).balanceOf(BOB),
            STARTING_BALANCE_WETH + (testUnderlyingAmount * 2),
            "Bob underlying after exercising 2"
        );
        assertEq(
            IERC20(testExerciseAsset).balanceOf(BOB),
            STARTING_BALANCE - (testExerciseAmount * 2) - expectedExercise2Fee,
            "Bob exercise after exercising 2"
        );
        assertEq(engine.balanceOf(BOB, testOptionId), 4, "Bob Option tokens after exercising 2");
        assertEq(engine.feeBalance(testUnderlyingAsset), expectedWriteFee, "Fee balance underlying after exercising 2");
        assertEq(engine.feeBalance(testExerciseAsset), expectedExercise2Fee, "Fee balance exercise after exercising 2");

        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(testOptionId, testExerciseAsset, BOB, expectedExercise3Fee);

        vm.expectEmit(true, true, true, true);
        emit OptionsExercised(testOptionId, BOB, 3);

        // Bob exercises 3 more
        vm.prank(BOB);
        engine.exercise(testOptionId, 3);

        // Balance assertions after exercising 3 more, for a total of 5
        assertEq(
            IERC20(testUnderlyingAsset).balanceOf(BOB),
            STARTING_BALANCE_WETH + (testUnderlyingAmount * 5),
            "Bob underlying after exercising 5"
        );
        assertEq(
            IERC20(testExerciseAsset).balanceOf(BOB),
            STARTING_BALANCE - (testExerciseAmount * 5) - expectedExercise2Fee - expectedExercise3Fee,
            "Bob exercise after exercising 5"
        );
        assertEq(engine.balanceOf(BOB, testOptionId), 1, "Bob Option tokens after exercising 5"); // still 1 left
        assertEq(engine.feeBalance(testUnderlyingAsset), expectedWriteFee, "Fee balance underlying after exercising 5");
        assertEq(
            engine.feeBalance(testExerciseAsset),
            expectedExercise2Fee + expectedExercise3Fee,
            "Fee balance exercise after exercising 5"
        );
    }

    // Negative behavior

    function testRevert_exercise_whenInvalidOption() public {
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);

        uint256 invalidOptionId = testOptionId + 1;

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidOption.selector, invalidOptionId));

        engine.exercise(invalidOptionId, 1);
        vm.stopPrank();
    }

    function testRevert_exercise_whenExpiredOption() public {
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        // Fast-forward to expiry
        vm.warp(testExpiryTimestamp);

        // Bob exercises
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );
        engine.exercise(testOptionId, 1);
        vm.stopPrank();
    }

    function testRevert_exercise_whenExerciseTooEarly() public {
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        vm.warp(testExerciseTimestamp - 1 seconds);

        // Bob immediately exercises before exerciseTimestamp
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOptionSettlementEngine.ExerciseTooEarly.selector, testOptionId, testExerciseTimestamp
            )
        );
        engine.exercise(testOptionId, 1);
        vm.stopPrank();
    }

    function testRevert_exercise_whenCallerHoldsInsufficientOptions() public {
        vm.warp(testExerciseTimestamp + 1 seconds);

        // Should revert if you hold 0
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.CallerHoldsInsufficientOptions.selector, testOptionId, 1)
        );
        engine.exercise(testOptionId, 1);

        // Should revert if you hold some, but not enough
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.CallerHoldsInsufficientOptions.selector, testOptionId, 2)
        );
        engine.exercise(testOptionId, 2);
        vm.stopPrank();
    }

    function testRevert_exercise_whenCallerHoldsInsufficientExerciseAsset() public {
        uint256 optionId = engine.newOptionType({
            underlyingAsset: address(ERC20A),
            underlyingAmount: 1 ether,
            exerciseAsset: address(ERC20B),
            exerciseAmount: 8 ether,
            exerciseTimestamp: uint40(block.timestamp),
            expiryTimestamp: uint40(block.timestamp + 30 days)
        });

        // Approve engine up to max on exercise asset
        address other = address(0xBABE);
        vm.prank(other);
        ERC20B.approve(address(engine), type(uint256).max);

        // Alice writes 5 and transfers 4 to Other
        vm.startPrank(ALICE);
        engine.write(optionId, 5);
        engine.safeTransferFrom(ALICE, other, optionId, 4, "");
        vm.stopPrank();

        // Check revert when Option Holder has zero exercise asset
        vm.expectRevert("TRANSFER_FROM_FAILED");
        vm.startPrank(other);
        engine.exercise(optionId, 3);

        uint256 expectedFee = _calculateFee(8 ether) * 3;

        // Check revert when Option Holder has some, but less than required
        _mint(other, MockERC20(address(ERC20B)), (8 ether * 3) + expectedFee - 1);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        engine.exercise(optionId, 3);

        // Finally, the positive case -- mint 1 more and exercise should succeed
        _mint(other, MockERC20(address(ERC20B)), 1);
        engine.exercise(optionId, 3);
        vm.stopPrank();

        assertEq(engine.balanceOf(other, optionId), 1, "Other option tokens"); // 1 left after 3 are burned on exercise
    }

    function testRevert_exercise_whenCallerHasNotGrantedSufficientApprovalToEngine() public {
        uint256 optionId = engine.newOptionType({
            underlyingAsset: address(ERC20A),
            underlyingAmount: 1 ether,
            exerciseAsset: address(ERC20B),
            exerciseAmount: 8 ether,
            exerciseTimestamp: uint40(block.timestamp),
            expiryTimestamp: uint40(block.timestamp + 30 days)
        });

        // Mint Other 1000 tokens of exercise asset
        address other = address(0xBABE);
        _mint(other, MockERC20(address(ERC20B)), 1000 ether);

        // Alice writes 5 and transfers 4 to Other
        vm.startPrank(ALICE);
        engine.write(optionId, 5);
        engine.safeTransferFrom(ALICE, other, optionId, 4, "");
        vm.stopPrank();

        // Check revert when Option Holder has granted zero approval
        vm.expectRevert("TRANSFER_FROM_FAILED");
        vm.startPrank(other);
        engine.exercise(optionId, 3);

        uint256 expectedFee = _calculateFee(8 ether) * 3;

        // Check revert when Option Holder has granted some approval, but less than required
        ERC20B.approve(address(engine), (8 ether * 3) + expectedFee - 1);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        engine.exercise(optionId, 3);

        // Finally, the positive case -- approve 1 more and exercise should pass
        ERC20B.approve(address(engine), (8 ether * 3) + expectedFee);
        engine.exercise(optionId, 3);
        vm.stopPrank();

        assertEq(engine.balanceOf(other, optionId), 1, "Other option tokens"); // 1 left after 3 are burned on exercise
    }

    /*//////////////////////////////////////////////////////////////
    // function setFeesEnabled(bool enabled) external
    //////////////////////////////////////////////////////////////*/

    function test_setFeesEnabled() public {
        vm.expectEmit(true, true, true, true);
        emit FeeSwitchUpdated(FEE_TO, false);

        // disable
        vm.startPrank(FEE_TO);
        engine.setFeesEnabled(false);

        assertFalse(engine.feesEnabled());

        vm.expectEmit(true, true, true, true);
        emit FeeSwitchUpdated(FEE_TO, true);

        // enable
        engine.setFeesEnabled(true);
        vm.stopPrank();

        assertTrue(engine.feesEnabled());
    }

    // Negative behavior

    function testRevert_setFeesEnabled_whenNotFeeTo() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.AccessControlViolation.selector, ALICE, FEE_TO));

        vm.prank(ALICE);
        engine.setFeesEnabled(true);
    }

    /*//////////////////////////////////////////////////////////////
    // function setFeeTo(address newFeeTo) external + function acceptFeeTo() external
    //////////////////////////////////////////////////////////////*/

    function test_setFeeToAndAcceptFeeTo() public {
        address newFeeTo = address(0xCAFE);

        // precondition check
        assertEq(engine.feeTo(), FEE_TO);

        vm.prank(FEE_TO);
        engine.setFeeTo(newFeeTo);

        vm.expectEmit(true, true, true, true);
        emit FeeToUpdated(newFeeTo);

        vm.prank(newFeeTo);
        engine.acceptFeeTo();

        assertEq(engine.feeTo(), newFeeTo);
    }

    function test_setFeeToAndAcceptFeeTo_multipleTimes() public {
        address newFeeTo = address(0xCAFE);
        address newNewFeeTo = address(0xBEEF);

        // First time around.
        vm.prank(FEE_TO);
        engine.setFeeTo(newFeeTo);

        vm.expectEmit(true, true, true, true);
        emit FeeToUpdated(newFeeTo);

        vm.prank(newFeeTo);
        engine.acceptFeeTo();

        assertEq(engine.feeTo(), newFeeTo);

        // Second time around.
        vm.prank(newFeeTo);
        engine.setFeeTo(newNewFeeTo);

        vm.expectEmit(true, true, true, true);
        emit FeeToUpdated(newNewFeeTo);

        vm.prank(newNewFeeTo);
        engine.acceptFeeTo();

        assertEq(engine.feeTo(), newNewFeeTo);
    }

    function testRevert_setFeeTo_whenNotCurrentFeeTo() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.AccessControlViolation.selector, ALICE, FEE_TO));
        vm.prank(ALICE);
        engine.setFeeTo(address(0xCAFE));
    }

    function testRevert_setFeeTo_whenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));
        vm.prank(FEE_TO);
        engine.setFeeTo(address(0));
    }

    function testRevert_acceptFeeTo_whenNotPendingFeeTo() public {
        address newFeeTo = address(0xCAFE);

        vm.prank(FEE_TO);
        engine.setFeeTo(newFeeTo);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.AccessControlViolation.selector, ALICE, newFeeTo)
        );
        vm.prank(ALICE);
        engine.acceptFeeTo();
    }

    /*//////////////////////////////////////////////////////////////
    // function setTokenURIGenerator(address newTokenURIGenerator) external
    //////////////////////////////////////////////////////////////*/

    function test_setTokenURIGenerator() public {
        TokenURIGenerator newTokenURIGenerator = new TokenURIGenerator();

        vm.expectEmit(true, true, true, true);
        emit TokenURIGeneratorUpdated(address(newTokenURIGenerator));

        vm.prank(FEE_TO);
        engine.setTokenURIGenerator(address(newTokenURIGenerator));

        assertEq(address(engine.tokenURIGenerator()), address(newTokenURIGenerator));
    }

    // Negative behavior

    function testRevert_setTokenURIGenerator_whenNotCurrentFeeTo() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.AccessControlViolation.selector, ALICE, FEE_TO));
        vm.prank(ALICE);
        engine.setTokenURIGenerator(address(0xCAFE));
    }

    function testRevert_setTokenURIGenerator_whenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));
        vm.prank(FEE_TO);
        engine.setTokenURIGenerator(address(0));
    }

    /*//////////////////////////////////////////////////////////////
    // function sweepFees(address[] memory tokens) external
    //////////////////////////////////////////////////////////////*/

    // TODO(Should fee sweep be onlyFeeTo? Probably)

    function test_sweepFees_whenNoFees() public {
        // Precondition checks
        assertEq(WETHLIKE.balanceOf(FEE_TO), 0);
        assertEq(DAILIKE.balanceOf(FEE_TO), 0);
        assertEq(USDCLIKE.balanceOf(FEE_TO), 0);

        address[] memory tokens = new address[](3);
        tokens[0] = address(WETHLIKE);
        tokens[1] = address(DAILIKE);
        tokens[2] = address(USDCLIKE);
        engine.sweepFees(tokens);

        // Balance assertions -- no change
        assertEq(WETHLIKE.balanceOf(FEE_TO), 0);
        assertEq(DAILIKE.balanceOf(FEE_TO), 0);
        assertEq(USDCLIKE.balanceOf(FEE_TO), 0);
    }

    function test_sweepFees() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(WETHLIKE);
        tokens[1] = address(DAILIKE);

        vm.startPrank(ALICE);
        engine.write(testOptionId, 10);
        vm.warp(testExerciseTimestamp);
        engine.exercise(testOptionId, 10);
        vm.stopPrank();

        uint256 wethFee = _calculateFee(10 * testUnderlyingAmount);
        uint256 daiFee = _calculateFee(10 * testExerciseAmount);

        // Precondition checks
        assertEq(WETHLIKE.balanceOf(FEE_TO), 0);
        assertEq(DAILIKE.balanceOf(FEE_TO), 0);

        emit FeeSwept(testUnderlyingAsset, FEE_TO, wethFee);
        emit FeeSwept(testExerciseAsset, FEE_TO, daiFee);

        engine.sweepFees(tokens);

        // Balance assertions -- with tolerance of 1 wei for loss of precision
        assertApproxEqAbs(WETHLIKE.balanceOf(FEE_TO), wethFee, 1, "FeeTo underlying balance");
        assertApproxEqAbs(DAILIKE.balanceOf(FEE_TO), daiFee, 1, "FeeTo exercise balance");
    }

    /*//////////////////////////////////////////////////////////////
    // function uri(uint256 tokenId) public view virtual override returns (string memory)
    //////////////////////////////////////////////////////////////*/

    function test_uri() public view {
        engine.uri(testOptionId);
    }

    // Negative behavior

    function testRevert_uri_whenTokenNotFound() public {
        uint256 tokenId = 420;

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, tokenId));
        engine.uri(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
    // constructor(address _feeTo, address _tokenURIGenerator)
    //////////////////////////////////////////////////////////////*/

    function testRevert_construction_whenFeeToIsZeroAddress() public {
        TokenURIGenerator localGenerator = new TokenURIGenerator();

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));
        new OptionSettlementEngine(address(0), address(localGenerator));
    }

    function testRevert_construction_whenTokenURIGeneratorIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));
        new OptionSettlementEngine(FEE_TO, address(0));
    }
}
