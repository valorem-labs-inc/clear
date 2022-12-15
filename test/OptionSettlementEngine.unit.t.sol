// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

import "solmate/utils/FixedPointMathLib.sol";
import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "./utils/BaseEngineTest.sol";

/// @notice Unit tests for OptionSettlementEngine
contract OptionSettlementTest is BaseEngineTest {
    // function setUp() public override {
    //     super.setUp();

    //     //
    // }

    function testInitial() public {
        assertEq(engine.feeTo(), FEE_TO);
        assertEq(engine.feesEnabled(), true);
    }

    /*//////////////////////////////////////////////////////////////
    //  Write Options / Redeem Claims
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
    //  Exercise Options
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
    //  Token Information
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
    //  Protocol Fees
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
    //  Privileged Functions
    //////////////////////////////////////////////////////////////*/

    function testExerciseBeforeExpiry() public {
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

        assertEq(engine.balanceOf(BOB, testOptionId), 0);
    }

    function testClaimAccessorBasic() public {
        vm.startPrank(ALICE);

        uint256 claimId1 = engine.write(testOptionId, 1);
        IOptionSettlementEngine.Claim memory claim1 = engine.claim(claimId1);
        assertEq(claim1.amountWritten, 1e18);
        assertEq(claim1.amountExercised, 0);

        uint256 claimId2 = engine.write(testOptionId, 1);
        IOptionSettlementEngine.Claim memory claim2 = engine.claim(claimId2);
        assertEq(claim1.amountWritten, 1e18);
        assertEq(claim1.amountExercised, 0);
        assertEq(claim2.amountWritten, 1e18);
        assertEq(claim2.amountExercised, 0);

        engine.write(claimId2, 1);
        claim2 = engine.claim(claimId2);
        assertEq(claim1.amountWritten, 1e18);
        assertEq(claim1.amountExercised, 0);
        assertEq(claim2.amountWritten, 2e18);
        assertEq(claim2.amountExercised, 0);

        vm.warp(testExerciseTimestamp);

        engine.exercise(testOptionId, 2);
        claim1 = engine.claim(claimId1);
        claim2 = engine.claim(claimId2);
        assertEq(claim1.amountWritten, 1e18);
        // exercised ratio in the bucket is 2/3
        assertEq(
            // 1 option is written in this claim, two options are exercised in the bucket, and in
            // total, 3 options are written
            claim1.amountExercised,
            FixedPointMathLib.divWadDown(1 * 2, 3)
        );
        assertEq(claim2.amountWritten, 2e18);
        assertEq(
            // 2 options are written in this claim, two options are exercised in the bucket, and in
            // total, 3 options are written
            claim2.amountExercised,
            FixedPointMathLib.divWadDown(2 * 2, 3)
        );
    }

    function testFairAssignment() public {
        // write 2, exercise 1, write 2 should create two buckets
        vm.startPrank(ALICE);

        uint256 claimId1 = engine.write(testOptionId, 1);
        uint256 claimId2 = engine.write(testOptionId, 1);

        engine.exercise(testOptionId, 1);

        // This should be written into a new bucket, and so the ratio of exercised to written in
        // this bucket should be zero
        uint256 claimId3 = engine.write(testOptionId, 2);

        IOptionSettlementEngine.Claim memory claim1 = engine.claim(claimId1);
        IOptionSettlementEngine.Claim memory claim2 = engine.claim(claimId2);
        IOptionSettlementEngine.Claim memory claim3 = engine.claim(claimId3);

        assertEq(claim1.amountWritten, 1e18);
        assertEq(claim1.amountExercised, FixedPointMathLib.divWadDown(1 * 1, 2));

        assertEq(claim2.amountWritten, 1e18);
        assertEq(claim2.amountExercised, FixedPointMathLib.divWadDown(1 * 1, 2));

        assertEq(claim3.amountWritten, 2e18);
        assertEq(claim3.amountExercised, 0);

        engine.exercise(testOptionId, 1);

        claim1 = engine.claim(claimId1);
        claim2 = engine.claim(claimId2);
        claim3 = engine.claim(claimId3);

        // 50/50 chance of exercising in first (claim 1 & 2) bucket or second bucket (claim 3)
        // 1 option is written in this claim, two options are exercised in the bucket, and in
        // total, 2 options are written
        assertEq(claim1.amountWritten, 1e18);
        assertEq(claim1.amountExercised, FixedPointMathLib.divWadDown(1 * 2, 2));

        assertEq(claim2.amountWritten, 1e18);
        assertEq(claim2.amountExercised, FixedPointMathLib.divWadDown(1 * 2, 2));

        assertEq(claim3.amountWritten, 2e18);
        assertEq(claim3.amountExercised, 0);

        // First bucket is fully exercised, this will be performed on the second
        engine.exercise(testOptionId, 1);

        claim1 = engine.claim(claimId1);
        claim2 = engine.claim(claimId2);
        claim3 = engine.claim(claimId3);

        assertEq(claim1.amountWritten, 1e18);
        assertEq(claim1.amountExercised, FixedPointMathLib.divWadDown(1 * 2, 2));

        assertEq(claim2.amountWritten, 1e18);
        assertEq(claim2.amountExercised, FixedPointMathLib.divWadDown(1 * 2, 2));

        assertEq(claim3.amountWritten, 2e18);
        assertEq(claim3.amountExercised, FixedPointMathLib.divWadDown(2 * 1, 2));

        // Both buckets are fully exercised
        engine.exercise(testOptionId, 1);

        claim1 = engine.claim(claimId1);
        claim2 = engine.claim(claimId2);
        claim3 = engine.claim(claimId3);

        assertEq(claim1.amountWritten, 1e18);
        assertEq(claim1.amountExercised, FixedPointMathLib.divWadDown(1 * 2, 2));

        assertEq(claim2.amountWritten, 1e18);
        assertEq(claim2.amountExercised, FixedPointMathLib.divWadDown(1 * 2, 2));

        assertEq(claim3.amountWritten, 2e18);
        assertEq(claim3.amountExercised, FixedPointMathLib.divWadDown(2 * 2, 2));
    }

    function testWriteMultipleWriteSameOptionType() public {
        // Alice writes a few options and later decides to write more
        vm.startPrank(ALICE);
        uint256 claimId1 = engine.write(testOptionId, 69);
        vm.warp(block.timestamp + 100);
        uint256 claimId2 = engine.write(testOptionId, 100);
        vm.stopPrank();

        assertEq(engine.balanceOf(ALICE, testOptionId), 169);
        assertEq(engine.balanceOf(ALICE, claimId1), 1);
        assertEq(engine.balanceOf(ALICE, claimId2), 1);

        IOptionSettlementEngine.Underlying memory claimUnderlying = engine.underlying(claimId1);
        (uint160 _optionId, uint96 claimIdx) = decodeTokenId(claimId1);
        uint256 optionId = uint256(_optionId) << 96;
        assertEq(optionId, testOptionId);
        assertEq(claimIdx, 1);
        assertEq(uint256(claimUnderlying.underlyingPosition), 69 * testUnderlyingAmount);
        _assertClaimAmountExercised(claimId1, 0);

        claimUnderlying = engine.underlying(claimId2);
        (optionId, claimIdx) = decodeTokenId(claimId2);
        optionId = uint256(_optionId) << 96;
        assertEq(optionId, testOptionId);
        assertEq(claimIdx, 2);
        assertEq(uint256(claimUnderlying.underlyingPosition), 100 * testUnderlyingAmount);
        _assertClaimAmountExercised(claimId2, 0);
    }

    function testTokenURI() public view {
        engine.uri(testOptionId);
    }

    function testExerciseMultipleWriteSameChain() public {
        uint256 wethBalanceEngine = WETHLIKE.balanceOf(address(engine));
        uint256 wethBalanceA = WETHLIKE.balanceOf(ALICE);
        uint256 wethBalanceB = WETHLIKE.balanceOf(BOB);
        uint256 daiBalanceEngine = DAILIKE.balanceOf(address(engine));
        uint256 daiBalanceA = DAILIKE.balanceOf(ALICE);
        uint256 daiBalanceB = DAILIKE.balanceOf(BOB);

        // Alice writes 1, decides to write another, and sends both to Bob to exercise
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 2, "");
        vm.stopPrank();

        assertEq(engine.balanceOf(ALICE, testOptionId), 0);
        assertEq(engine.balanceOf(BOB, testOptionId), 2);

        // Fees
        uint256 writeAmount = 2 * testUnderlyingAmount;
        uint256 writeFee = (writeAmount / 10000) * engine.feeBps();

        uint256 exerciseAmount = 2 * testExerciseAmount;
        uint256 exerciseFee = (exerciseAmount / 10000) * engine.feeBps();

        assertEq(WETHLIKE.balanceOf(address(engine)), wethBalanceEngine + writeAmount + writeFee);

        vm.warp(testExpiryTimestamp - 1);
        // Bob exercises
        vm.prank(BOB);
        engine.exercise(testOptionId, 2);
        assertEq(engine.balanceOf(BOB, testOptionId), 0);

        assertEq(WETHLIKE.balanceOf(address(engine)), wethBalanceEngine + writeFee);
        assertEq(WETHLIKE.balanceOf(ALICE), wethBalanceA - writeAmount - writeFee);
        assertEq(WETHLIKE.balanceOf(BOB), wethBalanceB + writeAmount);
        assertEq(DAILIKE.balanceOf(address(engine)), daiBalanceEngine + exerciseAmount + exerciseFee);
        assertEq(DAILIKE.balanceOf(ALICE), daiBalanceA);
        assertEq(DAILIKE.balanceOf(BOB), daiBalanceB - exerciseAmount - exerciseFee);
    }

    function testExerciseIncompleteExercise() public {
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 100);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 100, "");
        vm.stopPrank();

        // Fast-forward to just before expiry
        vm.warp(testExpiryTimestamp - 1);

        // Bob exercises
        vm.startPrank(BOB);
        engine.exercise(testOptionId, 50);

        // Bob exercises again
        engine.exercise(testOptionId, 50);
        vm.stopPrank();

        assertEq(engine.balanceOf(BOB, testOptionId), 0);
    }

    // NOTE: This test needed as testFuzz_redeem does not check if exerciseAmount == 0
    function testRedeemNotExercised() public {
        IOptionSettlementEngine.Underlying memory claimUnderlying;
        uint256 wethBalanceEngine = WETHLIKE.balanceOf(address(engine));
        uint256 wethBalanceA = WETHLIKE.balanceOf(ALICE);
        // Alice writes 7 and no one exercises
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 7);

        vm.warp(testExpiryTimestamp + 1);

        claimUnderlying = engine.underlying(claimId);
        assertTrue(claimUnderlying.underlyingPosition != 0);

        engine.redeem(claimId);
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, claimId));
        engine.underlying(claimId);

        // Fees
        uint256 writeAmount = 7 * testUnderlyingAmount;
        uint256 writeFee = (writeAmount / 10000) * engine.feeBps();
        assertEq(WETHLIKE.balanceOf(ALICE), wethBalanceA - writeFee);
        assertEq(WETHLIKE.balanceOf(address(engine)), wethBalanceEngine + writeFee);
    }

    function testExerciseWithDifferentDecimals() public {
        // Write an option where one of the assets isn't 18 decimals
        (uint256 newOptionId,) = _createNewOptionType({
            underlyingAsset: address(USDCLIKE),
            underlyingAmount: 100,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });

        // Alice writes
        vm.startPrank(ALICE);
        engine.write(newOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, newOptionId, 1, "");
        vm.stopPrank();

        // Bob owns 1 of these options
        assertEq(engine.balanceOf(BOB, newOptionId), 1);

        // Fast-forward to just before expiry
        vm.warp(testExpiryTimestamp - 1 seconds);

        // Bob exercises
        vm.startPrank(BOB);
        engine.exercise(newOptionId, 1);
        vm.stopPrank();

        // Now Bob owns 0 of these options
        assertEq(engine.balanceOf(BOB, newOptionId), 0);
    }

    function testUnderlyingWhenNotExercised() public {
        // Alice writes 7 and no one exercises
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 7);

        vm.warp(testExpiryTimestamp + 1);

        IOptionSettlementEngine.Underlying memory underlyingPositions = engine.underlying(claimId);

        assertEq(underlyingPositions.underlyingAsset, address(WETHLIKE));
        _assertPosition(underlyingPositions.underlyingPosition, 7 * testUnderlyingAmount);
        assertEq(underlyingPositions.exerciseAsset, address(DAILIKE));
        assertEq(underlyingPositions.exercisePosition, 0);
    }

    function testUnderlyingAfterExercise() public {
        uint256 claimId = _writeAndExerciseOption(testOptionId, ALICE, BOB, 2, 0);
        IOptionSettlementEngine.Underlying memory underlyingPositions = engine.underlying(claimId);
        _assertPosition(underlyingPositions.underlyingPosition, 2 * testUnderlyingAmount);
        assertEq(underlyingPositions.exercisePosition, 0);

        _writeAndExerciseOption(testOptionId, ALICE, BOB, 0, 1);
        underlyingPositions = engine.underlying(claimId);
        _assertPosition(underlyingPositions.underlyingPosition, testUnderlyingAmount);
        _assertPosition(underlyingPositions.exercisePosition, testExerciseAmount);

        _writeAndExerciseOption(testOptionId, ALICE, BOB, 0, 1);
        underlyingPositions = engine.underlying(claimId);
        _assertPosition(underlyingPositions.underlyingPosition, 0);
        _assertPosition(underlyingPositions.exercisePosition, 2 * testExerciseAmount);
    }

    function testWriteAfterFullyExercisingDay() public {
        uint256 claim1 = _writeAndExerciseOption(testOptionId, ALICE, BOB, 1, 1);
        uint256 claim2 = _writeAndExerciseOption(testOptionId, ALICE, BOB, 1, 1);

        IOptionSettlementEngine.Underlying memory underlyingPositions = engine.underlying(claim1);
        _assertPosition(underlyingPositions.underlyingPosition, 0);
        _assertPosition(underlyingPositions.exercisePosition, testExerciseAmount);

        underlyingPositions = engine.underlying(claim2);
        _assertPosition(underlyingPositions.underlyingPosition, 0);
        _assertPosition(underlyingPositions.exercisePosition, testExerciseAmount);
    }

    function testUnderlyingForFungibleOptionToken() public {
        IOptionSettlementEngine.Underlying memory underlying = engine.underlying(testOptionId);
        // before expiry, position is entirely the underlying amount
        _assertPosition(underlying.underlyingPosition, testUnderlyingAmount);
        _assertPosition(-1 * underlying.exercisePosition, testExerciseAmount);
        assertEq(testExerciseAsset, underlying.exerciseAsset);
        assertEq(testUnderlyingAsset, underlying.underlyingAsset);

        vm.warp(testOption.expiryTimestamp);
        // The token is now expired/worthless, and this should revert.
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );
        underlying = engine.underlying(testOptionId);
    }

    function testAddOptionsToExistingClaim() public {
        // write some options, grab a claim
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);

        IOptionSettlementEngine.Underlying memory claimUnderlying = engine.underlying(claimId);

        assertEq(testUnderlyingAmount, uint256(claimUnderlying.underlyingPosition));
        _assertClaimAmountExercised(claimId, 0);
        assertEq(1, engine.balanceOf(ALICE, claimId));
        assertEq(1, engine.balanceOf(ALICE, testOptionId));

        // write some more options, get a new claim NFT
        uint256 claimId2 = engine.write(testOptionId, 1);
        assertFalse(claimId == claimId2);
        assertEq(1, engine.balanceOf(ALICE, claimId2));
        assertEq(2, engine.balanceOf(ALICE, testOptionId));

        // write some more options, adding to existing claim
        uint256 claimId3 = engine.write(claimId, 1);
        assertEq(claimId, claimId3);
        assertEq(1, engine.balanceOf(ALICE, claimId3));
        assertEq(3, engine.balanceOf(ALICE, testOptionId));

        claimUnderlying = engine.underlying(claimId3);
        assertEq(2 * testUnderlyingAmount, uint256(claimUnderlying.underlyingPosition));
        _assertClaimAmountExercised(claimId, 0);
    }

    function testRandomAssignment() public {
        uint16 numDays = 7;
        uint256[] memory claimIds = new uint256[](numDays);

        // New option type with expiry in 1w
        testExerciseTimestamp = uint40(block.timestamp - 1);
        testExpiryTimestamp = uint40(block.timestamp + numDays * 1 days + 1);
        (uint256 optionId,) = _createNewOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: testUnderlyingAmount + 1, // to mess w seed
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });

        vm.startPrank(ALICE);
        for (uint256 i = 0; i < numDays; i++) {
            // write a single option
            uint256 claimId = engine.write(optionId, 1);
            claimIds[i] = claimId;
            vm.warp(block.timestamp + 1 days);
        }
        engine.safeTransferFrom(ALICE, BOB, optionId, numDays, "");
        vm.stopPrank();

        vm.startPrank(BOB);
    }

    function testWriteRecordFees() public {
        // Alice writes 2
        vm.prank(ALICE);
        engine.write(testOptionId, 2);

        // Fee is recorded on underlying asset, not on exercise asset
        uint256 writeAmount = 2 * testUnderlyingAmount;
        uint256 writeFee = (writeAmount * engine.feeBps()) / 10_000;
        assertEq(engine.feeBalance(address(WETHLIKE)), writeFee);
        assertEq(engine.feeBalance(address(DAILIKE)), 0);
    }

    function testWriteNoFeesRecordedWhenFeeSwitchIsDisabled() public {
        // precondition check, fee is recorded and emitted on write
        vm.prank(ALICE);
        engine.write(testOptionId, 2);

        uint256 writeAmount = 2 * testUnderlyingAmount;
        uint256 writeFee = (writeAmount * engine.feeBps()) / 10_000;
        assertEq(engine.feeBalance(address(WETHLIKE)), writeFee);

        // Disable fee switch
        vm.prank(FEE_TO);
        engine.setFeesEnabled(false);

        // Write 3 more, no fee is recorded or emitted
        vm.prank(ALICE);
        engine.write(testOptionId, 3);
        assertEq(engine.feeBalance(address(WETHLIKE)), writeFee); // no change

        // Re-enable
        vm.prank(FEE_TO);
        engine.setFeesEnabled(true);

        // Write 5 more, fee is again recorded and emitted
        vm.prank(ALICE);
        engine.write(testOptionId, 5);
        writeAmount = 5 * testUnderlyingAmount;
        writeFee += (writeAmount * engine.feeBps()) / 10_000;
        assertEq(engine.feeBalance(address(WETHLIKE)), writeFee); // includes fee on writing 5 more
    }

    function testExerciseRecordFees() public {
        // Alice writes 2 and transfers to Bob
        vm.startPrank(ALICE);
        engine.write(testOptionId, 2);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 2, "");
        vm.stopPrank();

        // Bob exercises 2
        vm.warp(testExerciseTimestamp + 1 seconds);
        vm.prank(BOB);
        engine.exercise(testOptionId, 2);

        // Fee is recorded on exercise asset
        uint256 exerciseAmount = 2 * testExerciseAmount;
        uint256 exerciseFee = (exerciseAmount * engine.feeBps()) / 10_000;
        assertEq(engine.feeBalance(address(DAILIKE)), exerciseFee);
    }

    function testExerciseNoFeesRecordedWhenFeeSwitchIsDisabled() public {
        // precondition check, fee is recorded and emitted on exercise
        vm.startPrank(ALICE);
        engine.write(testOptionId, 10);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 10, "");
        vm.stopPrank();

        vm.warp(testExerciseTimestamp + 1 seconds);
        vm.prank(BOB);
        engine.exercise(testOptionId, 2);

        uint256 exerciseAmount = 2 * testExerciseAmount;
        uint256 exerciseFee = (exerciseAmount * engine.feeBps()) / 10_000;
        assertEq(engine.feeBalance(address(DAILIKE)), exerciseFee);

        // Disable fee switch
        vm.prank(FEE_TO);
        engine.setFeesEnabled(false);

        // Exercise 3 more, no fee is recorded or emitted
        vm.prank(BOB);
        engine.exercise(testOptionId, 3);
        assertEq(engine.feeBalance(address(DAILIKE)), exerciseFee); // no change

        // Re-enable
        vm.prank(FEE_TO);
        engine.setFeesEnabled(true);

        // Exercise 5 more, fee is again recorded and emitted
        vm.prank(BOB);
        engine.exercise(testOptionId, 5);
        exerciseAmount = 5 * testExerciseAmount;
        exerciseFee += (exerciseAmount * engine.feeBps()) / 10_000;
        assertEq(engine.feeBalance(address(DAILIKE)), exerciseFee); // includes fee on exercising 5 more
    }

    // **********************************************************************
    //                            PROTOCOL ADMIN
    // **********************************************************************

    function testSetFeesEnabled() public {
        // precondition check -- in test suite, fee switch is enabled by default
        assertTrue(engine.feesEnabled());

        // disable
        vm.startPrank(FEE_TO);
        engine.setFeesEnabled(false);

        assertFalse(engine.feesEnabled());

        // enable
        engine.setFeesEnabled(true);

        assertTrue(engine.feesEnabled());
    }

    function testEventSetFeesEnabled() public {
        vm.expectEmit(true, true, true, true);
        emit FeeSwitchUpdated(FEE_TO, false);

        // disable
        vm.startPrank(FEE_TO);
        engine.setFeesEnabled(false);

        vm.expectEmit(true, true, true, true);
        emit FeeSwitchUpdated(FEE_TO, true);

        // enable
        engine.setFeesEnabled(true);
    }

    function testRevertSetFeesEnabledWhenNotFeeTo() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.AccessControlViolation.selector, ALICE, FEE_TO));

        vm.prank(ALICE);
        engine.setFeesEnabled(true);
    }

    function testRevertConstructorWhenFeeToIsZeroAddress() public {
        TokenURIGenerator localGenerator = new TokenURIGenerator();

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));

        new OptionSettlementEngine(address(0), address(localGenerator));
    }

    function testRevertConstructorWhenTokenURIGeneratorIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));

        new OptionSettlementEngine(FEE_TO, address(0));
    }

    function testSetFeeTo() public {
        // precondition check
        assertEq(engine.feeTo(), FEE_TO);

        vm.prank(FEE_TO);
        engine.setFeeTo(address(0xCAFE));

        assertEq(engine.feeTo(), address(0xCAFE));
    }

    function testEventSetFeeTo() public {
        vm.expectEmit(true, true, true, true);
        emit FeeToUpdated(address(0xCAFE));

        vm.prank(FEE_TO);
        engine.setFeeTo(address(0xCAFE));

        assertEq(engine.feeTo(), address(0xCAFE));
    }

    function testRevertSetFeeToWhenNotCurrentFeeTo() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.AccessControlViolation.selector, ALICE, FEE_TO));
        vm.prank(ALICE);
        engine.setFeeTo(address(0xCAFE));
    }

    function testRevertSetFeeToWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));
        vm.prank(FEE_TO);
        engine.setFeeTo(address(0));
    }

    function testSetTokenURIGenerator() public {
        TokenURIGenerator newTokenURIGenerator = new TokenURIGenerator();

        vm.prank(FEE_TO);
        engine.setTokenURIGenerator(address(newTokenURIGenerator));

        assertEq(address(engine.tokenURIGenerator()), address(newTokenURIGenerator));
    }

    function testEventSetTokenURIGenerator() public {
        TokenURIGenerator newTokenURIGenerator = new TokenURIGenerator();

        vm.expectEmit(true, true, true, true);
        emit TokenURIGeneratorUpdated(address(newTokenURIGenerator));

        vm.prank(FEE_TO);
        engine.setTokenURIGenerator(address(newTokenURIGenerator));
    }

    function testRevertSetTokenURIGeneratorWhenNotCurrentFeeTo() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.AccessControlViolation.selector, ALICE, FEE_TO));
        vm.prank(ALICE);
        engine.setTokenURIGenerator(address(0xCAFE));
    }

    function testRevertSetTokenURIGeneratorWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));
        vm.prank(FEE_TO);
        engine.setTokenURIGenerator(address(0));
    }

    // **********************************************************************
    //                            TOKEN ID ENCODING HELPERS
    // **********************************************************************

    function testEncodeTokenId() public {
        // Create new option type
        uint256 oTokenId = engine.newOptionType(
            address(DAILIKE), 1, address(USDCLIKE), 100, uint40(block.timestamp), uint40(block.timestamp + 30 days)
        );

        // Write 2 separate options lots
        vm.prank(ALICE);
        uint256 cTokenId1 = engine.write(oTokenId, 7);
        vm.prank(ALICE);
        uint256 cTokenId2 = engine.write(oTokenId, 3);

        // Check encoding the first claim
        (uint160 decodedOptionId,) = decodeTokenId(cTokenId1);
        uint96 expectedClaimIndex1 = 1;
        assertEq(encodeTokenId(decodedOptionId, expectedClaimIndex1), cTokenId1);

        // Check encoding the second claim
        uint96 expectedClaimIndex2 = 2;
        assertEq(encodeTokenId(decodedOptionId, expectedClaimIndex2), cTokenId2);
    }

    function testFuzzEncodeTokenId(uint256 optionId, uint256 claimIndex) public {
        optionId = bound(optionId, 0, type(uint160).max);
        claimIndex = bound(claimIndex, 0, type(uint96).max);

        uint256 expectedTokenId = claimIndex;
        expectedTokenId |= optionId << 96;

        assertEq(encodeTokenId(uint160(optionId), uint96(claimIndex)), expectedTokenId);
    }

    function testDecodeTokenId() public {
        // Create new option type
        uint256 oTokenId = engine.newOptionType(
            address(DAILIKE), 1, address(USDCLIKE), 100, uint40(block.timestamp), uint40(block.timestamp + 30 days)
        );

        // Write 2 separate options lots
        vm.prank(ALICE);
        uint256 cTokenId1 = engine.write(oTokenId, 7);
        vm.prank(ALICE);
        uint256 cTokenId2 = engine.write(oTokenId, 3);

        (uint160 decodedOptionIdFromOTokenId, uint96 decodedClaimIndexFromOTokenId) = decodeTokenId(oTokenId);
        assertEq(decodedOptionIdFromOTokenId, oTokenId >> 96);
        assertEq(decodedClaimIndexFromOTokenId, 0); // no claims when initially creating a new option type

        (uint160 decodedOptionIdFromCTokenId1, uint96 decodedClaimIndexFromCTokenId1) = decodeTokenId(cTokenId1);
        assertEq(decodedOptionIdFromCTokenId1, oTokenId >> 96);
        assertEq(decodedClaimIndexFromCTokenId1, 1); // first claim

        (uint160 decodedOptionIdFromCTokenId2, uint96 decodedClaimIndexFromCTokenId2) = decodeTokenId(cTokenId2);
        assertEq(decodedOptionIdFromCTokenId2, oTokenId >> 96);
        assertEq(decodedClaimIndexFromCTokenId2, 2); // second claim
    }

    function testFuzzDecodeTokenId(uint256 optionId, uint256 claimId) public {
        optionId = bound(optionId, 0, type(uint160).max);
        claimId = bound(claimId, 0, type(uint96).max);

        uint256 testTokenId = claimId;
        testTokenId |= optionId << 96;

        (uint160 decodedOptionId, uint96 decodedClaimId) = decodeTokenId(testTokenId);
        assertEq(decodedOptionId, optionId);
        assertEq(decodedClaimId, claimId);
    }

    function testGetOptionForTokenId() public {
        IOptionSettlementEngine.Option memory option = IOptionSettlementEngine.Option({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: 1,
            exerciseAsset: address(USDCLIKE),
            exerciseAmount: 100,
            exerciseTimestamp: uint40(block.timestamp),
            expiryTimestamp: uint40(block.timestamp + 30 days),
            settlementSeed: 0,
            nextClaimKey: 0
        });
        uint256 optionId = engine.newOptionType(
            address(DAILIKE), 1, address(USDCLIKE), 100, uint40(block.timestamp), uint40(block.timestamp + 30 days)
        );

        // Update struct values to match stored option data structure
        uint160 optionKey = uint160(bytes20(keccak256(abi.encode(option))));

        option.settlementSeed = optionKey; // settlement seed is initially equal to option key
        option.nextClaimKey = 1; // next claim num has been incremented

        assertEq(engine.option(optionId), option);
    }

    function testGetClaimForTokenId() public {
        uint256 optionId = engine.newOptionType(
            address(DAILIKE), 1, address(USDCLIKE), 100, uint40(block.timestamp), uint40(block.timestamp + 30 days)
        );

        vm.prank(ALICE);
        uint256 claimId = engine.write(optionId, 7);

        IOptionSettlementEngine.Underlying memory claimUnderlying = engine.underlying(claimId);

        assertEq(uint256(claimUnderlying.underlyingPosition), 7 * 1);
    }

    function testIsOptionInitialized() public {
        uint256 oTokenId = engine.newOptionType(
            address(DAILIKE), 1, address(USDCLIKE), 100, uint40(block.timestamp), uint40(block.timestamp + 30 days)
        );

        _assertTokenIsOption(oTokenId);
        _assertTokenIsNone(1337);
    }

    // **********************************************************************
    //                            EVENT TESTS
    // **********************************************************************

    function testEventNewOptionType() public {
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

    function testEventWriteWhenNewClaim() public {
        uint256 expectedFeeAccruedAmount = ((testUnderlyingAmount / 10_000) * engine.feeBps());

        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(testOptionId, address(WETHLIKE), ALICE, expectedFeeAccruedAmount);

        vm.expectEmit(true, true, true, true);
        emit OptionsWritten(testOptionId, ALICE, testOptionId + 1, 1);

        vm.prank(ALICE);
        engine.write(testOptionId, 1);
    }

    function testEventWriteWhenExistingClaim() public {
        uint256 expectedFeeAccruedAmount = ((testUnderlyingAmount / 10_000) * engine.feeBps());

        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);

        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(testOptionId, address(WETHLIKE), ALICE, expectedFeeAccruedAmount);

        vm.expectEmit(true, true, true, true);
        emit OptionsWritten(testOptionId, ALICE, claimId, 1);

        vm.prank(ALICE);
        engine.write(claimId, 1);
    }

    function testEventExercise() public {
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        vm.warp(testExpiryTimestamp - 1 seconds);

        decodeTokenId(testOptionId);
        uint256 expectedFeeAccruedAmount = (testExerciseAmount / 10_000) * engine.feeBps();

        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(testOptionId, address(DAILIKE), BOB, expectedFeeAccruedAmount);

        vm.expectEmit(true, true, true, true);
        emit OptionsExercised(testOptionId, BOB, 1);

        vm.prank(BOB);
        engine.exercise(testOptionId, 1);
    }

    function testEventRedeem() public {
        vm.startPrank(ALICE);
        uint96 amountWritten = 7;
        uint256 claimId = engine.write(testOptionId, amountWritten);
        uint96 expectedUnderlyingAmount = testUnderlyingAmount * amountWritten;

        vm.warp(testExpiryTimestamp + 1 seconds);

        vm.expectEmit(true, true, true, true);
        emit ClaimRedeemed(
            claimId,
            testOptionId,
            ALICE,
            0, // no one has exercised
            expectedUnderlyingAmount
            );

        engine.redeem(claimId);
    }

    function testSweepFeesWhenFeesAccruedForWrite() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(WETHLIKE);
        tokens[1] = address(DAILIKE);
        tokens[2] = address(USDCLIKE);

        uint96 daiUnderlyingAmount = 9 * 10 ** 18;
        uint96 usdcUnderlyingAmount = 7 * 10 ** 6; // not 18 decimals

        uint8 optionsWrittenWethUnderlying = 3;
        uint8 optionsWrittenDaiUnderlying = 4;
        uint8 optionsWrittenUsdcUnderlying = 5;

        // Write option that will generate WETH fees
        vm.startPrank(ALICE);
        engine.write(testOptionId, optionsWrittenWethUnderlying);

        // Write option that will generate DAI fees
        (uint256 daiOptionId,) = _createNewOptionType({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: daiUnderlyingAmount,
            exerciseAsset: address(WETHLIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(daiOptionId, optionsWrittenDaiUnderlying);

        // Write option that will generate USDC fees
        (uint256 usdcOptionId,) = _createNewOptionType({
            underlyingAsset: address(USDCLIKE),
            underlyingAmount: usdcUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(usdcOptionId, optionsWrittenUsdcUnderlying);
        vm.stopPrank();

        // Then assert expected fee amounts
        uint256[] memory expectedFees = new uint256[](3);
        expectedFees[0] = (((testUnderlyingAmount * optionsWrittenWethUnderlying) / 10_000) * engine.feeBps());
        expectedFees[1] = (((daiUnderlyingAmount * optionsWrittenDaiUnderlying) / 10_000) * engine.feeBps());
        expectedFees[2] = (((usdcUnderlyingAmount * optionsWrittenUsdcUnderlying) / 10_000) * engine.feeBps());

        // Pre feeTo balance check
        assertEq(WETHLIKE.balanceOf(FEE_TO), 0);
        assertEq(DAILIKE.balanceOf(FEE_TO), 0);
        assertEq(USDCLIKE.balanceOf(FEE_TO), 0);

        for (uint256 i = 0; i < tokens.length; i++) {
            vm.expectEmit(true, true, true, true);
            emit FeeSwept(tokens[i], engine.feeTo(), expectedFees[i] - 1); // sweeps 1 wei less as gas optimization
        }

        // When fees are swept
        engine.sweepFees(tokens);

        // Post feeTo balance check, first sweep
        uint256 feeToBalanceWeth = WETHLIKE.balanceOf(FEE_TO);
        uint256 feeToBalanceDai = DAILIKE.balanceOf(FEE_TO);
        uint256 feeToBalanceUsdc = USDCLIKE.balanceOf(FEE_TO);
        assertEq(feeToBalanceWeth, expectedFees[0] - 1);
        assertEq(feeToBalanceDai, expectedFees[1] - 1);
        assertEq(feeToBalanceUsdc, expectedFees[2] - 1);

        // Write and sweep again, but assert this time we sweep the true fee amount,
        // not 1 wei less, bc we've already done the gas optimization
        optionsWrittenWethUnderlying = 6;
        optionsWrittenDaiUnderlying = 3;
        optionsWrittenUsdcUnderlying = 2;
        vm.startPrank(ALICE);
        engine.write(testOptionId, optionsWrittenWethUnderlying);
        engine.write(daiOptionId, optionsWrittenDaiUnderlying);
        engine.write(usdcOptionId, optionsWrittenUsdcUnderlying);
        vm.stopPrank();
        expectedFees[0] = (((testUnderlyingAmount * optionsWrittenWethUnderlying) / 10_000) * engine.feeBps());
        expectedFees[1] = (((daiUnderlyingAmount * optionsWrittenDaiUnderlying) / 10_000) * engine.feeBps());
        expectedFees[2] = (((usdcUnderlyingAmount * optionsWrittenUsdcUnderlying) / 10_000) * engine.feeBps());
        for (uint256 i = 0; i < tokens.length; i++) {
            vm.expectEmit(true, true, true, true);
            emit FeeSwept(tokens[i], engine.feeTo(), expectedFees[i]); // true amount
        }
        engine.sweepFees(tokens);

        // Post feeTo balance check, second sweep
        assertEq(WETHLIKE.balanceOf(FEE_TO), feeToBalanceWeth + expectedFees[0]);
        assertEq(DAILIKE.balanceOf(FEE_TO), feeToBalanceDai + expectedFees[1]);
        assertEq(USDCLIKE.balanceOf(FEE_TO), feeToBalanceUsdc + expectedFees[2]);
    }

    function testSweepFeesWhenFeesAccruedForExercise() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(DAILIKE);
        tokens[1] = address(WETHLIKE);
        tokens[2] = address(USDCLIKE);

        uint96 daiExerciseAmount = 9 * 10 ** 18;
        uint96 wethExerciseAmount = 3 * 10 ** 18;
        uint96 usdcExerciseAmount = 7 * 10 ** 6; // not 18 decimals

        uint8 optionsWrittenDaiExercise = 3;
        uint8 optionsWrittenWethExercise = 4;
        uint8 optionsWrittenUsdcExercise = 5;

        // Write option for WETH-DAI pair
        vm.startPrank(ALICE);
        (uint256 daiExerciseOptionId,) = _createNewOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: daiExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(daiExerciseOptionId, optionsWrittenDaiExercise);

        // Write option for DAI-WETH pair
        (uint256 wethExerciseOptionId,) = _createNewOptionType({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(WETHLIKE),
            exerciseAmount: wethExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(wethExerciseOptionId, optionsWrittenWethExercise);

        // Write option for DAI-USDC pair
        (uint256 usdcExerciseOptionId,) = _createNewOptionType({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(USDCLIKE),
            exerciseAmount: usdcExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(usdcExerciseOptionId, optionsWrittenUsdcExercise);

        // Write option for USDC-DAI pair, so that USDC feeBalance will be 1 wei after writing
        (uint256 usdcUnderlyingOptionId,) = _createNewOptionType({
            underlyingAsset: address(USDCLIKE),
            underlyingAmount: usdcExerciseAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: daiExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(usdcUnderlyingOptionId, 1);

        // Transfer all option contracts to Bob
        engine.safeTransferFrom(ALICE, BOB, daiExerciseOptionId, optionsWrittenDaiExercise, "");
        engine.safeTransferFrom(ALICE, BOB, wethExerciseOptionId, optionsWrittenWethExercise, "");
        engine.safeTransferFrom(ALICE, BOB, usdcExerciseOptionId, optionsWrittenUsdcExercise, "");
        vm.stopPrank();

        vm.warp(testExpiryTimestamp - 1 seconds);

        // Clear away fees generated by writing options
        engine.sweepFees(tokens);

        // Get feeTo balances after sweeping fees from write
        uint256[] memory initialFeeToBalances = new uint256[](3);
        initialFeeToBalances[0] = DAILIKE.balanceOf(FEE_TO);
        initialFeeToBalances[1] = WETHLIKE.balanceOf(FEE_TO);
        initialFeeToBalances[2] = USDCLIKE.balanceOf(FEE_TO);

        // Exercise option that will generate WETH fees
        vm.startPrank(BOB);
        engine.exercise(daiExerciseOptionId, optionsWrittenDaiExercise);

        // // Exercise option that will generate DAI fees
        engine.exercise(wethExerciseOptionId, optionsWrittenWethExercise);

        // Exercise option that will generate USDC fees
        engine.exercise(usdcExerciseOptionId, optionsWrittenUsdcExercise);
        vm.stopPrank();

        // Then assert expected fee amounts, but because this isn't the first fee
        // taken for any of these assets, and the 1 wei-left-behind gas optimization
        // has already happened, therefore actual fee swept amount = true fee amount.
        uint256[] memory expectedFees = new uint256[](3);
        expectedFees[0] = (((daiExerciseAmount * optionsWrittenDaiExercise) / 10_000) * engine.feeBps());
        expectedFees[1] = (((wethExerciseAmount * optionsWrittenWethExercise) / 10_000) * engine.feeBps());
        expectedFees[2] = (((usdcExerciseAmount * optionsWrittenUsdcExercise) / 10_000) * engine.feeBps());

        for (uint256 i = 0; i < tokens.length; i++) {
            vm.expectEmit(true, true, true, true);
            emit FeeSwept(tokens[i], engine.feeTo(), expectedFees[i]);
        }

        // When fees are swept
        engine.sweepFees(tokens);

        // Check feeTo balances after sweeping fees from exercise
        assertEq(DAILIKE.balanceOf(FEE_TO), initialFeeToBalances[0] + expectedFees[0]);
        assertEq(WETHLIKE.balanceOf(FEE_TO), initialFeeToBalances[1] + expectedFees[1]);
        assertEq(USDCLIKE.balanceOf(FEE_TO), initialFeeToBalances[2] + expectedFees[2]);
    }

    // **********************************************************************
    //                            FAIL TESTS
    // **********************************************************************

    function testRevertNewOptionTypeWhenOptionsTypeExists() public {
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

    function testRevertNewOptionTypeWhenExpiryTooSoon() public {
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

    function testRevertNewOptionTypeWhenExerciseWindowTooShort() public {
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

    function testRevertNewOptionTypeWhenInvalidAssets() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.InvalidAssets.selector, address(DAILIKE), address(DAILIKE))
        );
        _createNewOptionType({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
    }

    function testRevertNewOptionTypeWhenTotalSuppliesAreTooLowToExercise() public {
        uint96 underlyingAmountExceedsTotalSupply = uint96(IERC20(address(DAILIKE)).totalSupply() + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.InvalidAssets.selector, address(DAILIKE), address(WETHLIKE))
        );

        _createNewOptionType({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: underlyingAmountExceedsTotalSupply,
            exerciseAsset: address(WETHLIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });

        uint96 exerciseAmountExceedsTotalSupply = uint96(IERC20(address(USDCLIKE)).totalSupply() + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.InvalidAssets.selector, address(USDCLIKE), address(WETHLIKE))
        );

        _createNewOptionType({
            underlyingAsset: address(USDCLIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(WETHLIKE),
            exerciseAmount: exerciseAmountExceedsTotalSupply,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
    }

    function testRevertWriteWhenInvalidOption() public {
        // Option ID not 0 in lower 96 b
        uint256 invalidOptionId = testOptionId + 1;
        // Option ID not initialized
        invalidOptionId = encodeTokenId(0x1, 0x0);
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidOption.selector, invalidOptionId));
        engine.write(invalidOptionId, 1);
    }

    function testRevertWriteWhenAmountWrittenCannotBeZero() public {
        uint112 invalidWriteAmount = 0;

        vm.expectRevert(IOptionSettlementEngine.AmountWrittenCannotBeZero.selector);

        engine.write(testOptionId, invalidWriteAmount);
    }

    function testRevertWriteExpiredOption() public {
        vm.warp(testExpiryTimestamp);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );

        engine.write(testOptionId, 1);
    }

    function testRevertExerciseBeforeExcercise() public {
        _createNewOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseTimestamp + 1,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp + 1
        });

        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);

        vm.stopPrank();
    }

    function testRevertWriteWhenCallerDoesNotOwnClaimId() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.CallerDoesNotOwnClaimId.selector, claimId));

        vm.prank(BOB);
        engine.write(claimId, 1);
    }

    function testRevertWriteWhenExpiredOption() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);

        vm.warp(testExpiryTimestamp + 1 seconds);

        engine.redeem(claimId);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );

        engine.write(claimId, 1);
        vm.stopPrank();
    }

    function testRevertExerciseWhenExerciseTooEarly() public {
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

    function testRevertExerciseWhenInvalidOption() public {
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);

        uint256 invalidOptionId = testOptionId + 1;

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidOption.selector, invalidOptionId));

        engine.exercise(invalidOptionId, 1);
    }

    function testRevertExerciseWhenExpiredOption() public {
        uint256 ts = block.timestamp;
        // ====== Exercise at Expiry =======
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        // Fast-forward to at expiry
        vm.warp(testExpiryTimestamp);

        // Bob exercises
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );
        engine.exercise(testOptionId, 1);
        vm.stopPrank();

        vm.warp(ts);
        // ====== Exercise after Expiry =======
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        // Fast-forward to at expiry
        vm.warp(testExpiryTimestamp + 1 seconds);

        // Bob exercises
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );
        engine.exercise(testOptionId, 1);
        vm.stopPrank();
    }

    function testRevertRedeemWhenInvalidClaim() public {
        uint256 badClaimId = encodeTokenId(0xDEADBEEF, 0);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidClaim.selector, badClaimId));

        vm.prank(ALICE);
        engine.redeem(badClaimId);
    }

    function testRevertExerciseWhenCallerHoldsInsufficientOptions() public {
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
    }

    function testRevertRedeemWhenCallerDoesNotOwnClaimId() public {
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

    function testRevertRedeemWhenClaimTooSoon() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);

        vm.warp(testExerciseTimestamp - 1 seconds);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ClaimTooSoon.selector, claimId, testExpiryTimestamp)
        );

        engine.redeem(claimId);
    }

    function testRevertUnderlyingWhenTokenNotFound() public {
        uint256 badOptionId = 123;

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, badOptionId));

        engine.underlying(badOptionId);
    }

    function testRevertUriWhenTokenNotFound() public {
        uint256 tokenId = 420;
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, tokenId));
        engine.uri(420);
    }
}
