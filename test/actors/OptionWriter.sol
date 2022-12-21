// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "./BaseActor.sol";

contract OptionWriter is BaseActor {
    constructor(OptionSettlementEngine _engine, OptionSettlementEngineInvariantTest _test) BaseActor(_engine, _test) {
    }

    function newOptionType() external {
        console.logString("newOptionType");
    }

    function writeNew() external {
        console.logString("writeNew");
    }

    function writeExisting() external {
        console.logString("writeExisting");
    }

    function redeem() external {
        console.logString("redeem");
    }
}
