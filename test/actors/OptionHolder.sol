// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "./BaseActor.sol";

contract OptionHolder is BaseActor {
    constructor(OptionSettlementEngine _engine, OptionSettlementEngineInvariantTest _test) BaseActor(_engine, _test) {
        //
    }

    function exercise() external {
        console.logString("exercise");
    }
}
