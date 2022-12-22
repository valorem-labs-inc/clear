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

    function test_unitOptionRevertsWhenDoesNotExist() public {
        uint256 badOptionId = 123;
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, badOptionId));
        engine.option(badOptionId);
    }

    function test_unitOptionReturnsOptionInfo() public {
        IOptionSettlementEngine.Option memory optionInfo = engine.option(testOptionId);
        assertEq(optionInfo.underlyingAsset, testUnderlyingAsset);
        assertEq(optionInfo.underlyingAmount, testUnderlyingAmount);
        assertEq(optionInfo.exerciseAsset, testExerciseAsset);
        assertEq(optionInfo.exerciseAmount, testExerciseAmount);
        assertEq(optionInfo.exerciseTimestamp, testExerciseTimestamp);
        assertEq(optionInfo.expiryTimestamp, testExpiryTimestamp);
    }

    /*//////////////////////////////////////////////////////////////
    //  function claim(uint256 claimId) external view returns (Claim memory claimInfo)
    //////////////////////////////////////////////////////////////*/

    function test_unitClaimRevertsWhenClaimDoesNotExist() public {
        uint256 badClaimId = testOptionId + 69;
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, badClaimId));
        engine.claim(badClaimId);
    }

    function test_unitClaimWrittenOnce() public {
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

    function test_unitClaimWrittenMultiple() public {
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

    function test_unitClaimWrittenMultipleMultipleClaims() public {
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

    /*//////////////////////////////////////////////////////////////
    //  function position(uint256 tokenId) external view returns (Position memory positionInfo);
    //////////////////////////////////////////////////////////////*/

    function test_unitPositionRevertsTokenNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, 1));
        engine.position(1);
    }

    function test_unitPositionOption() public {
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

    function test_unitPositionUnexercisedClaim() public {
        uint112 amountWritten = 69;
        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);

        IOptionSettlementEngine.Position memory position = engine.position(claimId);
        assertEq(position.underlyingAsset, testUnderlyingAsset);
        assertEq(position.underlyingAmount, int256(uint256(testUnderlyingAmount) * amountWritten));
        assertEq(position.exerciseAsset, testExerciseAsset);
        assertEq(position.exerciseAmount, int256(0));
    }

    function test_unitPositionPartiallyExercisedClaim() public {
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

    function test_unitPositionExercisedClaim() public {
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

    /*//////////////////////////////////////////////////////////////
    //  function tokenType(uint256 tokenId) external view returns (TokenType typeOfToken)
    //////////////////////////////////////////////////////////////*/

    function test_unitTokenTypeReturnsNone() public {
        _assertTokenIsNone(127);
    }

    function test_unitTokenTypeReturnsOption() public {
        _assertTokenIsOption(testOptionId);
    }

    function test_unitTokenTypeReturnsClaim() public {
        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);
        _assertTokenIsClaim(claimId);
    }

    /*//////////////////////////////////////////////////////////////
    //  function tokenURIGenerator() external view returns (ITokenURIGenerator uriGenerator)
    //////////////////////////////////////////////////////////////*/

    function test_unitTokenURIGenerator() public view {
        assert(address(engine.tokenURIGenerator()) == address(generator));
    }

    /*//////////////////////////////////////////////////////////////
    //  function feeBalance(address token) external view returns (uint256)
    //////////////////////////////////////////////////////////////*/

    function test_unitFeeBalanceFeeOn() public {
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

    function test_unitFeeBalanceFeeOff() public {
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

    function test_unitFeeBalanceMinimum() public {
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

    function test_unitFeeBps() public {
        assertEq(engine.feeBps(), 5);
    }

    /*//////////////////////////////////////////////////////////////
    //  function feesEnabled() external view returns (bool enabled)
    //////////////////////////////////////////////////////////////*/

    function test_unitFeesEnabled() public {
        assertEq(engine.feesEnabled(), true);
    }

    /*//////////////////////////////////////////////////////////////
    //  function feeTo() external view returns (address)
    //////////////////////////////////////////////////////////////*/

    function test_unitFeeTo() public {
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

    function test_unitNewOptionType() public {
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

    // Fail tests

    function test_unitNewOptionTypeRevertWhenOptionsTypeExists() public {
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

    function test_unitNewOptionTypeRevertWhenExpiryWindowTooShort() public {
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

    function test_unitNewOptionTypeRevertWhenExerciseWindowTooShort() public {
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

    function test_unitNewOptionTypeRevertWhenInvalidAssets() public {
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

    function test_unitNewOptionTypeRevertWhenTotalSuppliesAreTooLowToExercise() public {
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

    /*//////////////////////////////////////////////////////////////
    // function write(uint256 tokenId, uint112 amount) external returns (uint256 claimId)
    //////////////////////////////////////////////////////////////*/

    function test_unitWriteNewClaim() public {
        uint256 expectedFeeAccruedAmount = ((testUnderlyingAmount / 10_000) * engine.feeBps());

        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(testOptionId, address(WETHLIKE), ALICE, expectedFeeAccruedAmount);

        vm.expectEmit(true, true, true, true);
        emit OptionsWritten(testOptionId, ALICE, testOptionId + 1, 1);

        vm.prank(ALICE);
        engine.write(testOptionId, 1);
    }

    function test_unitWriteExistingClaim() public {
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

    function test_unitWriteFeeOff() public {
        vm.prank(FEE_TO);
        engine.setFeesEnabled(false);

        vm.expectEmit(true, true, true, true);
        emit OptionsWritten(testOptionId, ALICE, testOptionId + 1, 1);

        vm.prank(ALICE);
        engine.write(testOptionId, 1);
    }

    // Fail tests

    function test_unitWriteRevertWhenAmountWrittenCannotBeZero() public {
        uint112 invalidWriteAmount = 0;

        vm.expectRevert(IOptionSettlementEngine.AmountWrittenCannotBeZero.selector);

        engine.write(testOptionId, invalidWriteAmount);
    }

    function test_unitWriteRevertWhenInvalidOption() public {
        // Option ID not 0 in lower 96 b
        uint256 invalidOptionId = testOptionId + 1;
        // Option ID not initialized
        invalidOptionId = encodeTokenId(0x1, 0x0);
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidOption.selector, invalidOptionId));
        engine.write(invalidOptionId, 1);
    }

    function test_unitWriteRevertWhenExpiredOption() public {
        vm.warp(testExpiryTimestamp + 1 seconds);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );

        vm.prank(ALICE);
        engine.write(testOptionId, 1);
    }

    function test_unitWriteRevertWhenCallerDoesNotOwnClaimId() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.CallerDoesNotOwnClaimId.selector, claimId));

        vm.prank(BOB);
        engine.write(claimId, 1);
    }

    /*//////////////////////////////////////////////////////////////
    // function redeem(uint256 claimId) external
    //////////////////////////////////////////////////////////////*/

    function test_unitRedeemUnexercised() public {
        vm.startPrank(ALICE);
        uint256 amountWritten = 7;
        uint256 claimId = engine.write(testOptionId, uint112(amountWritten));
        uint256 expectedUnderlyingAmount = testUnderlyingAmount * amountWritten;

        vm.warp(testExpiryTimestamp);

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

    function test_unitRedeemPartialExercise() public {
        vm.startPrank(ALICE);
        uint256 amountWritten = 7;
        uint256 claimId = engine.write(testOptionId, uint112(amountWritten));
        uint256 expectedExerciseAmount = testExerciseAmount * 3;

        vm.warp(testExerciseTimestamp);

        engine.exercise(testOptionId, 3);

        uint256 expectedUnderlyingAmount = testUnderlyingAmount * 11;

        engine.write(claimId, uint112(amountWritten));

        vm.warp(testExpiryTimestamp);

        vm.expectEmit(true, true, true, true);
        emit ClaimRedeemed(claimId, testOptionId, ALICE, expectedExerciseAmount, expectedUnderlyingAmount);

        engine.redeem(claimId);
    }

    function test_unitRedeemExercised() public {
        vm.startPrank(ALICE);
        uint256 amountWritten = 7;
        uint256 claimId = engine.write(testOptionId, uint112(amountWritten));
        uint256 expectedExerciseAmount = testExerciseAmount * amountWritten;

        vm.warp(testExerciseTimestamp);

        engine.exercise(testOptionId, uint112(amountWritten));

        vm.warp(testExpiryTimestamp);

        vm.expectEmit(true, true, true, true);
        emit ClaimRedeemed(claimId, testOptionId, ALICE, expectedExerciseAmount, 0);

        engine.redeem(claimId);
    }

    // Fail tests

    function test_unitRedeemRevertWhenInvalidClaim() public {
        uint256 badClaimId = encodeTokenId(0xDEADBEEF, 0);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidClaim.selector, badClaimId));

        vm.prank(ALICE);
        engine.redeem(badClaimId);
    }

    function test_unitRedeemRevertWhenCallerDoesNotOwnClaimId() public {
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

    function test_unitRedeemRevertWhenClaimTooSoon() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);

        vm.warp(testExerciseTimestamp - 1 seconds);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ClaimTooSoon.selector, claimId, testExpiryTimestamp)
        );

        engine.redeem(claimId);
    }

    /*//////////////////////////////////////////////////////////////
    // function exercise(uint256 optionId, uint112 amount) external
    //////////////////////////////////////////////////////////////*/

    function test_unitExercise() public {
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        // Fast-forward to exercise
        vm.warp(testExerciseTimestamp);

        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(testOptionId, address(DAILIKE), BOB, _calculateFee(testExerciseAmount));

        vm.expectEmit(true, true, true, true);
        emit OptionsExercised(testOptionId, BOB, 1);

        // Bob exercises
        vm.startPrank(BOB);
        engine.exercise(testOptionId, 1);
        vm.stopPrank();
    }

    // Fail tests

    function test_unitExerciseRevertWhenInvalidOption() public {
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);

        uint256 invalidOptionId = testOptionId + 1;

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidOption.selector, invalidOptionId));

        engine.exercise(invalidOptionId, 1);
    }

    function test_unitExerciseRevertWhenExpiredOption() public {
        // ====== Exercise after Expiry =======
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

    function test_unitExerciseRevertWhenExerciseTooEarly() public {
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

    function test_unitExerciseRevertWhenCallerHoldsInsufficientOptions() public {
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

    /*//////////////////////////////////////////////////////////////
    // function setFeesEnabled(bool enabled) external
    //////////////////////////////////////////////////////////////*/

    function test_unitSetFeesEnabled() public {
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

        assertTrue(engine.feesEnabled());
    }

    // Fail tests

    function test_unitSetFeesEnabledRevertWhenNotFeeTo() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.AccessControlViolation.selector, ALICE, FEE_TO));

        vm.prank(ALICE);
        engine.setFeesEnabled(true);
    }

    /*//////////////////////////////////////////////////////////////
    // function setFeeTo(address newFeeTo) external
    //////////////////////////////////////////////////////////////*/

    function test_unitSetFeeTo() public {
        // precondition check
        assertEq(engine.feeTo(), FEE_TO);

        vm.expectEmit(true, true, true, true);
        emit FeeToUpdated(address(0xCAFE));

        vm.prank(FEE_TO);
        engine.setFeeTo(address(0xCAFE));

        assertEq(engine.feeTo(), address(0xCAFE));
    }

    function test_unitSetFeeToRevertWhenNotCurrentFeeTo() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.AccessControlViolation.selector, ALICE, FEE_TO));
        vm.prank(ALICE);
        engine.setFeeTo(address(0xCAFE));
    }

    function test_unitSetFeeToRevertWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));
        vm.prank(FEE_TO);
        engine.setFeeTo(address(0));
    }

    /*//////////////////////////////////////////////////////////////
    // function setTokenURIGenerator(address newTokenURIGenerator) external
    //////////////////////////////////////////////////////////////*/

    function test_unitSetTokenURIGenerator() public {
        TokenURIGenerator newTokenURIGenerator = new TokenURIGenerator();

        vm.expectEmit(true, true, true, true);
        emit TokenURIGeneratorUpdated(address(newTokenURIGenerator));

        vm.prank(FEE_TO);
        engine.setTokenURIGenerator(address(newTokenURIGenerator));

        assertEq(address(engine.tokenURIGenerator()), address(newTokenURIGenerator));
    }

    // Fail tests

    function test_unitSetTokenURIGeneratorRevertWhenNotCurrentFeeTo() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.AccessControlViolation.selector, ALICE, FEE_TO));
        vm.prank(ALICE);
        engine.setTokenURIGenerator(address(0xCAFE));
    }

    function test_unitSetTokenURIGeneratorRevertWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));
        vm.prank(FEE_TO);
        engine.setTokenURIGenerator(address(0));
    }

    /*//////////////////////////////////////////////////////////////
    // function sweepFees(address[] memory tokens) external
    //////////////////////////////////////////////////////////////*/

    function test_unitSweepNoFees() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(DAILIKE);
        tokens[1] = address(WETHLIKE);
        tokens[2] = address(USDCLIKE);
        engine.sweepFees(tokens);
    }

    function test_unitSweepFees() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(WETHLIKE);
        tokens[1] = address(DAILIKE);
        vm.prank(ALICE);
        engine.write(testOptionId, 10);
        vm.warp(testExerciseTimestamp);
        vm.prank(ALICE);
        engine.exercise(testOptionId, 10);

        uint256 wethFee = _calculateFee(10 * testUnderlyingAmount);
        uint256 daiFee = _calculateFee(10 * testExerciseAmount);

        emit FeeSwept(testExerciseAsset, FEE_TO, daiFee);
        emit FeeSwept(testUnderlyingAsset, FEE_TO, wethFee);
    engine.sweepFees(tokens);

    }

    /*//////////////////////////////////////////////////////////////
    // function uri(uint256 tokenId) public view virtual override returns (string memory)
    //////////////////////////////////////////////////////////////*/

    function test_unitUri() public view {
        engine.uri(testOptionId);
    }

    // Fail tests

    function test_unitUriRevertWhenTokenNotFound() public {
        uint256 tokenId = 420;
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, tokenId));
        engine.uri(420);
    }

    /*//////////////////////////////////////////////////////////////
    // constructor(address _feeTo, address _tokenURIGenerator)
    //////////////////////////////////////////////////////////////*/

    function test_unitConstructorRevertWhenFeeToIsZeroAddress() public {
        TokenURIGenerator localGenerator = new TokenURIGenerator();

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));

        new OptionSettlementEngine(address(0), address(localGenerator));
    }

    function test_unitConstructorRevertWhenTokenURIGeneratorIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));

        new OptionSettlementEngine(FEE_TO, address(0));
    }
}
