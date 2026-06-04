// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Deployer} from "src/helper/Deployer.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ContractNames} from "resources/ContractNames.sol";
import {console, Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

contract DeployRolesAuthority is Script {
    uint256 public privateKey;

    Deployer public deployer;
    uint8 public deployerRole = 1;
    address public admin = 0x90760A784953829095969204f87d6DFEc29a6ca9;

    function setUp() external {
        privateKey = vm.envUint("DEPLOYER");
    }

    function run() external {
        vm.startBroadcast(privateKey);

        new RolesAuthority(admin, Authority(address(0)));

        vm.stopBroadcast();
    }
}
