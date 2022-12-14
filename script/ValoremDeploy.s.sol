// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import "../src/TokenURIGenerator.sol";
import "../src/OptionSettlementEngine.sol";

contract ValoremDeployScript is Script {
    function run() public {
        // Get environment variables
        address feeTo = vm.envAddress("FEE_TO");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        // Start recording calls and contract creations
        vm.startBroadcast(privateKey);

        // Create contracts
        TokenURIGenerator generator = new TokenURIGenerator();
        OptionSettlementEngine engine = new OptionSettlementEngine(feeTo, address(generator));

        // Stop recording
        vm.stopBroadcast();
    }
}
