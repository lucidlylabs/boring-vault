// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

// source .env && forge script script/Governance/DeployVaultTimelock.s.sol:DeployVaultTimelock --sig "run(string)" syUSDT.json --broadcast --verify

contract DeployVaultTimelock is Script {
    using stdJson for string;

    function run(string memory configFileName) external {
        string memory path =
            string.concat(vm.projectRoot(), "/deployments/governance/", configFileName);
        string memory json = vm.readFile(path);

        string memory chainName = json.readString(".chainName");
        uint256 privateKey = vm.envUint(json.readString(".privateKeyEnvName"));
        address multisig = json.readAddress(".multisig");
        uint256 minDelay = json.readUint(".minDelaySeconds");

        require(multisig != address(0), "multisig not set in config");
        require(minDelay > 0, "minDelaySeconds not set in config");

        vm.createSelectFork(chainName);

        // The multisig is the sole proposer, executor, and admin of the timelock.
        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        address[] memory executors = new address[](1);
        executors[0] = multisig;

        vm.startBroadcast(privateKey);
        TimelockController timelock = new TimelockController(minDelay, proposers, executors, multisig);
        vm.stopBroadcast();

        console.log("==================================================");
        console.log("Timelock deployed for vault:", json.readString(".vaultName"));
        console.log("  chain:               ", chainName);
        console.log("  timelock address:    ", address(timelock));
        console.log("  minDelay (seconds):  ", minDelay);
        console.log("  proposer/executor:   ", multisig);
        console.log("  admin:               ", multisig);
        console.log("--------------------------------------------------");
        console.log("ACTION: paste the timelock address into the");
        console.log("'timelock' field of deployments/governance/", configFileName);
        console.log("==================================================");
    }
}
