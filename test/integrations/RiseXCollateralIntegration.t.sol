// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseTestIntegration} from "test/integrations/BaseTestIntegration.t.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {RiseXFullDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/RiseXFullDecoderAndSanitizer.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {Test, console} from "@forge-std/Test.sol";

interface IRiseXCollateralManager {
    function getTokenBalance(address account, address token) external view returns (int256);
}

interface IRiseXAccountRegistry {
    function getUserId(address account) external view returns (uint32);
    function getOrRegister(address account) external returns (uint32);
}

interface IRiseXAuthorization {
    function getSessionKeyStatus(address account, address signer) external view returns (uint8);
    function hasPermission(address account, address signer, uint8 permission) external view returns (bool);
}

/**
 * @notice Real-fork integration test for the RiseX collateral integration. Forks RISE Chain
 *         (chainId 4153) via RISE_RPC_URL and drives the full Manager -> merkle -> decoder ->
 *         live `CollateralManager` path. Deposit is asserted end-to-end against the real contract
 *         (`getTokenBalance`). Order placement and signer registration are off-chain (EIP-712 / API)
 *         and out of scope.
 *
 *         Run: RISE_RPC_URL=https://rpc.risechain.com forge test --match-contract RiseXCollateralIntegration
 */
contract RiseXCollateralIntegration is BaseTestIntegration {
    address internal collateralManager;
    address internal accountRegistry;
    ERC20 internal usdc;

    function _setUpRiseX() internal {
        super.setUp();
        _setupChain("rise", 14150000);

        usdc = getERC20(sourceChain, "USDC");
        collateralManager = getAddress(sourceChain, "riseXCollateralManager");
        accountRegistry = getAddress(sourceChain, "riseXAccountRegistry");

        address decoder = address(new RiseXFullDecoderAndSanitizer());
        _overrideDecoder(decoder);

        // PRODUCTION PREREQUISITE: a deposit reverts `AccountNotRegistered` until the vault's RiseX
        // account exists, and the vault CANNOT register itself (getOrRegister is role-gated to RiseX
        // operator contracts — verified on-chain via AccessManager.canCall). Onboarding is therefore
        // an off-chain/operator step, not a vault on-chain action and not a merkle leaf. We simulate
        // it here by registering through an authorized caller (the live CollateralManager).
        vm.prank(collateralManager);
        IRiseXAccountRegistry(accountRegistry).getOrRegister(address(boringVault));
    }

    /// @notice Approve + deposit through the merkle-gated manager into the LIVE CollateralManager,
    ///         for a vault already onboarded to RiseX (see _setUpRiseX).
    function testRiseXDepositLive() external {
        _setUpRiseX();

        assertGt(IRiseXAccountRegistry(accountRegistry).getUserId(address(boringVault)), 0, "vault onboarded on RiseX");

        uint256 amount = 1_000e6; // 1k USDC.e (6 decimals)
        deal(address(usdc), address(boringVault), amount);

        ManageLeaf[] memory leafs = new ManageLeaf[](8);
        _addRiseXCollateralLeafs(leafs, address(usdc));
        // leafs: [0]=approve [1]=deposit [2]=withdraw [3]=releasePendingWithdrawal

        bytes32[][] memory tree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), tree[tree.length - 1][0]);

        Tx memory t = _getTxArrays(2);
        t.manageLeafs[0] = leafs[0]; // approve
        t.manageLeafs[1] = leafs[1]; // deposit
        bytes32[][] memory proofs = _getProofsUsingTree(t.manageLeafs, tree);

        t.targets[0] = address(usdc);
        t.targetData[0] = abi.encodeWithSignature("approve(address,uint256)", collateralManager, amount);
        t.targets[1] = collateralManager;
        t.targetData[1] =
            abi.encodeWithSignature("deposit(address,address,uint256)", address(boringVault), address(usdc), amount);
        t.decodersAndSanitizers[0] = rawDataDecoderAndSanitizer;
        t.decodersAndSanitizers[1] = rawDataDecoderAndSanitizer;

        int256 balanceBefore =
            IRiseXCollateralManager(collateralManager).getTokenBalance(address(boringVault), address(usdc));

        _submitManagerCall(proofs, t);

        assertEq(usdc.balanceOf(address(boringVault)), 0, "vault USDC.e moved into RiseX");
        int256 balanceAfter =
            IRiseXCollateralManager(collateralManager).getTokenBalance(address(boringVault), address(usdc));
        // CollateralManager normalizes balances to 18 decimals, so 1000 USDC.e (6 dp) -> 1000e18.
        uint256 scale = 10 ** (18 - usdc.decimals());
        assertEq(balanceAfter - balanceBefore, int256(amount * scale), "collateral credited to vault on RiseX");
    }

    /// @notice The vault authorizes its strategist API signer on the LIVE RISExAuthorization via
    ///         registerSenderSigner — no off-chain signature (msg.sender is the account). This is the
    ///         on-chain step that enables off-chain trading. Account must be onboarded first.
    function testRiseXRegisterSignerLive() external {
        _setUpRiseX();

        address authorization = getAddress(sourceChain, "riseXAuthorization");
        address signer = address(0x5160E1); // strategist API signer key

        assertEq(
            IRiseXAuthorization(authorization).getSessionKeyStatus(address(boringVault), signer),
            0,
            "signer not yet authorized"
        );

        ManageLeaf[] memory leafs = new ManageLeaf[](8);
        _addRiseXCollateralLeafs(leafs, address(usdc)); // 0..3
        _addRiseXRegisterSignerLeaf(leafs, signer); // 4

        bytes32[][] memory tree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), tree[tree.length - 1][0]);

        Tx memory t = _getTxArrays(1);
        t.manageLeafs[0] = leafs[4];
        bytes32[][] memory proofs = _getProofsUsingTree(t.manageLeafs, tree);
        t.targets[0] = authorization;
        t.targetData[0] = abi.encodeWithSignature(
            "registerSenderSigner(address,uint48,uint8,uint32)",
            signer,
            uint48(0),
            uint8(0),
            uint32(block.timestamp + 7 days)
        );
        t.decodersAndSanitizers[0] = rawDataDecoderAndSanitizer;

        _submitManagerCall(proofs, t);

        assertEq(
            IRiseXAuthorization(authorization).getSessionKeyStatus(address(boringVault), signer),
            1,
            "signer authorized (active session key)"
        );
        assertTrue(
            IRiseXAuthorization(authorization).hasPermission(address(boringVault), signer, 0),
            "signer has Permission.All"
        );
    }

    /// @notice Pointing the deposit `account` at an attacker (instead of the vault) must fail merkle
    ///         verification: the decoder returns the tampered account, which no longer matches the
    ///         leaf's pinned vault address.
    function testRiseXTamperedAccountReverts() external {
        _setUpRiseX();

        uint256 amount = 1_000e6;
        deal(address(usdc), address(boringVault), amount);

        ManageLeaf[] memory leafs = new ManageLeaf[](8);
        _addRiseXCollateralLeafs(leafs, address(usdc));

        bytes32[][] memory tree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), tree[tree.length - 1][0]);

        address attacker = address(0xBAD);

        Tx memory t = _getTxArrays(1);
        t.manageLeafs[0] = leafs[1]; // deposit leaf (account pinned to vault)
        bytes32[][] memory proofs = _getProofsUsingTree(t.manageLeafs, tree);
        t.targets[0] = collateralManager;
        t.targetData[0] = abi.encodeWithSignature("deposit(address,address,uint256)", attacker, address(usdc), amount);
        t.decodersAndSanitizers[0] = rawDataDecoderAndSanitizer;

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    ManagerWithMerkleVerification.ManagerWithMerkleVerification__FailedToVerifyManageProof.selector,
                    t.targets[0],
                    t.targetData[0],
                    0
                )
            )
        );
        manager.manageVaultWithMerkleVerification(proofs, t.decodersAndSanitizers, t.targets, t.targetData, t.values);
    }
}
