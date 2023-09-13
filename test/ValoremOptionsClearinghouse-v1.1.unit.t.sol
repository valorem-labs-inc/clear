// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "solmate/utils/FixedPointMathLib.sol";

import "./utils/BaseClearinghouseTest.sol";

/// @notice Unit tests for ValoremOptionsClearinghouse v1.1.0
contract ValoremOptionsClearinghousev11UnitTest is BaseClearinghouseTest {
    address private constant writer1 = ALICE;
    address private constant writer2 = BOB;
    address private constant writer3 = CAROL;
    address private constant exerciser1 = userD;
    address private constant exerciser2 = userE;

    uint256 private optionId;
    uint256 private claimId1;
    uint256 private claimId2;
    uint256 private claimId3;

    uint256 private optionIdB;
    uint256 private claimId1B;
    uint256 private claimId2B;
    uint256 private claimId3B;

    uint256 private optionId2C;
    uint256 private claimId2C;

    IValoremOptionsClearinghouse.Claim private claimState1;
    IValoremOptionsClearinghouse.Claim private claimState2;
    IValoremOptionsClearinghouse.Claim private claimState3;
    IValoremOptionsClearinghouse.Claim private claimState1B;
    IValoremOptionsClearinghouse.Claim private claimState2B;
    IValoremOptionsClearinghouse.Claim private claimState3B;
    IValoremOptionsClearinghouse.Claim private claimState2C;

    IValoremOptionsClearinghouse.Position private position1;
    IValoremOptionsClearinghouse.Position private position2;
    IValoremOptionsClearinghouse.Position private position3;
    IValoremOptionsClearinghouse.Position private position1B;
    IValoremOptionsClearinghouse.Position private position2B;
    IValoremOptionsClearinghouse.Position private position3B;
    IValoremOptionsClearinghouse.Position private position2C;

    // Scenario A, writer2 nets and redeems, writer1 and writer3 redeem
    uint256 expectedUnderlyingReturnedFromRedeemClaim1;
    uint256 expectedExerciseReturnedFromRedeemClaim1;
    uint256 expectedUnderlyingReturnedFromNetClaim2;
    uint256 expectedExerciseReturnedFromNetClaim2;
    uint256 expectedUnderlyingReturnedFromRedeemClaim2;
    uint256 expectedExerciseReturnedFromRedeemClaim2;
    uint256 expectedUnderlyingReturnedFromRedeemClaim3;
    uint256 expectedExerciseReturnedFromRedeemClaim3;

    // Scenario B, writer2 nets and redeems, writer1 and writer3 redeem
    uint256 expectedUnderlyingReturnedFromRedeemClaim1B;
    uint256 expectedExerciseReturnedFromRedeemClaim1B;
    uint256 expectedUnderlyingReturnedFromNetClaim2B;
    uint256 expectedExerciseReturnedFromNetClaim2B;
    uint256 expectedUnderlyingReturnedFromRedeemClaim2B;
    uint256 expectedExerciseReturnedFromRedeemClaim2B;
    uint256 expectedUnderlyingReturnedFromRedeemClaim3B;
    uint256 expectedExerciseReturnedFromRedeemClaim3B;

    // Scenario C, writer2 nets
    uint256 expectedUnderlyingReturnedFromNetClaim2C;
    uint256 expectedExerciseReturnedFromNetClaim2C;

    uint256 private constant DAWN = 1_000_000 seconds;

    /*//////////////////////////////////////////////////////////////
    // Clearinghouse v1.1.0
    //////////////////////////////////////////////////////////////*/

    // function test_claimAssignmentStatus() public {
    //     uint112 amountWritten = 5;
    //     uint256 expectedFee = _calculateFee(testUnderlyingAmount * amountWritten);
    //     uint256 expectedClaimId = testOptionId + 1;

    //     vm.prank(ALICE);
    //     uint256 claimId = engine.write(testOptionId, amountWritten);

    //     // Post-write conditions
    //     assertEq(claimId, expectedClaimId, "claimId");
    //     assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice Claim NFT");
    //     assertEq(engine.balanceOf(ALICE, testOptionId), amountWritten, "Alice Option tokens");
    //     assertEq(
    //         IERC20(testUnderlyingAsset).balanceOf(ALICE),
    //         STARTING_BALANCE_WETH - (testUnderlyingAmount * amountWritten) - expectedFee,
    //         "Alice underlying"
    //     );
    //     assertEq(IERC20(testExerciseAsset).balanceOf(ALICE), STARTING_BALANCE, "Alice exercise"); // no change
    //     assertEq(engine.feeBalance(testUnderlyingAsset), expectedFee, "Fee balance underlying");
    //     assertEq(engine.feeBalance(testExerciseAsset), 0, "Fee balance exercise"); // no fee assessed on exercise asset during write()

    // Unassigned
    // IValoremOptionsClearinghouse.Claim memory unassigned = engine.claim(claimId);
    // emit log("Unassigned Claim ---------");
    // emit log_named_string("amountWritten", pp(unassigned.amountWritten, 18, 0));
    // emit log_named_string("amountExercised", pp(unassigned.amountExercised, 18, 0));
    // uint256 assignmentPercentage = unassigned.amountExercised / unassigned.amountWritten;
    // emit log_named_uint("percentage", assignmentPercentage);
    // if amountExercised == 0, claim is unassigned

    //     // Partially Assigned
    //     vm.prank(ALICE);
    //     engine.safeTransferFrom(ALICE, BOB, testOptionId, 5, "");

    //     vm.prank(BOB);
    //     engine.exercise(testOptionId, 1);

    // IValoremOptionsClearinghouse.Claim memory partiallyAssigned = engine.claim(claimId);
    // emit log("Partially Assigned Claim ---------");
    // emit log_named_string("amountWritten", pp(partiallyAssigned.amountWritten, 18, 0));
    // emit log_named_string("amountExercised", pp(partiallyAssigned.amountExercised, 18, 0));
    // assignmentPercentage = partiallyAssigned.amountExercised / partiallyAssigned.amountWritten;
    // emit log_named_uint("percentage", assignmentPercentage); // TODO use scalar
    // if amountExercised > 0 && amountWritten > amountExercised, claim is partially assigned

    //     // Fully Assigned
    //     vm.prank(BOB);
    //     engine.exercise(testOptionId, 4);

    // IValoremOptionsClearinghouse.Claim memory fullyAssigned = engine.claim(claimId);
    // emit log("Fully Assigned Claim ---------");
    // emit log_named_string("amountWritten", pp(fullyAssigned.amountWritten, 18, 0));
    // emit log_named_string("amountExercised", pp(fullyAssigned.amountExercised, 18, 0));
    // assignmentPercentage = fullyAssigned.amountExercised / fullyAssigned.amountWritten;
    // emit log_named_uint("percentage", assignmentPercentage);
    // if amountWritten == amountExercised, claim is fully assigned
    // }

    // /*//////////////////////////////////////////////////////////////
    // // net(uint256 optionId) external
    // //////////////////////////////////////////////////////////////*/

    // // TODO

    // function test_net_whenUnassigned() public {
    //     uint256 balanceA = ERC20A.balanceOf(ALICE);
    //     uint256 balanceB = ERC20B.balanceOf(ALICE);

    //     // Alice writes 10 Options
    //     vm.startPrank(ALICE);
    //     uint256 optionId = engine.newOptionType({
    //         underlyingAsset: address(ERC20A),
    //         underlyingAmount: 1 ether,
    //         exerciseAsset: address(ERC20B),
    //         exerciseAmount: 8 ether,
    //         exerciseTimestamp: uint40(block.timestamp),
    //         expiryTimestamp: uint40(block.timestamp + 30 days)
    //     });
    //     uint256 claimId = engine.write(optionId, 10);

    //     uint256 expectedWriteAmount = 10 * 1 ether;

    //     assertEq(engine.balanceOf(ALICE, optionId), 10, "Alice option tokens before");
    //     assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice claim tokens before");
    //     assertEq(
    //         ERC20A.balanceOf(ALICE),
    //         balanceA - expectedWriteAmount - _calculateFee(expectedWriteAmount),
    //         "Alice underlying asset before"
    //     );
    //     assertEq(ERC20B.balanceOf(ALICE), balanceB, "Alice exercise asset before");

    //     // Alice nets offsetting positions after no Options have been exercised
    //     engine.net(claimId);

    //     assertEq(engine.balanceOf(ALICE, optionId), 0, "Alice option tokens after");
    //     assertEq(engine.balanceOf(ALICE, claimId), 0, "Alice claim tokens after");
    //     assertEq(ERC20A.balanceOf(ALICE), balanceA - _calculateFee(expectedWriteAmount), "Alice underlying asset after"); // still less write fee
    //     assertEq(ERC20B.balanceOf(ALICE), balanceB, "Alice exercise asset after");
    // }

    // function test_net_whenPartiallyAssigned() public {
    //     uint256 aliceBalanceA = ERC20A.balanceOf(ALICE);
    //     uint256 aliceBalanceB = ERC20B.balanceOf(ALICE);
    //     uint256 bobBalanceA = ERC20A.balanceOf(BOB);
    //     uint256 bobBalanceB = ERC20B.balanceOf(BOB);

    //     // Alice writes 10 Options
    //     vm.startPrank(ALICE);
    //     uint256 optionId = engine.newOptionType({
    //         underlyingAsset: address(ERC20A),
    //         underlyingAmount: 1 ether,
    //         exerciseAsset: address(ERC20B),
    //         exerciseAmount: 8 ether,
    //         exerciseTimestamp: uint40(block.timestamp),
    //         expiryTimestamp: uint40(block.timestamp + 30 days)
    //     });
    //     uint256 claimId = engine.write(optionId, 10);

    //     uint256 expectedWriteAmount = 10 * 1 ether;
    //     uint256 expectedExerciseAmount = 3 * 8 ether;

    //     assertEq(engine.balanceOf(ALICE, optionId), 10, "Alice option tokens before");
    //     assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice claim tokens before");
    //     assertEq(
    //         ERC20A.balanceOf(ALICE),
    //         aliceBalanceA - expectedWriteAmount - _calculateFee(expectedWriteAmount),
    //         "Alice underlying asset before"
    //     );
    //     assertEq(ERC20B.balanceOf(ALICE), aliceBalanceB, "Alice exercise asset before");

    //     // Alice transfers 3 Options to Bob
    //     engine.safeTransferFrom(ALICE, BOB, optionId, 3, "");
    //     vm.stopPrank();

    //     assertEq(engine.balanceOf(ALICE, optionId), 7, "Alice option tokens after transfer");
    //     assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice claim tokens after transfer");

    //     // Bob exercises 3 Options
    //     vm.prank(BOB);
    //     engine.exercise(optionId, 3);

    //     assertEq(
    //         ERC20A.balanceOf(ALICE),
    //         aliceBalanceA - expectedWriteAmount - _calculateFee(expectedWriteAmount),
    //         "Alice underlying asset after exercise"
    //     );
    //     assertEq(ERC20B.balanceOf(ALICE), aliceBalanceB, "Alice exercise asset after exercise");
    //     assertEq(ERC20A.balanceOf(BOB), bobBalanceA + (3 * 1 ether), "Bob underlying asset after exercise");
    //     assertEq(
    //         ERC20B.balanceOf(BOB),
    //         bobBalanceB - expectedExerciseAmount - _calculateFee(expectedExerciseAmount),
    //         "Bob exercise asset after exercise"
    //     );

    //     // Alice closes remaining 7 Options and gets collateral back from 3 Options that Bob exercised
    //     engine.net(claimId);

    //     assertEq(engine.balanceOf(ALICE, optionId), 0, "Alice option tokens after close");
    //     assertEq(engine.balanceOf(ALICE, claimId), 0, "Alice claim tokens after close");
    //     assertEq(
    //         ERC20A.balanceOf(ALICE),
    //         aliceBalanceA - expectedWriteAmount - _calculateFee(expectedWriteAmount) + (3 * 1 ether),
    //         "Alice underlying asset after close"
    //     );
    //     assertEq(ERC20B.balanceOf(ALICE), aliceBalanceB + expectedExerciseAmount, "Alice exercise asset after close");
    //     assertEq(ERC20A.balanceOf(BOB), bobBalanceA + (3 * 1 ether), "Bob underlying asset after close");
    //     assertEq(
    //         ERC20B.balanceOf(BOB),
    //         bobBalanceB - expectedExerciseAmount - _calculateFee(expectedExerciseAmount),
    //         "Bob exercise asset after close"
    //     );
    // }

    function test_nettable() public {
        // Scenario A, Option Type exerciseAmount is 1750
        // (Scenario B will have Option Type with different settlementSeed -- to explore a different assignment path)
        // (Scenario C will be very basic, only 1 writer, 1 claim, no assignment -- to burn the Claim during net)

        // t = 1

        // writer1 writes 1.15 options, of which exerciser1 takes 1
        vm.startPrank(writer1);
        optionId = engine.newOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: 1e12,
            exerciseAsset: address(USDCLIKE),
            exerciseAmount: 1750,
            exerciseTimestamp: uint40(DAWN + 1 days),
            expiryTimestamp: uint40(DAWN + 8 days)
        });
        claimId1 = engine.write(optionId, 0.01e6); // write 0.01 options, not taken
        engine.write(claimId1, 0.04e6); // write 0.04 options, not taken
        engine.write(claimId1, 0.95e6); // write 0.95 options, taken
        engine.safeTransferFrom(writer1, exerciser1, optionId, 1e6, "");
        engine.write(claimId1, 0.15e6); // write 0.15 options, not taken
        vm.stopPrank();

        // bucket state -- 1 claim, 1 bucket
        // option type inventory check
        assertEq(engine.balanceOf(writer1, optionId), 0.15e6, "writer1 option balance t1");
        assertEq(engine.balanceOf(exerciser1, optionId), 1e6, "exerciser1 option balance t1");

        // t = 2

        // writer2 writes 0.1 options, exerciser2 takes all
        vm.startPrank(writer2);
        claimId2 = engine.write(optionId, 0.1e6);
        engine.safeTransferFrom(writer2, exerciser2, optionId, 0.1e6, "");
        vm.stopPrank();

        // bucket state -- 2 claims, 1 bucket
        // inventory check
        assertEq(engine.balanceOf(writer1, optionId), 0.15e6, "writer1 option balance t2");
        assertEq(engine.balanceOf(exerciser1, optionId), 1e6, "exerciser1 option balance t2");
        assertEq(engine.balanceOf(writer2, optionId), 0, "writer2 option balance t2");
        assertEq(engine.balanceOf(exerciser2, optionId), 0.1e6, "exerciser2 option balance t2");

        // t = 3
        vm.warp(DAWN + 1 days);

        // FIRST EXERCISE -- Bob exercises his 1 option
        vm.prank(exerciser1);
        engine.exercise(optionId, 1e6);

        // inventory check
        assertEq(engine.balanceOf(writer1, optionId), 0.15e6, "writer1 option balance t3");
        assertEq(engine.balanceOf(exerciser1, optionId), 0, "exerciser1 option balance t3");
        assertEq(engine.balanceOf(writer2, optionId), 0, "writer2 option balance t3");
        assertEq(engine.balanceOf(exerciser2, optionId), 0.1e6, "exerciser2 option balance t3");

        // t = 4

        // writer3 writes 0.01 options, no taker
        vm.prank(writer3);
        claimId3 = engine.write(optionId, 0.01e6);

        // writer1 writes 0.75 options, no taker
        vm.prank(writer1);
        engine.write(claimId1, 0.85e6);

        // writer2 writes 0.01 options, no taker
        vm.prank(writer2);
        engine.write(claimId2, 0.01e6);

        // bucket state --
        // B1 contains {Claim 1, Claim 2}
        // B2 contains {Claim 3, Claim 1, Claim 2}

        // inventory check
        assertEq(engine.balanceOf(writer1, optionId), 1e6, "writer1 option balance t4");
        assertEq(engine.balanceOf(exerciser1, optionId), 0, "exerciser1 option balance t4");
        assertEq(engine.balanceOf(writer2, optionId), 0.01e6, "writer2 option balance t4");
        assertEq(engine.balanceOf(exerciser2, optionId), 0.1e6, "exerciser2 option balance t4");
        assertEq(engine.balanceOf(writer3, optionId), 0.01e6, "writer3 option balance t4");

        // t = 5

        // SECOND EXERCISE
        vm.prank(exerciser2);
        engine.exercise(optionId, 0.05e6);

        // inventory check
        assertEq(engine.balanceOf(writer1, optionId), 1e6, "writer1 option balance t5");
        assertEq(engine.balanceOf(exerciser1, optionId), 0, "exerciser1 option balance t5");
        assertEq(engine.balanceOf(writer2, optionId), 0.01e6, "writer2 option balance t5");
        assertEq(engine.balanceOf(exerciser2, optionId), 0.05e6, "exerciser2 option balance t5");
        assertEq(engine.balanceOf(writer3, optionId), 0.01e6, "writer3 option balance t5");

        // t = 6

        // writer1 writes 1 option, no takers
        vm.prank(writer1);
        engine.write(claimId1, 1e6);

        // bucket state --
        // B1 contains {Claim 1, Claim 2}
        // B2 contains {Claim 3, Claim 1, Claim 2}
        // B3 contains {Claim 1}

        // inventory check
        assertEq(engine.balanceOf(writer1, optionId), 2e6, "writer1 option balance t6");
        assertEq(engine.balanceOf(exerciser1, optionId), 0, "exerciser1 option balance t6");
        assertEq(engine.balanceOf(writer2, optionId), 0.01e6, "writer2 option balance t6");
        assertEq(engine.balanceOf(exerciser2, optionId), 0.05e6, "exerciser2 option balance t6");
        assertEq(engine.balanceOf(writer3, optionId), 0.01e6, "writer3 option balance t6");

        claimState1 = engine.claim(claimId1);
        claimState2 = engine.claim(claimId2);
        claimState3 = engine.claim(claimId3);

        console.log("Scenario A ------------------");
        console.log("Claim 1 ----------");
        console.log("amountWritten", claimState1.amountWritten, "amountExercised", claimState1.amountExercised);
        console.log("Claim 2 ----------");
        console.log("amountWritten", claimState2.amountWritten, "amountExercised", claimState2.amountExercised);
        console.log("Claim 3 ----------");
        console.log("amountWritten", claimState3.amountWritten, "amountExercised", claimState3.amountExercised);

        // Scenario B, run the same actions but with a slightly different Option Type, for a different settlementSeed,
        // resulting in a different assignment path
        vm.startPrank(writer1);
        optionIdB = engine.newOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: 1e12,
            exerciseAsset: address(USDCLIKE),
            exerciseAmount: 1746, // slightly less USDC dust, for a different settlementSeed
            exerciseTimestamp: uint40(DAWN + 2 days),
            expiryTimestamp: uint40(DAWN + 9 days) // 1 more day than Option Type A, for staggered redemption ability
        });
        claimId1B = engine.write(optionIdB, 0.01e6);
        engine.write(claimId1B, 0.04e6);
        engine.write(claimId1B, 0.95e6);
        engine.safeTransferFrom(writer1, exerciser1, optionIdB, 1e6, "");
        engine.write(claimId1B, 0.15e6);
        vm.stopPrank();
        vm.startPrank(writer2);
        claimId2B = engine.write(optionIdB, 0.1e6);
        engine.safeTransferFrom(writer2, exerciser2, optionIdB, 0.1e6, "");
        vm.stopPrank();
        vm.warp(DAWN + 2 days);
        vm.prank(exerciser1);
        engine.exercise(optionIdB, 1e6);
        vm.prank(writer3);
        claimId3B = engine.write(optionIdB, 0.01e6);
        vm.prank(writer1);
        engine.write(claimId1B, 0.85e6);
        vm.prank(writer2);
        engine.write(claimId2B, 0.01e6);
        vm.prank(exerciser2);
        engine.exercise(optionIdB, 0.05e6);
        vm.prank(writer1);
        engine.write(claimId1B, 1e6);
        assertEq(engine.balanceOf(writer1, optionIdB), 2e6, "writer1 option balance t6");
        assertEq(engine.balanceOf(exerciser1, optionIdB), 0, "exerciser1 option balance t6");
        assertEq(engine.balanceOf(writer2, optionIdB), 0.01e6, "writer2 option balance t6");
        assertEq(engine.balanceOf(exerciser2, optionIdB), 0.05e6, "exerciser2 option balance t6");
        assertEq(engine.balanceOf(writer3, optionIdB), 0.01e6, "writer3 option balance t6");

        claimState1B = engine.claim(claimId1B);
        claimState2B = engine.claim(claimId2B);
        claimState3B = engine.claim(claimId3B);

        console.log("Scenario B ------------------");
        console.log("Claim 1 ----------");
        console.log("amountWritten", claimState1B.amountWritten, "amountExercised", claimState1B.amountExercised);
        console.log("Claim 2 ----------");
        console.log("amountWritten", claimState2B.amountWritten, "amountExercised", claimState2B.amountExercised);
        console.log("Claim 3 ----------");
        console.log("amountWritten", claimState3B.amountWritten, "amountExercised", claimState3B.amountExercised);

        // Scenario C, 1 writer, 1 claim, 1 bucket, no assigment -- will burn Claim during net()
        vm.startPrank(writer2);
        optionId2C = engine.newOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: 1e12,
            exerciseAsset: address(USDCLIKE),
            exerciseAmount: 1750,
            exerciseTimestamp: uint40(DAWN + 3 days),
            expiryTimestamp: uint40(DAWN + 10 days) // 1 more day than Option Type B, for staggered redemption ability
        });
        claimId2C = engine.write(optionId2C, 1e6);
        vm.stopPrank();

        claimState2C = engine.claim(claimId2C);

        console.log("Scenario C ------------------");
        console.log("Claim 2 ----------");
        console.log("amountWritten", claimState2C.amountWritten, "amountExercised", claimState2C.amountExercised);

        //
        // Summary of current assignment status of each scenario:
        //

        // Scenario A -- writer2 has a claim worth 0.029425287356321839080460 options

        // Options written, by claim
        // 3000000000000000000000000+110000000000000000000000+10000000000000000000000
        // = 3120000.000000000000000000
        // for a total of 3.12 options written (.01+.04+.95+.15+.1+.01+.85+.01+1)

        // Claim assignment status
        // 968850574712643678160919+80574712643678160919540+574712643678160919540
        // = 1049999.999999999999999999
        // for a total of ~1.05 options exercised (1 + .05)

        // Scenario B -- writer2 has a claim worth 0.026 options

        // When they buy 0.0175 options from writer1, and attempt to net()
        // Then sometimes they can, sometimes they can't, depending on assignment path dependence
        // We will use these 2 scenarios to test the functionality of nettable

        // Options written, by claim
        // 3000000000000000000000000+110000000000000000000000+10000000000000000000000
        // = 3120000.000000000000000000
        // for a total of 3.12 options written

        // Claim assignment status (in this path, Claim 3 never got assigned)
        // 966000000000000000000000+84000000000000000000000+0
        // = 1050000.000000000000000000
        // for a total of 1.05 options exercised

        // Scenario C -- writer1 has a claim worth 1 option

        // Options written, by claim
        // 1000000000000000000000000
        // = 1000000.000000000000000000
        // for a total of 1 option written

        // Claim assignment status
        // 0
        // = 0
        // for a total of 0 options exercised

        //
        // Finally, we can test nettable()
        //

        // Scenario A
        uint256 nettableWriter1A = engine.nettable(claimId1);
        uint256 nettableWriter2A = engine.nettable(claimId2);
        uint256 nettableWriter3A = engine.nettable(claimId3);
        assertEq(nettableWriter1A, (claimState1.amountWritten - claimState1.amountExercised) / 1e18);
        assertEq(nettableWriter2A, (claimState2.amountWritten - claimState2.amountExercised) / 1e18);
        assertEq(nettableWriter3A, (claimState3.amountWritten - claimState3.amountExercised) / 1e18);

        // Scenario B
        uint256 nettableWriter1B = engine.nettable(claimId1B);
        uint256 nettableWriter2B = engine.nettable(claimId2B);
        uint256 nettableWriter3B = engine.nettable(claimId3B);
        assertEq(nettableWriter1B, (claimState1B.amountWritten - claimState1B.amountExercised) / 1e18);
        assertEq(nettableWriter2B, (claimState2B.amountWritten - claimState2B.amountExercised) / 1e18);
        assertEq(nettableWriter3B, (claimState3B.amountWritten - claimState3B.amountExercised) / 1e18);

        // Scenario C
        uint256 nettableWriter2C = engine.nettable(claimId2C);
        assertEq(nettableWriter2C, (claimState2C.amountWritten - claimState2C.amountExercised) / 1e18);

        // TODO separate into other test; consider refactoring out a modifier for the text fixture

        //
        // Get positions for each Claim and check amounts available, before getting into actual netting
        //

        // Scenario A
        position1 = engine.position(claimId1);
        position2 = engine.position(claimId2);
        position3 = engine.position(claimId3);

        expectedUnderlyingReturnedFromRedeemClaim1 =
            (1e12 * (claimState1.amountWritten - claimState1.amountExercised)) / 1e18;
        expectedExerciseReturnedFromRedeemClaim1 = (1750 * claimState1.amountExercised) / 1e18;
        assertEq(
            position1.underlyingAmount,
            int256(expectedUnderlyingReturnedFromRedeemClaim1),
            "A -- claim 1 underlying asset avail"
        );
        assertEq(
            position1.exerciseAmount,
            int256(expectedExerciseReturnedFromRedeemClaim1),
            "A -- claim 1 exercise asset avail"
        );

        expectedUnderlyingReturnedFromNetClaim2 = (0.0275e6 * 1e12 * (claimState2.amountWritten - claimState2.amountExercised)) / claimState2.amountWritten;
        console.log("U NET 2A", expectedUnderlyingReturnedFromNetClaim2);
        expectedExerciseReturnedFromNetClaim2 = (0.0275e6 * 1750 * claimState2.amountExercised) / claimState2.amountWritten;
        console.log("E NET 2A", expectedExerciseReturnedFromNetClaim2);
        expectedUnderlyingReturnedFromRedeemClaim2 = (1e12 * (claimState2.amountWritten - claimState2.amountExercised)) / 1e18;
        expectedExerciseReturnedFromRedeemClaim2 = (1750 * claimState2.amountExercised) / 1e18;
        assertEq(
            position2.underlyingAmount,
            int256(expectedUnderlyingReturnedFromRedeemClaim2),
            "A -- claim 2 underlying asset avail"
        );
        assertEq(
            position2.exerciseAmount,
            int256(expectedExerciseReturnedFromRedeemClaim2),
            "A -- claim 2 exercise asset avail"
        );

        expectedUnderlyingReturnedFromRedeemClaim3 = (1e12 * (claimState3.amountWritten - claimState3.amountExercised)) / 1e18;
        expectedExerciseReturnedFromRedeemClaim3 = (1750 * claimState3.amountExercised) / 1e18;
        assertEq(
            position3.underlyingAmount,
            int256(expectedUnderlyingReturnedFromRedeemClaim3),
            "A -- claim 3 underlying asset avail"
        );
        assertEq(
            position3.exerciseAmount,
            int256(expectedExerciseReturnedFromRedeemClaim3),
            "A -- claim 3 exercise asset avail"
        );

        // Scenario B
        position1B = engine.position(claimId1B);
        position2B = engine.position(claimId2B);
        position3B = engine.position(claimId3B);

        expectedUnderlyingReturnedFromRedeemClaim1B = (1e12 * (claimState1B.amountWritten - claimState1B.amountExercised)) / 1e18;
        expectedExerciseReturnedFromRedeemClaim1B = (1746 * claimState1B.amountExercised) / 1e18;
        assertEq(
            position1B.underlyingAmount,
            int256(expectedUnderlyingReturnedFromRedeemClaim1B),
            "B -- claim 1 underlying asset avail"
        );
        assertEq(
            position1B.exerciseAmount,
            int256(expectedExerciseReturnedFromRedeemClaim1B),
            "B -- claim 1 exercise asset avail"
        );

        expectedUnderlyingReturnedFromNetClaim2B = (0.026e6 * 1e12 * (claimState2B.amountWritten - claimState2B.amountExercised)) / claimState2B.amountWritten;
        console.log("U NET 2B", expectedUnderlyingReturnedFromNetClaim2B);
        expectedExerciseReturnedFromNetClaim2B = (0.026e6 * 1746 * claimState2B.amountExercised) / claimState2B.amountWritten;
        console.log("E NET 2B", expectedExerciseReturnedFromNetClaim2B);
        expectedUnderlyingReturnedFromRedeemClaim2B = (1e12 * (claimState2B.amountWritten - claimState2B.amountExercised)) / 1e18;
        expectedExerciseReturnedFromRedeemClaim2B = (1746 * claimState2B.amountExercised) / 1e18;
        assertEq(
            position2B.underlyingAmount,
            int256(expectedUnderlyingReturnedFromRedeemClaim2B),
            "B -- claim 2 underlying asset avail"
        );
        assertEq(
            position2B.exerciseAmount,
            int256(expectedExerciseReturnedFromRedeemClaim2B),
            "B -- claim 2 exercise asset avail"
        );

        expectedUnderlyingReturnedFromRedeemClaim3B = (1e12 * (claimState3B.amountWritten - claimState3B.amountExercised)) / 1e18;
        expectedExerciseReturnedFromRedeemClaim3B = (1746 * claimState3B.amountExercised) / 1e18;
        assertEq(
            position3B.underlyingAmount,
            int256(expectedUnderlyingReturnedFromRedeemClaim3B),
            "B -- claim 3 underlying asset avail"
        );
        assertEq(
            position3B.exerciseAmount,
            int256(expectedExerciseReturnedFromRedeemClaim3B),
            "B -- claim 3 exercise asset avail"
        );

        // Scenario C
        position2C = engine.position(claimId2C);
        expectedUnderlyingReturnedFromNetClaim2C = (1e12 * (claimState2C.amountWritten - claimState2C.amountExercised)) / 1e18;
        expectedExerciseReturnedFromNetClaim2C = (1750 * claimState2C.amountExercised) / 1e18;
        assertEq(
            position2C.underlyingAmount,
            int256(expectedUnderlyingReturnedFromNetClaim2C),
            "C -- claim 1 underlying asset avail"
        );
        assertEq(
            position2C.exerciseAmount,
            int256(expectedExerciseReturnedFromNetClaim2C),
            "C -- claim 1 exercise asset avail"
        );

        //
        // Test net()
        //

        // temporary balance values
        uint256 uBalance;
        uint256 eBalance;

        // writer2 gets 0.0175 options from writer 1
        vm.prank(writer1);
        engine.safeTransferFrom(writer1, writer2, optionId, 0.0175e6, "");

        // Scenario A

        // vm.expectEmit(true, true, true, true); // TODO re-enable and investigate; forge not playing nice
        // emit ClaimNetted(
        //     claimId2,
        //     optionId,
        //     writer2,
        //     0.0275e6,
        //     111,
        //     111
        // );
        uBalance = WETHLIKE.balanceOf(writer2);
        eBalance = USDCLIKE.balanceOf(writer2);
        vm.prank(writer2);
        engine.net(claimId2, 0.0275e6);
        assertEq(engine.balanceOf(writer2, optionId), 0, "A -- writer2 ALL options are burned after net");
        assertEq(engine.balanceOf(writer2, claimId2), 1, "A -- writer2 Claim is not burned after net");
        // TODO implement rest of net()
        assertEq(
            WETHLIKE.balanceOf(writer2),
            uBalance + expectedUnderlyingReturnedFromNetClaim2,
            "A -- writer2 got correct WETHLIKE collateral back from net"
        );
        assertEq(
            USDCLIKE.balanceOf(writer2),
            eBalance + expectedExerciseReturnedFromNetClaim2,
            "A -- writer2 got correct USDCLIKE collateral back from net"
        );

        vm.warp(DAWN + 8 days); // warp to Option Type A expiry

        // Now let's redeem the rest of writer2's claim for the last little bit of collateral
        // TODO

        // Let's redeem the other writers' claims and ensure they also get back the correct collateral
        uBalance = WETHLIKE.balanceOf(writer1);
        eBalance = USDCLIKE.balanceOf(writer1);
        vm.prank(writer1);
        engine.redeem(claimId1);
        assertEq(engine.balanceOf(writer1, claimId1), 0, "A -- writer1 Claim is burned after redeem");
        assertEq(
            WETHLIKE.balanceOf(writer1),
            uBalance + expectedUnderlyingReturnedFromRedeemClaim1,
            "A -- writer1 got correct WETHLIKE collateral back from redeem"
        );
        assertEq(
            USDCLIKE.balanceOf(writer1),
            eBalance + expectedExerciseReturnedFromRedeemClaim1,
            "A -- writer1 got correct USDCLIKE collateral back from redeeem"
        );

        uBalance = WETHLIKE.balanceOf(writer3);
        eBalance = USDCLIKE.balanceOf(writer3);
        vm.prank(writer3);
        engine.redeem(claimId3);
        assertEq(engine.balanceOf(writer3, claimId3), 0, "A -- writer3 Claim is burned after redeem");
        assertEq(
            WETHLIKE.balanceOf(writer3),
            uBalance + expectedUnderlyingReturnedFromRedeemClaim3,
            "A -- writer3 got correct WETHLIKE collateral back from redeem"
        );
        assertEq(
            USDCLIKE.balanceOf(writer3),
            eBalance + expectedExerciseReturnedFromRedeemClaim3,
            "A -- writer3 got correct USDCLIKE collateral back from redeeem"
        );

        // Scenario B

        // Try to net too much, based on current balance (ie, 0.026e6 is nettable but writer2 doesn't hold enough)
        vm.expectRevert(
            abi.encodeWithSelector(
                IValoremOptionsClearinghouse.CallerHoldsInsufficientClaimToNetOptions.selector,
                claimId2B,
                0.026e6,
                engine.nettable(claimId2B)
            )
        );
        vm.prank(writer2);
        engine.net(claimId2B, 0.026e6);

        // Try to net too much, based on amount options nettable (ie, writer2 holds enough but 0.0275e6 isn't nettable)
        vm.prank(writer1);
        engine.safeTransferFrom(writer1, writer2, optionIdB, 0.0175e6, "");

        vm.expectRevert(
            abi.encodeWithSelector(
                IValoremOptionsClearinghouse.CallerHoldsInsufficientClaimToNetOptions.selector,
                claimId2B,
                0.0275e6,
                engine.nettable(claimId2B)
            )
        );
        vm.prank(writer2);
        engine.net(claimId2B, 0.0275e6);

        // Finally, we net a nettable amount (ie, writer2 holds enough and 0.026e6 is nettable)
        // vm.expectEmit(true, true, true, true); // TODO re-enable and investigate; forge not playing nice
        // emit ClaimNetted(
        //     claimId2B,
        //     optionIdB,
        //     writer2,
        //     0.026e6,
        //     111,
        //     111
        // );

        uBalance = WETHLIKE.balanceOf(writer2);
        eBalance = USDCLIKE.balanceOf(writer2);
        vm.prank(writer2);
        engine.net(claimId2B, 0.026e6);
        assertEq(engine.balanceOf(writer2, optionIdB), 0.0275e6 - 0.026e6, "B -- writer2 SOME options burned after net");
        assertEq(engine.balanceOf(writer2, claimId2B), 1, "B -- writer2 Claim is not burned after net");
        // TODO implement rest of net()
        assertEq(
            WETHLIKE.balanceOf(writer2),
            uBalance + expectedUnderlyingReturnedFromNetClaim2B,
            "B -- writer2 got correct WETHLIKE collateral back from net"
        );
        assertEq(
            USDCLIKE.balanceOf(writer2),
            eBalance + expectedExerciseReturnedFromNetClaim2B,
            "B -- writer2 got correct USDCLIKE collateral back from net"
        );

        vm.warp(DAWN + 9 days); // warp to Option Type B expiry

        // Now let's redeem the rest of writer2's claim for the last little bit of collateral
        // TODO

        // Again let's redeem the other writers' claims and ensure they get back the correct collateral from redeem
        uBalance = WETHLIKE.balanceOf(writer1);
        eBalance = USDCLIKE.balanceOf(writer1);
        vm.prank(writer1);
        engine.redeem(claimId1B);
        assertEq(engine.balanceOf(writer1, claimId1B), 0, "B -- writer1 Claim is burned after redeem");
        assertEq(
            WETHLIKE.balanceOf(writer1),
            uBalance + expectedUnderlyingReturnedFromRedeemClaim1B,
            "B -- writer1 got correct WETHLIKE collateral back from redeem"
        );
        assertEq(
            USDCLIKE.balanceOf(writer1),
            eBalance + expectedExerciseReturnedFromRedeemClaim1B,
            "B -- writer1 got correct USDCLIKE collateral back from redeeem"
        );

        uBalance = WETHLIKE.balanceOf(writer3);
        eBalance = USDCLIKE.balanceOf(writer3);
        vm.prank(writer3);
        engine.redeem(claimId3B);
        assertEq(engine.balanceOf(writer3, claimId3B), 0, "B -- writer3 Claim is burned after redeem");
        assertEq(
            WETHLIKE.balanceOf(writer3),
            uBalance + expectedUnderlyingReturnedFromRedeemClaim3B,
            "B -- writer3 got correct WETHLIKE collateral back from redeem"
        );
        assertEq(
            USDCLIKE.balanceOf(writer3),
            eBalance + expectedExerciseReturnedFromRedeemClaim3B,
            "B -- writer3 got correct USDCLIKE collateral back from redeeem"
        );

        // Scenario C
        uBalance = WETHLIKE.balanceOf(writer2);
        eBalance = USDCLIKE.balanceOf(writer2);
        vm.prank(writer2);
        engine.net(claimId2C, 1e6);
        assertEq(engine.balanceOf(writer2, optionId2C), 0, "C -- writer2 ALL options burned after net");
        // TODO implement rest of net()
        assertEq(engine.balanceOf(writer1, claimId2C), 0, "C -- writer2 Claim IS burned after net");
        assertEq(
            WETHLIKE.balanceOf(writer2),
            uBalance + expectedUnderlyingReturnedFromNetClaim2C,
            "C -- writer2 got correct WETHLIKE collateral back from net"
        );
        assertEq(
            USDCLIKE.balanceOf(writer2),
            eBalance + expectedExerciseReturnedFromNetClaim2C,
            "C -- writer2 got correct USDCLIKE collateral back from net"
        );
    }

    // TODO remaining scenarios

    /*//////////////////////////////////////////////////////////////
    // redeem() early
    //////////////////////////////////////////////////////////////*/

    function test_redeem_whenBeforeExpiryAndClaimIsFullyAssigned() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 10);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 10, "");
        vm.stopPrank();

        vm.warp(testExerciseTimestamp);
        vm.prank(BOB);
        engine.exercise(testOptionId, 10);

        // pre-redeem check
        assertEq(
            ERC20(testExerciseAsset).balanceOf(ALICE), STARTING_BALANCE, "Alice exercise asset balance, pre-redeem"
        );

        // vm.warp(testExpiryTimestamp);
        vm.prank(ALICE);
        engine.redeem(claimId);

        // post-redeem check
        uint256 expectedPostRedeemBalance = STARTING_BALANCE + (testExerciseAmount * 10);
        assertEq(
            ERC20(testExerciseAsset).balanceOf(ALICE),
            expectedPostRedeemBalance,
            "Alice exercise asset balance, post-redeem"
        );
    }

    function testRevert_redeem_whenBeforeExpiryAndClaimIsUnassigned() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 2);

        vm.warp(testExpiryTimestamp - 1 seconds);

        vm.expectRevert(
            abi.encodeWithSelector(IValoremOptionsClearinghouse.ClaimTooSoon.selector, claimId, testExpiryTimestamp)
        );

        engine.redeem(claimId);
        vm.stopPrank();
    }

    function testRevert_redeem_whenBeforeExpiryAndClaimIsPartiallyAssigned() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 2);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 2, "");
        vm.stopPrank();

        vm.warp(testExpiryTimestamp - 1 seconds);

        vm.prank(BOB);
        engine.exercise(testOptionId, 1);

        vm.expectRevert(
            abi.encodeWithSelector(IValoremOptionsClearinghouse.ClaimTooSoon.selector, claimId, testExpiryTimestamp)
        );

        vm.prank(ALICE);
        engine.redeem(claimId);
    }
}
