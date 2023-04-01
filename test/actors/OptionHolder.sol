// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import "./BaseActor.sol";

contract OptionHolder is BaseActor {
    constructor(ValoremOptionsClearinghouse _clearinghouse, ValoremOptionsClearinghouseInvariantTest _test)
        BaseActor(_clearinghouse, _test)
    {
        //
    }

    function exercise() external {
        console.logString("exercise");
        uint256[] memory optionTypes = test.getOptionTypes();
        // Retrieve all option types
        for (uint256 i = 0; i < optionTypes.length; i++) {
            uint256 optionType = optionTypes[i];
            uint256 optionBalance = clearinghouse.balanceOf(address(this), optionType);
            // exercise a random amount up to the total balance
            uint256 toExercise = _randBetween(uint32(block.timestamp), optionBalance);
            clearinghouse.exercise(optionType, uint112(toExercise));
        }
    }
}
