// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test} from "@forge-std/Test.sol";
import {DeployArcticArchitectureWithConfigScript} from
    "script/ArchitectureDeployments/DeployArcticArchitectureWithConfig.s.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {Auth} from "@solmate/auth/Auth.sol";

/// @dev Subclasses the deploy script to expose its `internal` planning functions and inject the
///      internal state they read. The script builds every action into `txs[]` and only broadcasts in
///      `_bundleTxs` (never called here), so we can assert on the queued plan (`getTxs()`) without
///      forking or broadcasting.
contract DeployArcticHarness is DeployArcticArchitectureWithConfigScript {
    function setRawJson(string memory j) external {
        rawJson = j;
    }

    function setLogLevel(uint256 l) external {
        logLevel = l;
    }

    function setSourceChain(string memory c) external {
        sourceChain = c;
    }

    function setDeployer(Deployer d) external {
        deployer = d;
    }

    function setRolesAuthority(RolesAuthority ra, bool exists) external {
        rolesAuthority = ra;
        rolesAuthorityExists = exists;
    }

    function setTellerDeploymentName(string memory n) external {
        tellerDeploymentName = n;
    }

    function exposed_finalOwner() external view returns (address) {
        return _finalOwner();
    }

    function exposed_finalizeAuthority() external {
        _finalizeAuthority();
    }

    function exposed_deployTeller() external {
        _deployTeller();
    }

    function exposed_finalizeOwnable(address target, bool exists, address owner_) external {
        _finalizeOwnable(target, exists, owner_);
    }
}

/// @notice Tier-1 unit tests for the config deploy script's owner/role handoff and validation guards.
///         These assert the *planned* txs and the fail-closed reverts; they do not fork or broadcast.
contract DeployArcticArchitectureWithConfigTest is Test {
    DeployArcticHarness internal h;

    address internal constant FINAL_OWNER = 0x1111111111111111111111111111111111111111;
    address internal constant ROLES_AUTHORITY = 0x2222222222222222222222222222222222222222;

    // {address, name} with an explicit final owner address (no ChainValues lookup needed).
    string internal constant CONFIG_WITH_FINAL_OWNER =
        '{"deploymentParameters":{"finalOwnerAddressOrName":{"address":"0x1111111111111111111111111111111111111111","name":""}}}';

    function setUp() external {
        h = new DeployArcticHarness();
        // A real Deployer so `_getAddressAndIfDeployed` can predict CREATE3 addresses. Nothing is actually
        // deployed, so every component reads as "not yet deployed" and gets queued rather than skipped.
        Deployer deployer = new Deployer(address(this), Authority(address(0)));
        h.setDeployer(deployer);
        h.setSourceChain("mainnet");
    }

    // -------------------------------------------------------------------------
    // _finalOwner: required key, resolved from config, never hardcoded
    // -------------------------------------------------------------------------

    function test_finalOwner_resolvesExplicitConfigAddress() external {
        h.setRawJson(CONFIG_WITH_FINAL_OWNER);
        assertEq(h.exposed_finalOwner(), FINAL_OWNER);
    }

    function test_finalOwner_revertsWhenKeyAbsent() external {
        // No hardcoded fallback owner -> a config without finalOwnerAddressOrName must fail closed.
        h.setRawJson('{"deploymentParameters":{}}');
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployArcticArchitectureWithConfigScript.KeyNotFound.selector,
                ".deploymentParameters.finalOwnerAddressOrName"
            )
        );
        h.exposed_finalOwner();
    }

    function test_finalOwner_revertsWhenResolvesToZero() external {
        // address_ == 0 forces a ChainValues name lookup; an unmapped name resolves to zero, which
        // ChainValues.getAddress rejects -> the stack can never hand off to address(0).
        h.setRawJson(
            '{"deploymentParameters":{"finalOwnerAddressOrName":{"address":"0x0000000000000000000000000000000000000000","name":"definitelyNotAChainValue"}}}'
        );
        vm.expectRevert();
        h.exposed_finalOwner();
    }

    // -------------------------------------------------------------------------
    // _finalizeAuthority: single rolesAuthority handoff to finalOwner, no dev-EOA grants
    // -------------------------------------------------------------------------

    function test_finalizeAuthority_queuesSingleHandoffToFinalOwner() external {
        h.setLogLevel(0); // silence _log
        h.setRolesAuthority(RolesAuthority(ROLES_AUTHORITY), false);
        h.setRawJson(CONFIG_WITH_FINAL_OWNER);

        h.exposed_finalizeAuthority();

        Deployer.Tx[] memory txs = h.getTxs();
        // Exactly one queued tx, and it is the rolesAuthority handoff to finalOwner -- no OWNER_ROLE /
        // STRATEGIST_ROLE grants to any dev EOA (the behaviour the removed `_setupTestUser` had).
        assertEq(txs.length, 1, "expected exactly one handoff tx");
        assertEq(txs[0].target, ROLES_AUTHORITY, "tx must target rolesAuthority");
        assertEq(txs[0].value, 0, "handoff carries no value");
        assertEq(
            txs[0].data,
            abi.encodeWithSelector(Auth.transferOwnership.selector, FINAL_OWNER),
            "tx must be transferOwnership(finalOwner)"
        );
    }

    // -------------------------------------------------------------------------
    // _finalizeOwnable: byte-identical authority/ownership handoff (R3 dedup guard)
    // -------------------------------------------------------------------------

    function test_finalizeOwnable_notDeployed_queuesAuthorityThenOwnership() external {
        h.setRolesAuthority(RolesAuthority(ROLES_AUTHORITY), false);
        address target = address(0xBEEF);

        h.exposed_finalizeOwnable(target, false, FINAL_OWNER);

        Deployer.Tx[] memory txs = h.getTxs();
        assertEq(txs.length, 2, "fresh contract queues both ops");
        assertEq(txs[0].target, target);
        assertEq(
            txs[0].data, abi.encodeWithSelector(Auth.setAuthority.selector, ROLES_AUTHORITY), "setAuthority first"
        );
        assertEq(txs[1].target, target);
        assertEq(
            txs[1].data,
            abi.encodeWithSelector(Auth.transferOwnership.selector, FINAL_OWNER),
            "transferOwnership second"
        );
    }

    function test_finalizeOwnable_deployed_skipsWhenAlreadyCorrect() external {
        h.setRolesAuthority(RolesAuthority(ROLES_AUTHORITY), false);
        // target already has authority == rolesAuthority and owner == finalOwner -> nothing to do.
        RolesAuthority target = new RolesAuthority(FINAL_OWNER, Authority(ROLES_AUTHORITY));

        h.exposed_finalizeOwnable(address(target), true, FINAL_OWNER);

        assertEq(h.getTxs().length, 0, "no txs when already correct");
    }

    function test_finalizeOwnable_deployed_queuesWhenWrong() external {
        h.setRolesAuthority(RolesAuthority(ROLES_AUTHORITY), false);
        // wrong owner + zero authority -> both ops queued.
        RolesAuthority target = new RolesAuthority(address(0xABCD), Authority(address(0)));

        h.exposed_finalizeOwnable(address(target), true, FINAL_OWNER);

        Deployer.Tx[] memory txs = h.getTxs();
        assertEq(txs.length, 2, "deployed-but-wrong queues both ops");
        assertEq(txs[0].data, abi.encodeWithSelector(Auth.setAuthority.selector, ROLES_AUTHORITY));
        assertEq(txs[1].data, abi.encodeWithSelector(Auth.transferOwnership.selector, FINAL_OWNER));
    }

    // -------------------------------------------------------------------------
    // _deployTeller: fail closed when no teller kind is selected
    // -------------------------------------------------------------------------

    function test_deployTeller_revertsWhenNoKind() external {
        h.setLogLevel(4); // _log(_, 1) only reverts when logLevel >= 1
        h.setTellerDeploymentName("test teller V0.0");
        h.setRawJson(
            '{"deploymentParameters":{"nativeWrapperAddressOrName":{"address":"0x4200000000000000000000000000000000000006","name":""}},"tellerConfiguration":{"tellerParameters":{"kind":{"teller":false,"tellerWithRemediation":false,"tellerWithCcip":false,"tellerWithLayerZero":false}}}}'
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployArcticArchitectureWithConfigScript.DeployError.selector, "Teller kind not set in configuration file"
            )
        );
        h.exposed_deployTeller();
    }
}
