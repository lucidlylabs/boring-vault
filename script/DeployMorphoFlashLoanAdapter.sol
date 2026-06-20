// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.21;

import {Deployer} from "src/helper/Deployer.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {MorphoFlashLoanAdapter} from "src/base/Roles/MorphoFlashLoan/MorphoFlashLoanAdapter.sol";

import "@forge-std/Script.sol";

contract DeployMorphoFlashLoanAdapter is Script, MerkleTreeHelper {
    Deployer public deployer = Deployer(0x771263e3Bc6aCDa5aE388A3F8A0c2dd7A17275FC);

    function setUp() external {}

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;

        vm.createSelectFork("base");
        setSourceChainName("base");

        vm.startBroadcast(vm.envUint("DEPLOYER"));

        creationCode = type(MorphoFlashLoanAdapter).creationCode;
        constructorArgs = abi.encode(
            getAddress(sourceChain, "morphoBlue"),
            0xbEA97618434D925B0F9EdAB63aDF4Ce46F373b51,
            0xCED7B28a74A40D300f54f3e01DF0385238672451
        );
        deployer.deployContract("MorphoFlashLoanAdapter_HedgedBtcMmStrategyBaseV1", creationCode, constructorArgs, 0);

        vm.stopBroadcast();
    }
}
