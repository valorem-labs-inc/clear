// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "solmate/utils/FixedPointMathLib.sol";
import {pp, SolPretty} from "SolPretty/SolPretty.sol";

import "./utils/BaseClearinghouseTest.sol";

/// @notice Unit tests for ValoremOptionsClearinghouse v1.1.0
contract ValoremOptionsClearinghousev11UnitTest is BaseClearinghouseTest {
    using SolPretty for string;

    /*//////////////////////////////////////////////////////////////
    // Clearinghouse v1.1.0
    //////////////////////////////////////////////////////////////*/

    function test_claimAssignmentStatus() public {
        uint112 amountWritten = 5;
        uint256 expectedFee = _calculateFee(testUnderlyingAmount * amountWritten);
        uint256 expectedClaimId = testOptionId + 1;

        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);

        // Post-write conditions
        assertEq(claimId, expectedClaimId, "claimId");
        assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice Claim NFT");
        assertEq(engine.balanceOf(ALICE, testOptionId), amountWritten, "Alice Option tokens");
        assertEq(
            IERC20(testUnderlyingAsset).balanceOf(ALICE),
            STARTING_BALANCE_WETH - (testUnderlyingAmount * amountWritten) - expectedFee,
            "Alice underlying"
        );
        assertEq(IERC20(testExerciseAsset).balanceOf(ALICE), STARTING_BALANCE, "Alice exercise"); // no change
        assertEq(engine.feeBalance(testUnderlyingAsset), expectedFee, "Fee balance underlying");
        assertEq(engine.feeBalance(testExerciseAsset), 0, "Fee balance exercise"); // no fee assessed on exercise asset during write()

        // Unassigned
        IValoremOptionsClearinghouse.Claim memory unassigned = engine.claim(claimId);
        emit log("Unassigned Claim ---------");
        emit log_named_string("amountWritten", pp(unassigned.amountWritten, 18, 0));
        emit log_named_string("amountExercised", pp(unassigned.amountExercised, 18, 0));
        uint256 assignmentPercentage = unassigned.amountExercised / unassigned.amountWritten;
        emit log_named_uint("percentage", assignmentPercentage);
        // if amountExercised == 0, claim is unassigned

        // Partially Assigned
        vm.prank(ALICE);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 5, "");

        vm.prank(BOB);
        engine.exercise(testOptionId, 1);

        IValoremOptionsClearinghouse.Claim memory partiallyAssigned = engine.claim(claimId);
        emit log("Partially Assigned Claim ---------");
        emit log_named_string("amountWritten", pp(partiallyAssigned.amountWritten, 18, 0));
        emit log_named_string("amountExercised", pp(partiallyAssigned.amountExercised, 18, 0));
        assignmentPercentage = partiallyAssigned.amountExercised / partiallyAssigned.amountWritten;
        emit log_named_uint("percentage", assignmentPercentage); // TODO use scalar
        // if amountExercised > 0 && amountWritten > amountExercised, claim is partially assigned

        // Fully Assigned
        vm.prank(BOB);
        engine.exercise(testOptionId, 4);

        IValoremOptionsClearinghouse.Claim memory fullyAssigned = engine.claim(claimId);
        emit log("Fully Assigned Claim ---------");
        emit log_named_string("amountWritten", pp(fullyAssigned.amountWritten, 18, 0));
        emit log_named_string("amountExercised", pp(fullyAssigned.amountExercised, 18, 0));
        assignmentPercentage = fullyAssigned.amountExercised / fullyAssigned.amountWritten;
        emit log_named_uint("percentage", assignmentPercentage);
        // if amountWritten == amountExercised, claim is fully assigned
    }

    /*//////////////////////////////////////////////////////////////
    // net(uint256 optionId) external
    //////////////////////////////////////////////////////////////*/

    // TODO

    function test_net_whenUnassigned() public {
        uint256 balanceA = ERC20A.balanceOf(ALICE);
        uint256 balanceB = ERC20B.balanceOf(ALICE);

        // Alice writes 10 Options
        vm.startPrank(ALICE);
        uint256 optionId = engine.newOptionType({
            underlyingAsset: address(ERC20A),
            underlyingAmount: 1 ether,
            exerciseAsset: address(ERC20B),
            exerciseAmount: 8 ether,
            exerciseTimestamp: uint40(block.timestamp),
            expiryTimestamp: uint40(block.timestamp + 30 days)
        });
        uint256 claimId = engine.write(optionId, 10);

        uint256 expectedWriteAmount = 10 * 1 ether;

        assertEq(engine.balanceOf(ALICE, optionId), 10, "Alice option tokens before");
        assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice claim tokens before");
        assertEq(
            ERC20A.balanceOf(ALICE),
            balanceA - expectedWriteAmount - _calculateFee(expectedWriteAmount),
            "Alice underlying asset before"
        );
        assertEq(ERC20B.balanceOf(ALICE), balanceB, "Alice exercise asset before");

        // Alice nets offsetting positions after no Options have been exercised
        engine.net(claimId);

        assertEq(engine.balanceOf(ALICE, optionId), 0, "Alice option tokens after");
        assertEq(engine.balanceOf(ALICE, claimId), 0, "Alice claim tokens after");
        assertEq(ERC20A.balanceOf(ALICE), balanceA - _calculateFee(expectedWriteAmount), "Alice underlying asset after"); // still less write fee
        assertEq(ERC20B.balanceOf(ALICE), balanceB, "Alice exercise asset after");
    }

    function test_net_whenPartiallyAssigned() public {
        uint256 aliceBalanceA = ERC20A.balanceOf(ALICE);
        uint256 aliceBalanceB = ERC20B.balanceOf(ALICE);
        uint256 bobBalanceA = ERC20A.balanceOf(BOB);
        uint256 bobBalanceB = ERC20B.balanceOf(BOB);

        // Alice writes 10 Options
        vm.startPrank(ALICE);
        uint256 optionId = engine.newOptionType({
            underlyingAsset: address(ERC20A),
            underlyingAmount: 1 ether,
            exerciseAsset: address(ERC20B),
            exerciseAmount: 8 ether,
            exerciseTimestamp: uint40(block.timestamp),
            expiryTimestamp: uint40(block.timestamp + 30 days)
        });
        uint256 claimId = engine.write(optionId, 10);

        uint256 expectedWriteAmount = 10 * 1 ether;
        uint256 expectedExerciseAmount = 3 * 8 ether;

        assertEq(engine.balanceOf(ALICE, optionId), 10, "Alice option tokens before");
        assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice claim tokens before");
        assertEq(
            ERC20A.balanceOf(ALICE),
            aliceBalanceA - expectedWriteAmount - _calculateFee(expectedWriteAmount),
            "Alice underlying asset before"
        );
        assertEq(ERC20B.balanceOf(ALICE), aliceBalanceB, "Alice exercise asset before");

        // Alice transfers 3 Options to Bob
        engine.safeTransferFrom(ALICE, BOB, optionId, 3, "");
        vm.stopPrank();

        assertEq(engine.balanceOf(ALICE, optionId), 7, "Alice option tokens after transfer");
        assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice claim tokens after transfer");

        // Bob exercises 3 Options
        vm.prank(BOB);
        engine.exercise(optionId, 3);

        assertEq(
            ERC20A.balanceOf(ALICE),
            aliceBalanceA - expectedWriteAmount - _calculateFee(expectedWriteAmount),
            "Alice underlying asset after exercise"
        );
        assertEq(ERC20B.balanceOf(ALICE), aliceBalanceB, "Alice exercise asset after exercise");
        assertEq(ERC20A.balanceOf(BOB), bobBalanceA + (3 * 1 ether), "Bob underlying asset after exercise");
        assertEq(
            ERC20B.balanceOf(BOB),
            bobBalanceB - expectedExerciseAmount - _calculateFee(expectedExerciseAmount),
            "Bob exercise asset after exercise"
        );

        // Alice closes remaining 7 Options and gets collateral back from 3 Options that Bob exercised
        engine.net(claimId);

        assertEq(engine.balanceOf(ALICE, optionId), 0, "Alice option tokens after close");
        assertEq(engine.balanceOf(ALICE, claimId), 0, "Alice claim tokens after close");
        assertEq(
            ERC20A.balanceOf(ALICE),
            aliceBalanceA - expectedWriteAmount - _calculateFee(expectedWriteAmount) + (3 * 1 ether),
            "Alice underlying asset after close"
        );
        assertEq(ERC20B.balanceOf(ALICE), aliceBalanceB + expectedExerciseAmount, "Alice exercise asset after close");
        assertEq(ERC20A.balanceOf(BOB), bobBalanceA + (3 * 1 ether), "Bob underlying asset after close");
        assertEq(
            ERC20B.balanceOf(BOB),
            bobBalanceB - expectedExerciseAmount - _calculateFee(expectedExerciseAmount),
            "Bob exercise asset after close"
        );
    }

    function test_netScenario() public {
        address writer1 = ALICE;
        address writer2 = BOB;
        address writer3 = CAROL;
        address exerciser1 = userD;
        address exerciser2 = userE;

        // t = 1

        // writer1 writes 1.15 options, of which exerciser1 takes 1
        vm.startPrank(writer1);
        uint256 optionId = engine.newOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: 1e12,
            exerciseAsset: address(USDCLIKE),
            exerciseAmount: 1750,
            exerciseTimestamp: uint40(block.timestamp + 1 days),
            expiryTimestamp: uint40(block.timestamp + 8 days)
        });
        uint256 claimId1 = engine.write(optionId, 0.01e6); // write 0.01 options, not taken
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
        uint256 claimId2 = engine.write(optionId, 0.1e6);
        engine.safeTransferFrom(writer2, exerciser2, optionId, 0.1e6, "");
        vm.stopPrank();

        // bucket state -- 2 claims, 1 bucket
        // inventory check
        assertEq(engine.balanceOf(writer1, optionId), 0.15e6, "writer1 option balance t2");
        assertEq(engine.balanceOf(exerciser1, optionId), 1e6, "exerciser1 option balance t2");
        assertEq(engine.balanceOf(writer2, optionId), 0, "writer2 option balance t2");
        assertEq(engine.balanceOf(exerciser2, optionId), 0.1e6, "exerciser2 option balance t2");

        // t = 3
        vm.warp(block.timestamp + 1 days);
    
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
        uint256 claimId3 = engine.write(optionId, 0.01e6);

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

        IValoremOptionsClearinghouse.Claim memory claimState1 = engine.claim(claimId1);
        IValoremOptionsClearinghouse.Claim memory claimState2 = engine.claim(claimId2);
        IValoremOptionsClearinghouse.Claim memory claimState3 = engine.claim(claimId3);

        console.log("Claim 1 ------------");
        console.log("amountWritten", claimState1.amountWritten, "amountExercised", claimState1.amountExercised);
        console.log("Claim 2 ------------");
        console.log("amountWritten", claimState2.amountWritten, "amountExercised", claimState2.amountExercised);
        console.log("Claim 3 ------------");
        console.log("amountWritten", claimState3.amountWritten, "amountExercised", claimState3.amountExercised);

        // 3000000000000000000000000+110000000000000000000000+10000000000000000000000
        // = 3120000.000000000000000000
        // for a total of 3.12 options written (.01+.04+.95+.15+.1+.01+.85+.01+1)

        // 968850574712643678160919+80574712643678160919540+574712643678160919540
        // = 1049999.999999999999999999
        // for a total of ~1.05 options exercised (1 + .05)

        // writer1 has a claim worth 2031149.425287356321839081 options

        // other pseudorandom assignment selection, by changing exercise amount
        /*
        Claim 1 ------------
        amountWritten 3000000000000000000000000 amountExercised 966000000000000000000000
        Claim 2 ------------
        amountWritten 110000000000000000000000 amountExercised 84000000000000000000000
        Claim 3 ------------
        amountWritten 10000000000000000000000 amountExercised 0
         */

        //
    }

    // TODO remaining scenarios

    /*//////////////////////////////////////////////////////////////
    // redeem() early
    //////////////////////////////////////////////////////////////*/

    // TODO
}
