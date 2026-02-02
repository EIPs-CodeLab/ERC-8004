// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/IdentityRegistry.sol";
import "../src/ReputationRegistry.sol";
import "../src/ValidationRegistry.sol";

contract DeployERC8004 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Identity Registry
        IdentityRegistry identityRegistry = new IdentityRegistry();
        console.log("IdentityRegistry deployed at:", address(identityRegistry));

        // 2. Deploy Reputation Registry (linked to IdentityRegistry)
        ReputationRegistry reputationRegistry = new ReputationRegistry(address(identityRegistry));
        console.log("ReputationRegistry deployed at:", address(reputationRegistry));

        // 3. Deploy Validation Registry (linked to IdentityRegistry)
        ValidationRegistry validationRegistry = new ValidationRegistry(address(identityRegistry));
        console.log("ValidationRegistry deployed at:", address(validationRegistry));

        vm.stopBroadcast();
        
        string memory iAddr = vm.toString(address(identityRegistry));
        string memory rAddr = vm.toString(address(reputationRegistry));
        string memory vAddr = vm.toString(address(validationRegistry));

        console.log("IdentityRegistry verification:");
        console.log(string.concat("forge verify-contract --chain sepolia ", iAddr, " src/IdentityRegistry.sol:IdentityRegistry"));
        
        console.log("ReputationRegistry verification:");
        console.log(string.concat("forge verify-contract --chain sepolia ", rAddr, " src/ReputationRegistry.sol:ReputationRegistry --constructor-args $(cast abi-encode \"constructor(address)\" ", iAddr, ")"));
        
        console.log("ValidationRegistry verification:");
        console.log(string.concat("forge verify-contract --chain sepolia ", vAddr, " src/ValidationRegistry.sol:ValidationRegistry --constructor-args $(cast abi-encode \"constructor(address)\" ", iAddr, ")"));
    }
}
