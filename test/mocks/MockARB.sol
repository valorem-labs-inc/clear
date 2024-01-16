// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import "./MockERC20.sol";

/// @notice Mock for ARB Token
contract MockARB is MockERC20 {
    constructor() MockERC20("ARB", "ARB", 18) {}
}
