// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {
    DnEnaPtHedgeHyperEvmDecoderAndSanitizer
} from "src/base/DecodersAndSanitizers/DnEnaPtHedgeHyperEvmDecoderAndSanitizer.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract DeployDnEnaPtHedgeHyperEvmDecoderAndSanitizerScript is Script {
    function run() external returns (address decoder) {
        uint256 privateKey = vm.envUint("DEPLOYER01");

        vm.startBroadcast(privateKey);
        decoder = address(new DnEnaPtHedgeHyperEvmDecoderAndSanitizer());
        vm.stopBroadcast();

        console.log("DnEnaPtHedgeHyperEvmDecoderAndSanitizer deployed at:");
        console.logAddress(decoder);
    }
}
