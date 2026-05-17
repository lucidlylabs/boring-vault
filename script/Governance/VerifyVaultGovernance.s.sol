// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

interface IOwned {
    function owner() external view returns (address);
}

// Read-only check that a vault's governance migration landed correctly.
//
// source .env && forge script script/Governance/VerifyVaultGovernance.s.sol:VerifyVaultGovernance --sig "run(string)" syUSDT.json

contract VerifyVaultGovernance is Script {
    using stdJson for string;

    uint8 internal constant PAUSER_ROLE = 5;
    uint8 internal constant OWNER_ROLE = 8;
    uint8 internal constant MULTISIG_ROLE = 9;
    uint8 internal constant GENERIC_PAUSER_ROLE = 14;
    uint8 internal constant PAUSE_ALL_ROLE = 16;
    uint8 internal constant UNPAUSE_ALL_ROLE = 17;

    uint256 internal failures;

    function _check(bool ok, string memory label) internal {
        if (ok) {
            console.log("  PASS ", label);
        } else {
            console.log("  FAIL ", label);
            failures++;
        }
    }

    function run(string memory configFileName) external {
        string memory json =
            vm.readFile(string.concat(vm.projectRoot(), "/deployments/governance/", configFileName));

        vm.createSelectFork(json.readString(".chainName"));

        address multisig = json.readAddress(".multisig");
        address guardian = json.readAddress(".guardian");
        TimelockController timelock = TimelockController(payable(json.readAddress(".timelock")));
        RolesAuthority rolesAuthority = RolesAuthority(json.readAddress(".contracts.RolesAuthority"));
        address pauser = json.readAddress(".contracts.Pauser");
        address operationalOwner = json.readAddress(".currentOwners.operationalOwner");
        address rolesAuthorityOwner = json.readAddress(".currentOwners.rolesAuthorityOwner");
        uint256 minDelay = json.readUint(".minDelaySeconds");

        address[7] memory contracts = [
            json.readAddress(".contracts.BoringVault"),
            json.readAddress(".contracts.ManagerWithMerkleVerification"),
            json.readAddress(".contracts.AccountantWithRateProviders"),
            json.readAddress(".contracts.Teller"),
            json.readAddress(".contracts.BoringOnChainQueue"),
            json.readAddress(".contracts.QueueSolver"),
            pauser
        ];

        console.log("Verifying governance for vault:", json.readString(".vaultName"));

        // owner() of every contract (incl. RolesAuthority) is the timelock.
        for (uint256 i; i < contracts.length; ++i) {
            _check(IOwned(contracts[i]).owner() == address(timelock), "contract owner() == timelock");
        }
        _check(IOwned(address(rolesAuthority)).owner() == address(timelock), "RolesAuthority owner() == timelock");

        // Role grants in place.
        _check(rolesAuthority.doesUserHaveRole(address(timelock), OWNER_ROLE), "timelock has OWNER_ROLE");
        _check(rolesAuthority.doesUserHaveRole(multisig, MULTISIG_ROLE), "multisig has MULTISIG_ROLE");
        _check(rolesAuthority.doesUserHaveRole(multisig, PAUSE_ALL_ROLE), "multisig has PAUSE_ALL_ROLE");
        _check(rolesAuthority.doesUserHaveRole(multisig, UNPAUSE_ALL_ROLE), "multisig has UNPAUSE_ALL_ROLE");
        _check(rolesAuthority.doesUserHaveRole(guardian, GENERIC_PAUSER_ROLE), "guardian has GENERIC_PAUSER_ROLE");
        _check(rolesAuthority.doesUserHaveRole(pauser, PAUSER_ROLE), "pauser has PAUSER_ROLE");

        // Timelock wiring.
        _check(timelock.hasRole(timelock.PROPOSER_ROLE(), multisig), "multisig is timelock proposer");
        _check(timelock.hasRole(timelock.EXECUTOR_ROLE(), multisig), "multisig is timelock executor");
        _check(timelock.getMinDelay() == minDelay, "timelock minDelay matches config");

        // Negative checks: old EOAs must retain nothing.
        _check(!rolesAuthority.doesUserHaveRole(operationalOwner, OWNER_ROLE), "old operational EOA has no OWNER_ROLE");
        _check(
            !rolesAuthority.doesUserHaveRole(rolesAuthorityOwner, OWNER_ROLE),
            "old RolesAuthority EOA has no OWNER_ROLE"
        );

        if (failures == 0) {
            console.log("ALL CHECKS PASSED");
        } else {
            console.log("CHECKS FAILED:", failures);
            revert("governance verification failed");
        }
    }
}
