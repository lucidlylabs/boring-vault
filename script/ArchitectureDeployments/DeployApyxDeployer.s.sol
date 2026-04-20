// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Deployer} from "src/helper/Deployer.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {Script, console2} from "@forge-std/Script.sol";

contract DeployApyxDeployerScript is Script {
    uint8 public constant DEPLOYER_ROLE = 1;
    string public constant CONFIG_PATH = "deployments/configurations/Mainnet/ApyxUSD.json";

    function run() external {
        uint256 privateKey = vm.envUint("BORING_DEVELOPER");
        address owner = vm.addr(privateKey);

        vm.startBroadcast(privateKey);

        RolesAuthority rolesAuthority = new RolesAuthority(owner, Authority(address(0)));
        Deployer deployer = new Deployer(owner, rolesAuthority);

        rolesAuthority.setRoleCapability(DEPLOYER_ROLE, address(deployer), Deployer.deployContract.selector, true);
        rolesAuthority.setRoleCapability(DEPLOYER_ROLE, address(deployer), Deployer.bundleTxs.selector, true);
        rolesAuthority.setUserRole(owner, DEPLOYER_ROLE, true);
        
        rolesAuthority.setUserRole(address(deployer), DEPLOYER_ROLE, true);

        vm.stopBroadcast();

        console2.log("Deployer:      ", address(deployer));
        console2.log("RolesAuthority:", address(rolesAuthority));
        console2.log("Owner:         ", owner);

        _patchConfig(address(deployer));
    }

    function _patchConfig(address deployerAddress) internal {
        
        string memory jsonDeployer = string.concat('"', vm.toString(deployerAddress), '"');
        vm.writeJson(jsonDeployer, CONFIG_PATH, ".deploymentParameters.txBundlerAddressOrName.address");
        vm.writeJson(jsonDeployer, CONFIG_PATH, ".deploymentParameters.deployerContractAddressOrName.address");
        vm.writeJson(jsonDeployer, CONFIG_PATH, ".deploymentParameters.deploymentOwnerAddressOrName.address");
        console2.log("Patched", CONFIG_PATH);
    }
}
