// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import "solmate/utils/FixedPointMathLib.sol";
import "forge-std/Test.sol";
import {pp, SolPretty} from "SolPretty/SolPretty.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

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
    // net()
    //////////////////////////////////////////////////////////////*/

    // TODO

    /*//////////////////////////////////////////////////////////////
    // redeem() early
    //////////////////////////////////////////////////////////////*/

    // TODO
}
