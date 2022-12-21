// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../src/OptionSettlementEngine.sol";
import "../OptionSettlementEngine.invariant.t.sol";

abstract contract BaseActor is StdUtils, CommonBase {
    OptionSettlementEngine internal engine;
    OptionSettlementEngineInvariantTest private test;

    constructor(OptionSettlementEngine _engine, OptionSettlementEngineInvariantTest _test) {
        engine = _engine;
        test = _test;
        //
    }
}
