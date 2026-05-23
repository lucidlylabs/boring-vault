// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test, stdJson, console} from "forge-std/Test.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

interface IOwned {
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

interface IManager {
    function setManageRoot(address strategist, bytes32 root) external;
    function manageRoot(address strategist) external view returns (bytes32);
    function isPaused() external view returns (bool);
}

interface IPausableView {
    function isPaused() external view returns (bool);
}

interface IPauser {
    function pauseAll() external;
}

// End-to-end exercise of the timelock + multisig governance flow on a mainnet
// fork: migrate a live vault off its EOAs, then drive a real config change
// through the timelock and confirm the emergency pause path bypasses it.
contract VaultGovernanceE2E is Test {
    using stdJson for string;

    uint8 internal constant PAUSER_ROLE = 5;
    uint8 internal constant OWNER_ROLE = 8;
    uint8 internal constant MULTISIG_ROLE = 9;
    uint8 internal constant GENERIC_PAUSER_ROLE = 14;
    uint8 internal constant PAUSE_ALL_ROLE = 16;
    uint8 internal constant UNPAUSE_ALL_ROLE = 17;

    // Stand-ins for the off-chain Safe and its guardian bot. The Safe collects
    // signatures off-chain; on-chain it is just the calling address, so a plain
    // address faithfully models the multisig for this test.
    address internal multisig = makeAddr("multisig");
    address internal guardian = makeAddr("guardian");
    address internal strategist = makeAddr("strategist");

    TimelockController internal timelock;
    RolesAuthority internal rolesAuthority;

    address internal operationalOwner;
    address internal rolesAuthorityOwner;
    uint256 internal minDelay;

    address internal boringVault;
    address internal manager;
    address internal accountant;
    address internal teller;
    address internal queue;
    address internal queueSolver;
    address internal pauser;

    function setUp() external {
        string memory json = vm.readFile(
            string.concat(vm.projectRoot(), "/deployments/governance/syUSDT.json")
        );

        vm.createSelectFork(json.readString(".chainName"));

        operationalOwner = json.readAddress(".currentOwners.operationalOwner");
        rolesAuthorityOwner = json.readAddress(".currentOwners.rolesAuthorityOwner");
        minDelay = json.readUint(".minDelaySeconds");

        rolesAuthority = RolesAuthority(json.readAddress(".contracts.RolesAuthority"));
        boringVault = json.readAddress(".contracts.BoringVault");
        manager = json.readAddress(".contracts.ManagerWithMerkleVerification");
        accountant = json.readAddress(".contracts.AccountantWithRateProviders");
        teller = json.readAddress(".contracts.Teller");
        queue = json.readAddress(".contracts.BoringOnChainQueue");
        queueSolver = json.readAddress(".contracts.QueueSolver");
        pauser = json.readAddress(".contracts.Pauser");

        // The multisig is the sole proposer / executor / admin of the timelock.
        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        address[] memory executors = new address[](1);
        executors[0] = multisig;
        timelock = new TimelockController(minDelay, proposers, executors, multisig);

        _migrate();
    }

    // Reproduces MigrateVaultGovernance's three phases by impersonating the
    // current owner EOAs.
    function _migrate() internal {
        // Phase 1 - grant roles (RolesAuthority owner).
        vm.startPrank(rolesAuthorityOwner);
        rolesAuthority.setUserRole(address(timelock), OWNER_ROLE, true);
        rolesAuthority.setUserRole(multisig, MULTISIG_ROLE, true);
        rolesAuthority.setUserRole(multisig, PAUSE_ALL_ROLE, true);
        rolesAuthority.setUserRole(multisig, UNPAUSE_ALL_ROLE, true);
        rolesAuthority.setUserRole(guardian, GENERIC_PAUSER_ROLE, true);
        rolesAuthority.setUserRole(pauser, PAUSER_ROLE, true);
        vm.stopPrank();

        // Phase 2 - transfer the 7 operational contracts (operational owner).
        vm.startPrank(operationalOwner);
        IOwned(boringVault).transferOwnership(address(timelock));
        IOwned(manager).transferOwnership(address(timelock));
        IOwned(accountant).transferOwnership(address(timelock));
        IOwned(teller).transferOwnership(address(timelock));
        IOwned(queue).transferOwnership(address(timelock));
        IOwned(queueSolver).transferOwnership(address(timelock));
        IOwned(pauser).transferOwnership(address(timelock));
        vm.stopPrank();

        // Phase 3 - transfer RolesAuthority last (RolesAuthority owner).
        vm.prank(rolesAuthorityOwner);
        IOwned(address(rolesAuthority)).transferOwnership(address(timelock));
    }

    function test_migration_movesAllOwnershipToTimelock() external view {
        assertEq(IOwned(boringVault).owner(), address(timelock), "vault");
        assertEq(IOwned(manager).owner(), address(timelock), "manager");
        assertEq(IOwned(accountant).owner(), address(timelock), "accountant");
        assertEq(IOwned(teller).owner(), address(timelock), "teller");
        assertEq(IOwned(queue).owner(), address(timelock), "queue");
        assertEq(IOwned(queueSolver).owner(), address(timelock), "solver");
        assertEq(IOwned(pauser).owner(), address(timelock), "pauser");
        assertEq(IOwned(address(rolesAuthority)).owner(), address(timelock), "rolesAuthority");
    }

    function test_oldEoaCanNoLongerChangeConfig() external {
        vm.prank(operationalOwner);
        vm.expectRevert();
        IManager(manager).setManageRoot(strategist, bytes32(uint256(1)));
    }

    // The "create the draft locally" flow: build the schedule payload locally,
    // the multisig schedules it, wait the delay, the multisig executes it.
    function test_configChangeFlowsThroughTimelock() external {
        bytes32 newRoot = keccak256("e2e-root");

        // Draft built locally - this calldata is what a Safe tx would carry.
        bytes memory payload = abi.encodeWithSelector(IManager.setManageRoot.selector, strategist, newRoot);
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("e2e-salt");

        // Multisig schedules it on the timelock.
        vm.prank(multisig);
        timelock.schedule(manager, 0, payload, predecessor, salt, minDelay);

        // Cannot execute before the delay elapses.
        vm.prank(multisig);
        vm.expectRevert();
        timelock.execute(manager, 0, payload, predecessor, salt);

        // After the delay, the multisig executes and the change lands.
        vm.warp(block.timestamp + minDelay);
        vm.prank(multisig);
        timelock.execute(manager, 0, payload, predecessor, salt);

        assertEq(IManager(manager).manageRoot(strategist), newRoot, "manage root updated via timelock");
    }

    function test_scheduledOperationCanBeCancelledDuringDelay() external {
        bytes memory payload =
            abi.encodeWithSelector(IManager.setManageRoot.selector, strategist, keccak256("cancel-me"));
        bytes32 salt = keccak256("cancel-salt");

        vm.prank(multisig);
        timelock.schedule(manager, 0, payload, bytes32(0), salt, minDelay);

        bytes32 id = timelock.hashOperation(manager, 0, payload, bytes32(0), salt);
        assertTrue(timelock.isOperationPending(id), "pending after schedule");

        vm.prank(multisig);
        timelock.cancel(id);
        assertFalse(timelock.isOperation(id), "cleared after cancel");
    }

    // Emergency pause must NOT route through the 12h timelock.
    function test_pauseBypassesTimelock() external {
        assertFalse(IManager(manager).isPaused(), "manager starts unpaused");

        vm.prank(multisig);
        IPauser(pauser).pauseAll();

        assertTrue(IManager(manager).isPaused(), "manager paused instantly");
        assertTrue(IPausableView(teller).isPaused(), "teller paused instantly");
    }

    function test_guardianCanReachThePauser() external {
        // Guardian holds GENERIC_PAUSER_ROLE; it is wired into RolesAuthority
        // independently of the timelock owner path.
        assertTrue(rolesAuthority.doesUserHaveRole(guardian, GENERIC_PAUSER_ROLE), "guardian role");
    }
}
