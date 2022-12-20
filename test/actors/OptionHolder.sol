// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "./BaseActor.sol";

contract OptionHolder is BaseActor {
    constructor(OptionSettlementEngine _engine) BaseActor(_engine) {
        //
    }

    function exercise() external {
        console.logString("exercise");
    }
}
