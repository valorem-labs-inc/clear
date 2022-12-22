// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

import "./utils/BaseEngineTest.sol";

/// @notice Integration tests for OptionSettlementEngine
contract OptionSettlementIntegrationTest is BaseEngineTest {
    function test_integrationFairAssignment() public {
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

        assertEq(claim1.amountWritten, WAD);
        assertEq(claim1.amountExercised, FixedPointMathLib.divWadDown(1 * 1, 2));

        assertEq(claim2.amountWritten, WAD);
        assertEq(claim2.amountExercised, FixedPointMathLib.divWadDown(1 * 1, 2));

        assertEq(claim3.amountWritten, 2 * WAD);
        assertEq(claim3.amountExercised, 0);

        engine.exercise(testOptionId, 1);

        claim1 = engine.claim(claimId1);
        claim2 = engine.claim(claimId2);
        claim3 = engine.claim(claimId3);

        // 50/50 chance of exercising in first (claim 1 & 2) bucket or second bucket (claim 3)
        // 1 option is written in this claim, two options are exercised in the bucket, and in
        // total, 2 options are written
        assertEq(claim1.amountWritten, WAD);
        assertEq(claim1.amountExercised, FixedPointMathLib.divWadDown(1 * 2, 2));

        assertEq(claim2.amountWritten, WAD);
        assertEq(claim2.amountExercised, FixedPointMathLib.divWadDown(1 * 2, 2));

        assertEq(claim3.amountWritten, 2 * WAD);
        assertEq(claim3.amountExercised, 0);

        // First bucket is fully exercised, this will be performed on the second
        engine.exercise(testOptionId, 1);

        claim1 = engine.claim(claimId1);
        claim2 = engine.claim(claimId2);
        claim3 = engine.claim(claimId3);

        assertEq(claim1.amountWritten, WAD);
        assertEq(claim1.amountExercised, FixedPointMathLib.divWadDown(1 * 2, 2));

        assertEq(claim2.amountWritten, WAD);
        assertEq(claim2.amountExercised, FixedPointMathLib.divWadDown(1 * 2, 2));

        assertEq(claim3.amountWritten, 2 * WAD);
        assertEq(claim3.amountExercised, FixedPointMathLib.divWadDown(2 * 1, 2));

        // Both buckets are fully exercised
        engine.exercise(testOptionId, 1);

        claim1 = engine.claim(claimId1);
        claim2 = engine.claim(claimId2);
        claim3 = engine.claim(claimId3);

        assertEq(claim1.amountWritten, WAD);
        assertEq(claim1.amountExercised, FixedPointMathLib.divWadDown(1 * 2, 2));

        assertEq(claim2.amountWritten, WAD);
        assertEq(claim2.amountExercised, FixedPointMathLib.divWadDown(1 * 2, 2));

        assertEq(claim3.amountWritten, 2 * WAD);
        assertEq(claim3.amountExercised, FixedPointMathLib.divWadDown(2 * 2, 2));
    }

    function test_integrationDustHandling() public {
        // Alice writes a new option
        vm.startPrank(ALICE);
        uint256 optionId = engine.newOptionType(
            address(ERC20A),
            1 ether,
            address(ERC20B),
            15 ether,
            uint40(block.timestamp),
            uint40(block.timestamp + 30 days)
        );
        uint256 claim1 = engine.write(optionId, 1);

        // Alice writes 6 more options on separate claims
        uint256 claim2 = engine.write(optionId, 1);
        uint256 claim3 = engine.write(optionId, 1);
        uint256 claim4 = engine.write(optionId, 1);
        uint256 claim5 = engine.write(optionId, 1);
        uint256 claim6 = engine.write(optionId, 1);
        uint256 claim7 = engine.write(optionId, 1);
        vm.stopPrank();

        // Quick check of Alice balances
        uint256 costToWrite = 1 ether + _calculateFee(1 ether); // underlyingAmount + fee
        assertEq(ERC20A.balanceOf(ALICE), STARTING_BALANCE - (costToWrite * 7), "Alice underlying balance before");
        assertEq(engine.balanceOf(ALICE, optionId), 7, "Alice option balance before");
        assertEq(engine.balanceOf(ALICE, claim1), 1, "Alice claim 1 balance before");
        assertEq(engine.balanceOf(ALICE, claim2), 1, "Alice claim 2 balance before");
        assertEq(engine.balanceOf(ALICE, claim3), 1, "Alice claim 3 balance before");
        assertEq(engine.balanceOf(ALICE, claim4), 1, "Alice claim 4 balance before");
        assertEq(engine.balanceOf(ALICE, claim5), 1, "Alice claim 5 balance before");
        assertEq(engine.balanceOf(ALICE, claim6), 1, "Alice claim 6 balance before");
        assertEq(engine.balanceOf(ALICE, claim7), 1, "Alice claim 7 balance before");

        // Alice sells 1 to Bob
        vm.prank(ALICE);
        engine.safeTransferFrom(ALICE, BOB, optionId, 1, "");

        // Warp right before expiry time and Bob exercises
        vm.warp(block.timestamp + 30 days - 1 seconds);
        vm.prank(BOB);
        engine.exercise(optionId, 1);

        // Check balances after exercise
        // Bob +underlying -exercise, No change to Alice until she redeems
        uint256 costToExercise = 15 ether + _calculateFee(15 ether); // exerciseAmount + fee
        assertEq(ERC20A.balanceOf(BOB), STARTING_BALANCE + 1 ether, "Bob underlying balance after exercise 1");
        assertEq(ERC20B.balanceOf(BOB), STARTING_BALANCE - costToExercise, "Bob exercise balance after exercise 1");

        // Warp to expiry time and Alice redeems 3 claims
        vm.warp(block.timestamp + 1 seconds);
        vm.startPrank(ALICE);
        engine.redeem(claim1);
        engine.redeem(claim3);
        engine.redeem(claim4);
        vm.stopPrank();

        // Check balances after redeeming just 3
        // Alice +underlying +exercise, No change to Bob
        uint256 underlyingRedeemedJust3 = FixedPointMathLib.mulDivDown(1 ether, 4, 7); // 4 partially exercised claims worth of underlyingAsset
        underlyingRedeemedJust3 += 2 ether; // + 2 unexercised claims worth
        uint256 exerciseRedeemedJust3 = FixedPointMathLib.mulDivDown(15 ether, 3, 7); // 3 partially exercised claims worth of exerciseAsset
        // 2 wei lost to dust
        assertEq(
            ERC20A.balanceOf(ALICE),
            STARTING_BALANCE - (costToWrite * 7) + underlyingRedeemedJust3 - 2,
            "Alice underlying balance after redeem just 3"
        );
        assertEq(
            ERC20B.balanceOf(ALICE),
            STARTING_BALANCE + exerciseRedeemedJust3,
            "Alice exercise balance after redeem just 3"
        );

        // Alice redeems remaining 4 claims
        vm.warp(block.timestamp + 1 seconds);
        vm.startPrank(ALICE);
        engine.redeem(claim2);
        engine.redeem(claim5);
        engine.redeem(claim6);
        engine.redeem(claim7);
        vm.stopPrank();

        // Check balances after redeeming all 7
        // Alice +underlying +exercise, No change to Bob
        uint256 underlyingRedeemedAll7 = 1 ether * 6; // 6 claims worth of underlyingAsset
        uint256 exerciseRedeemedAll7 = 15 ether; // 1 claim worth of exerciseAsset
        // 6 wei lost to dust.
        assertEq(
            ERC20A.balanceOf(ALICE),
            STARTING_BALANCE - (costToWrite * 7) + underlyingRedeemedAll7 - 6,
            "Alice underlying balance after redeem all 7"
        );
        // 1 wei lost to dust.
        assertEq(
            ERC20B.balanceOf(ALICE),
            STARTING_BALANCE + exerciseRedeemedAll7 - 1,
            "Alice exercise balance after redeem all 7"
        );
    }
}
