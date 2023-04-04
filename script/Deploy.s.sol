// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import "../src/TokenURIGenerator.sol";
import "../src/ValoremOptionsClearinghouse.sol";

contract DeployScript is Script {
    // Command to deploy:
    // forge script script/Deploy.s.sol --rpc-url=<RPC_URL> --broadcast --slow

    function run() public {
        // Get environment variables.
        address feeTo = vm.envAddress("FEE_TO");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        bytes32 saltGenerator = keccak256(bytes(vm.envString("SALT_GENERATOR")));
        bytes32 saltEngine = keccak256(bytes(vm.envString("SALT_ENGINE")));

        // Deploy TokenURIGenerator.
        vm.startBroadcast(privateKey);
        TokenURIGenerator generator = new TokenURIGenerator{salt: saltGenerator}();
        vm.stopBroadcast();

        // Deploy ValoremOptionsClearinghouse.
        vm.startBroadcast(privateKey);
        new ValoremOptionsClearinghouse{salt: saltEngine}(feeTo, address(generator));
        vm.stopBroadcast();
    }
}
