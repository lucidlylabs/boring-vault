// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {
    LucidlyMorphoPriceAggregatorV3WrapperV1
} from "src/adapters/oracle/LucidlyMorphoPriceAggregatorV3WrapperV1.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

contract DeployLucidlyMorphoPriceAggregatorV3WrapperV1Script is Script {
    using stdJson for string;

    function run(string memory configFile) external {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/oracles/", configFile);
        string memory json = vm.readFile(path);

        vm.createSelectFork("mainnet");

        vm.startBroadcast(vm.envUint(json.readString(".privateKeyEnvName")));

        LucidlyMorphoPriceAggregatorV3WrapperV1 wrapper = new LucidlyMorphoPriceAggregatorV3WrapperV1(
            json.readAddress(".sourceOracle"),
            uint8(json.readUint(".sourceDecimals")),
            uint8(json.readUint(".outputDecimals")),
            json.readString(".name")
        );

        console.log("Deployed:", json.readString(".deploymentName"), address(wrapper));

        vm.stopBroadcast();
    }
}