// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "./BaseActor.sol";

contract ProtocolAdmin is BaseActor {
    constructor(OptionSettlementEngine _engine) BaseActor(_engine) {}

    function setFeesEnabled() external view {
        console.logString("setFeesEnabled");
    }

    function setFeeTo() external view {
        console.logString("setFeeTo");
    }

    function setTokenURIGenerator() external view {
        console.logString("setTokenURIGenerator");
    }

    function sweepFees() external view {
        console.logString("sweepFees");
    }
}
