// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import "../src/TokenURIGenerator.sol";
import "../src/OptionSettlementEngine.sol";

interface ValoremDeployer {
    function deploy(bytes32 salt, bytes memory creationCode, uint256 value) external returns (address);
}

contract DeployScript is Script {
    // forge create script/ValoremDeployer.sol:ValoremDeployer --rpc-url=$GOERLI_RPC_URL --private-key=$PRIVATE_KEY --libraries solmate/utils/CREATE3.sol:CREATE3:0x90FDFbBDb263856F9CDc10450a9A76a1c99F70B2
    address private constant DEPLOYER = 0xFF24f7bb65F734f1B3bB160d1CE214dCaC0b5Ef8;

    function run() public {
        // Set environment variables and salt
        address feeTo = vm.envAddress("FEE_TO");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        // Deploy TokenURIGenerator
        vm.startBroadcast(privateKey);
        address generator = ValoremDeployer(DEPLOYER).deploy(
            keccak256(bytes("Permissionless physically settled options, on any ERC20 token. -- TokenURIGenerator")),
            abi.encodePacked(type(TokenURIGenerator).creationCode),
            0
        );
        vm.stopBroadcast();

        // Deploy OptionSettlementEngine
        vm.startBroadcast(privateKey);
        ValoremDeployer(DEPLOYER).deploy(
            keccak256(bytes("Permissionless physically settled options, on any ERC20 token. -- OptionSettlementEngine")),
            abi.encodePacked(type(OptionSettlementEngine).creationCode, abi.encode(feeTo, generator)),
            0
        );
        vm.stopBroadcast();
    }
}
