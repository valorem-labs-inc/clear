// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "./BaseActor.sol";

contract OptionHolder is BaseActor {
    constructor(OptionSettlementEngine _engine, OptionSettlementEngineInvariantTest _test) BaseActor(_engine, _test) {
        //
    }

    function exercise() external {
        console.logString("exercise");
        uint256[] memory optionTypes = test.getOptionTypes();
        // Retrieve all option types
        for (uint256 i = 0; i < optionTypes.length; i++) {
            uint256 optionType = optionTypes[i];
            uint256 optionBalance = engine.balanceOf(address(this), optionType);
            // exercise a random amount up to the total balance
            uint256 toExercise = _randBetween(uint32(block.timestamp), optionBalance);
            engine.exercise(optionType, uint112(toExercise));
        }
    }
}
