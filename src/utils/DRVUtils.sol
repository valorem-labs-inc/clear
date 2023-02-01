// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import {Math} from "./Math.sol";

/// TODO
library DRVUtils {

    /// TODO
    function calculateRangeNumber(uint256 weight) public returns (uint256 rangeNumber) {
        rangeNumber = Math.floor(Math.log2(weight)) + 1;
    }

    /// TODO
    function calculateToleranceBounds(uint256 b, uint256 j) public returns (uint256 toleranceLowerBound, uint256 toleranceUpperBound) {
        toleranceLowerBound = (1-b) * (2**(j-1));
        toleranceUpperBound = (2+b) * (2**(j-1));
    }

    /// TODO
    function calculateDegreeBound(uint256 b, uint256 c) public returns (uint256 d) {
        d = (((1-b)/(2+b))**2 * 2**c) / 2;
    }

    /// TODO
    function isElementOfHalfOpenRange(uint256 x, uint256 lowerBound, uint256 upperBound) public returns (bool within) {
        within = x >= lowerBound && x < upperBound;
    }
}
