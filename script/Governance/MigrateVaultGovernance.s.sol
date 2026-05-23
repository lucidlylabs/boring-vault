// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

interface IAuth {
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

// Migrates a live vault from EOA control to timelock control. Run in three
// phases, each broadcast with the indicated key:
//
// 1) grantRoles            -- ROLES_AUTHORITY_OWNER_PK
// 2) transferContracts     -- OPERATIONAL_OWNER_PK
// 3) transferRolesAuthority-- ROLES_AUTHORITY_OWNER_PK   (must be last)
//
// source .env && forge script script/Governance/MigrateVaultGovernance.s.sol:MigrateVaultGovernance --sig "grantRoles(string)" syUSDT.json --broadcast

contract MigrateVaultGovernance is Script {
    using stdJson for string;

    uint8 internal constant PAUSER_ROLE = 5;
    uint8 internal constant OWNER_ROLE = 8;
    uint8 internal constant MULTISIG_ROLE = 9;
    uint8 internal constant GENERIC_PAUSER_ROLE = 14;
    uint8 internal constant PAUSE_ALL_ROLE = 16;
    uint8 internal constant UNPAUSE_ALL_ROLE = 17;

    struct Cfg {
        string chainName;
        address multisig;
        address guardian;
        address timelock;
        RolesAuthority rolesAuthority;
        address pauser;
        address boringVault;
        address manager;
        address accountant;
        address teller;
        address queue;
        address queueSolver;
    }

    function _load(string memory configFileName) internal returns (string memory json, Cfg memory c) {
        string memory path =
            string.concat(vm.projectRoot(), "/deployments/governance/", configFileName);
        json = vm.readFile(path);

        c.chainName = json.readString(".chainName");
        c.multisig = json.readAddress(".multisig");
        c.guardian = json.readAddress(".guardian");
        c.timelock = json.readAddress(".timelock");
        c.rolesAuthority = RolesAuthority(json.readAddress(".contracts.RolesAuthority"));
        c.pauser = json.readAddress(".contracts.Pauser");
        c.boringVault = json.readAddress(".contracts.BoringVault");
        c.manager = json.readAddress(".contracts.ManagerWithMerkleVerification");
        c.accountant = json.readAddress(".contracts.AccountantWithRateProviders");
        c.teller = json.readAddress(".contracts.Teller");
        c.queue = json.readAddress(".contracts.BoringOnChainQueue");
        c.queueSolver = json.readAddress(".contracts.QueueSolver");

        require(c.multisig != address(0), "multisig not set in config");
        require(c.guardian != address(0), "guardian not set in config");
        require(c.timelock != address(0), "timelock not set in config (deploy it first)");

        vm.createSelectFork(c.chainName);
    }

    // Phase 1: grant the new governance roles. Signed by the RolesAuthority owner.
    function grantRoles(string memory configFileName) external {
        (string memory json, Cfg memory c) = _load(configFileName);
        uint256 key = vm.envUint(json.readString(".migration.rolesAuthorityOwnerKeyEnvName"));

        vm.startBroadcast(key);
        c.rolesAuthority.setUserRole(c.timelock, OWNER_ROLE, true);
        c.rolesAuthority.setUserRole(c.multisig, MULTISIG_ROLE, true);
        c.rolesAuthority.setUserRole(c.multisig, PAUSE_ALL_ROLE, true);
        c.rolesAuthority.setUserRole(c.multisig, UNPAUSE_ALL_ROLE, true);
        c.rolesAuthority.setUserRole(c.guardian, GENERIC_PAUSER_ROLE, true);
        c.rolesAuthority.setUserRole(c.pauser, PAUSER_ROLE, true);
        vm.stopBroadcast();

        console.log("Phase 1 done: roles granted (timelock=OWNER, multisig=MULTISIG/PAUSE, guardian=PAUSER).");
    }

    // Phase 2: hand ownership of the 7 operational contracts to the timelock.
    // Signed by the operational owner. RolesAuthority is intentionally excluded.
    function transferContracts(string memory configFileName) external {
        (string memory json, Cfg memory c) = _load(configFileName);
        uint256 key = vm.envUint(json.readString(".migration.operationalOwnerKeyEnvName"));

        vm.startBroadcast(key);
        IAuth(c.boringVault).transferOwnership(c.timelock);
        IAuth(c.manager).transferOwnership(c.timelock);
        IAuth(c.accountant).transferOwnership(c.timelock);
        IAuth(c.teller).transferOwnership(c.timelock);
        IAuth(c.queue).transferOwnership(c.timelock);
        IAuth(c.queueSolver).transferOwnership(c.timelock);
        IAuth(c.pauser).transferOwnership(c.timelock);
        vm.stopBroadcast();

        console.log("Phase 2 done: vault/manager/accountant/teller/queue/solver/pauser owned by timelock.");
    }

    // Phase 3: hand ownership of RolesAuthority to the timelock. Must run last,
    // after all role grants -- once this lands, further grants need the timelock.
    function transferRolesAuthority(string memory configFileName) external {
        (string memory json, Cfg memory c) = _load(configFileName);
        uint256 key = vm.envUint(json.readString(".migration.rolesAuthorityOwnerKeyEnvName"));

        vm.startBroadcast(key);
        IAuth(address(c.rolesAuthority)).transferOwnership(c.timelock);
        vm.stopBroadcast();

        console.log("Phase 3 done: RolesAuthority owned by timelock. EOA migration complete.");
    }
}
