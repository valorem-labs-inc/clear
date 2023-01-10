// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "solmate/utils/CREATE3.sol";

contract ValoremDeployer {
    function deploy(bytes32 salt, bytes memory creationCode, uint256 value) public returns (address) {
        return CREATE3.deploy(salt, creationCode, value);
    }
}
