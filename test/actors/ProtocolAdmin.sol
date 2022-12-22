// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "./BaseActor.sol";

contract ProtocolAdmin is BaseActor {
    constructor(OptionSettlementEngine _engine) BaseActor(_engine) {
        //
    }

    function setFeesEnabled() external {
        console.logString("setFeesEnabled");
    }

    function setFeeTo() external {
        console.logString("setFeeTo");
    }

    function setTokenURIGenerator() external {
        console.logString("setTokenURIGenerator");
    }

    function sweepFees() external {
        console.logString("sweepFees");
    }
}
