// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import "../../src/OptionSettlementEngine.sol";
import "../OptionSettlementEngine.invariant.t.sol";

abstract contract BaseActor is StdUtils, CommonBase {
    OptionSettlementEngine internal engine;
    OptionSettlementEngineInvariantTest internal test;

    constructor(OptionSettlementEngine _engine, OptionSettlementEngineInvariantTest _test) {
        engine = _engine;
        test = _test;
    }

    function _randBetween(uint32 seed, uint256 max) internal pure returns (uint256) {
        uint256 h = uint256(keccak256(abi.encode(seed)));
        return h % max;
    }

    function _getRandomElement(uint32 seed, uint256[] memory arr) internal pure returns (uint256) {
        uint256 idx = _randBetween(seed, arr.length);
        return arr[idx];
    }

}
