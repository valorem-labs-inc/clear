// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "./BaseActor.sol";

contract ProtocolAdmin is BaseActor {
    constructor(OptionSettlementEngine _engine, OptionSettlementEngineInvariantTest _test) BaseActor(_engine, _test) {
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
