// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../src/OptionSettlementEngine.sol";

abstract contract BaseActor is StdUtils, CommonBase {
    OptionSettlementEngine internal engine;

    constructor(OptionSettlementEngine _engine) {
        engine = _engine;

        //
    }
}
