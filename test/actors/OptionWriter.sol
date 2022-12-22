// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "./BaseActor.sol";

contract OptionWriter is BaseActor {
    constructor(OptionSettlementEngine _engine) BaseActor(_engine) {}

    function newOptionType() external view {
        console.logString("newOptionType");
    }

    function writeNew() external view {
        console.logString("writeNew");
    }

    function writeExisting() external view {
        console.logString("writeExisting");
    }

    function redeem() external view {
        console.logString("redeem");
    }
}
