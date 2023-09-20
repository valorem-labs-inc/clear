// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import "./MockERC20.sol";

/// @notice Mock for USDC Stablecoin
contract MockUSDC is MockERC20 {
    constructor() MockERC20("USDC Stablecoin", "USDC", 6) {}
}
