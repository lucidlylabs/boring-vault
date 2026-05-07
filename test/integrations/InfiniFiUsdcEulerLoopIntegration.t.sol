// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BoringVault} from "src/base/BoringVault.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {MorphoFlashLoanAdapter} from "src/base/Roles/MorphoFlashLoan/MorphoFlashLoanAdapter.sol";
import {InfiniFiUsdcEulerLoopDecoderAndSanitizer} from
    "src/base/DecodersAndSanitizers/InfiniFiUsdcEulerLoopDecoderAndSanitizer.sol";

import {Test, console} from "@forge-std/Test.sol";

/// @dev MAINNET_RPC_URL=$MAINNET_RPC_URL forge test --mp test/integrations/InfiniFiUsdcEulerLoopIntegration.t.sol -vvv
contract InfiniFiUsdcEulerLoopIntegrationTest is Test, MerkleTreeHelper {
    using SafeTransferLib for ERC20;

    ManagerWithMerkleVerification public manager;
    BoringVault public boringVault;
    address public rawDataDecoderAndSanitizer;
    RolesAuthority public rolesAuthority;
    MorphoFlashLoanAdapter public flashLoanAdapter;

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 2;
    uint8 public constant MANGER_INTERNAL_ROLE = 3;
    uint8 public constant ADMIN_ROLE = 4;
    uint8 public constant BORING_VAULT_ROLE = 5;
    uint8 public constant BALANCER_VAULT_ROLE = 6;

    function setUp() external {
        setSourceChainName("mainnet");
        _startFork("MAINNET_RPC_URL", 0);

        boringVault = new BoringVault(address(this), "Boring Vault", "BV", 18);
        manager =
            new ManagerWithMerkleVerification(address(this), address(boringVault), getAddress(sourceChain, "vault"));
        rawDataDecoderAndSanitizer = address(new InfiniFiUsdcEulerLoopDecoderAndSanitizer());

        setAddress(false, sourceChain, "boringVault", address(boringVault));
        setAddress(false, sourceChain, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizer);
        setAddress(false, sourceChain, "manager", address(manager));
        setAddress(false, sourceChain, "managerAddress", address(manager));
        setAddress(false, sourceChain, "accountantAddress", address(1));

        flashLoanAdapter = new MorphoFlashLoanAdapter(
            getAddress(sourceChain, "morphoBlue"), address(boringVault), address(manager)
        );
        setAddress(true, sourceChain, "morphoBlueFlashLoanAdapterAddress", address(flashLoanAdapter));

        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        boringVault.setAuthority(rolesAuthority);
        manager.setAuthority(rolesAuthority);

        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(boringVault),
            bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)"))),
            true
        );
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(boringVault),
            bytes4(keccak256(abi.encodePacked("manage(address[],bytes[],uint256[])"))),
            true
        );
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(manager),
            ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
            true
        );
        rolesAuthority.setRoleCapability(
            MANGER_INTERNAL_ROLE,
            address(manager),
            ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
            true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(manager), ManagerWithMerkleVerification.setManageRoot.selector, true
        );

        rolesAuthority.setUserRole(address(this), STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(address(manager), MANGER_INTERNAL_ROLE, true);
        rolesAuthority.setUserRole(address(this), ADMIN_ROLE, true);
        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(address(boringVault), BORING_VAULT_ROLE, true);
        rolesAuthority.setUserRole(address(flashLoanAdapter), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(address(flashLoanAdapter), STRATEGIST_ROLE, true);
    }

    /// @dev Open the leveraged loop in a single flashloan tx.
    function test__InfiniFiUsdcEulerLoop__OpenLoop() external {
        uint256 seedUsdc = 1_000e6;
        uint256 totalUsdc = 3_000e6; // 3x leverage
        uint256 flashloanUsdc = totalUsdc - seedUsdc;

        deal(getAddress(sourceChain, "USDC"), address(boringVault), seedUsdc);

        ManageLeaf[] memory leafs = new ManageLeaf[](64);
        _addInfiniFiUsdcEulerLoopLeafs(leafs);
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);
        manager.setManageRoot(address(flashLoanAdapter), manageTree[manageTree.length - 1][0]);

        bytes memory userData = _buildInnerPayload(leafs, manageTree, totalUsdc, flashloanUsdc);
        _executeOuterFlashloan(leafs, manageTree, flashloanUsdc, userData);

        uint256 colShares = ERC4626(getAddress(sourceChain, "euler_liUSD_13w_collateral")).balanceOf(address(boringVault));
        assertGt(colShares, 0, "vault should hold Euler liUSD collateral shares");
        console.log("euler collateral shares:", colShares);
        console.log(
            "vault USDC after open:", ERC20(getAddress(sourceChain, "USDC")).balanceOf(address(boringVault))
        );
    }

    // ========================================= helpers =========================================

    function _buildInnerPayload(
        ManageLeaf[] memory leafs,
        bytes32[][] memory manageTree,
        uint256 totalUsdc,
        uint256 flashloanUsdc
    ) internal view returns (bytes memory) {
        ManageLeaf[] memory innerManage = new ManageLeaf[](7);
        innerManage[0] = _findByDesc(leafs, "approve InfiniGateway to spend USDC");
        innerManage[1] = _findByDesc(leafs, "mint liUSD-13w with USDC via InfiniGateway");
        innerManage[2] = _findApproveLeaf(leafs, getAddress(sourceChain, "liUSD_13w"), getAddress(sourceChain, "euler_liUSD_13w_collateral"));
        innerManage[3] = _findDepositLeaf(leafs, getAddress(sourceChain, "euler_liUSD_13w_collateral"));
        innerManage[4] = _findEvcLeaf(leafs, "enableCollateral(address,address)", address(boringVault), getAddress(sourceChain, "euler_liUSD_13w_collateral"));
        innerManage[5] = _findEvcLeaf(leafs, "enableController(address,address)", address(boringVault), getAddress(sourceChain, "euler_USDC_120_borrow"));
        innerManage[6] = _findBorrowLeaf(leafs, getAddress(sourceChain, "euler_USDC_120_borrow"));

        bytes32[][] memory innerProofs = _getProofsUsingTree(innerManage, manageTree);

        return abi.encode(
            getAddress(sourceChain, "USDC"),
            innerProofs,
            _decoderArr(7),
            _innerTargets(),
            _innerData(totalUsdc, flashloanUsdc),
            new uint256[](7)
        );
    }

    function _innerTargets() internal view returns (address[] memory t) {
        t = new address[](7);
        t[0] = getAddress(sourceChain, "USDC");
        t[1] = getAddress(sourceChain, "InfiniGatewayContract");
        t[2] = getAddress(sourceChain, "liUSD_13w");
        t[3] = getAddress(sourceChain, "euler_liUSD_13w_collateral");
        t[4] = getAddress(sourceChain, "ethereumVaultConnector");
        t[5] = getAddress(sourceChain, "ethereumVaultConnector");
        t[6] = getAddress(sourceChain, "euler_USDC_120_borrow");
    }

    function _innerData(uint256 totalUsdc, uint256 flashloanUsdc) internal view returns (bytes[] memory d) {
        address vaultAddr = address(boringVault);
        // Compute a safe lower bound on the minted liUSD-13w using Euler's oracle.
        // getQuote(amount, base, USD_PSEUDO) returns USD value, 18 decimals.
        // We want X liUSD such that quote(X, liUSD, USD) ~= totalUsdc * 1e12 (USDC scaled to 18d).
        // i.e. X = (totalUsdc * 1e12 * 1e18) / quote(1e18, liUSD, USD). Take 90% as safety.
        address oracle = getAddress(sourceChain, "euler_liUSD_oracle");
        address liUsd = getAddress(sourceChain, "liUSD_13w");
        address usdPseudo = address(uint160(0x348)); // ISO 4217 840 = USD
        (bool ok, bytes memory ret) = oracle.staticcall(
            abi.encodeWithSignature("getQuote(uint256,address,address)", uint256(1e18), liUsd, usdPseudo)
        );
        require(ok, "oracle.getQuote failed");
        uint256 pricePerShare18 = abi.decode(ret, (uint256));
        uint256 liUsdAmt = (totalUsdc * 1e12 * 1e18) / pricePerShare18; // raw shares for totalUsdc USD
        liUsdAmt = (liUsdAmt * 90) / 100; // 90% safety to absorb price drift / mint slippage
        d = new bytes[](7);
        d[0] = abi.encodeWithSignature(
            "approve(address,uint256)", getAddress(sourceChain, "InfiniGatewayContract"), type(uint256).max
        );
        d[1] = abi.encodeWithSignature(
            "mintAndLock(address,uint256,uint32)", vaultAddr, totalUsdc, uint32(13)
        );
        d[2] = abi.encodeWithSignature(
            "approve(address,uint256)", getAddress(sourceChain, "euler_liUSD_13w_collateral"), type(uint256).max
        );
        d[3] = abi.encodeWithSignature("deposit(uint256,address)", liUsdAmt, vaultAddr);
        d[4] = abi.encodeWithSignature(
            "enableCollateral(address,address)", vaultAddr, getAddress(sourceChain, "euler_liUSD_13w_collateral")
        );
        d[5] = abi.encodeWithSignature(
            "enableController(address,address)", vaultAddr, getAddress(sourceChain, "euler_USDC_120_borrow")
        );
        d[6] = abi.encodeWithSignature("borrow(uint256,address)", flashloanUsdc, vaultAddr);
    }

    function _executeOuterFlashloan(
        ManageLeaf[] memory leafs,
        bytes32[][] memory manageTree,
        uint256 flashloanUsdc,
        bytes memory userData
    ) internal {
        ManageLeaf[] memory outer = new ManageLeaf[](1);
        outer[0] = _findByDesc(leafs, "call MorphoFlashLoanAdapter to flash-borrow USDC");
        bytes32[][] memory outerProofs = _getProofsUsingTree(outer, manageTree);

        address[] memory targets = new address[](1);
        targets[0] = address(flashLoanAdapter);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature(
            "morphoFlashLoan(address,uint256,bytes)", getAddress(sourceChain, "USDC"), flashloanUsdc, userData
        );

        manager.manageVaultWithMerkleVerification(outerProofs, _decoderArr(1), targets, data, new uint256[](1));
    }

    function _decoderArr(uint256 n) internal view returns (address[] memory a) {
        a = new address[](n);
        for (uint256 i = 0; i < n; i++) a[i] = rawDataDecoderAndSanitizer;
    }

    function _findByDesc(ManageLeaf[] memory leafs, string memory desc) internal pure returns (ManageLeaf memory) {
        bytes32 h = keccak256(bytes(desc));
        for (uint256 i = 0; i < leafs.length; i++) {
            if (bytes(leafs[i].description).length == 0) continue;
            if (keccak256(bytes(leafs[i].description)) == h) return leafs[i];
        }
        revert("leaf not found");
    }

    function _findApproveLeaf(ManageLeaf[] memory leafs, address token, address spender)
        internal
        pure
        returns (ManageLeaf memory)
    {
        bytes32 sigH = keccak256("approve(address,uint256)");
        for (uint256 i = 0; i < leafs.length; i++) {
            if (bytes(leafs[i].signature).length == 0) continue;
            if (
                keccak256(bytes(leafs[i].signature)) == sigH && leafs[i].target == token
                    && leafs[i].argumentAddresses.length == 1 && leafs[i].argumentAddresses[0] == spender
            ) return leafs[i];
        }
        revert("approve leaf not found");
    }

    function _findDepositLeaf(ManageLeaf[] memory leafs, address vault4626)
        internal
        pure
        returns (ManageLeaf memory)
    {
        bytes32 sigH = keccak256("deposit(uint256,address)");
        for (uint256 i = 0; i < leafs.length; i++) {
            if (bytes(leafs[i].signature).length == 0) continue;
            if (keccak256(bytes(leafs[i].signature)) == sigH && leafs[i].target == vault4626) return leafs[i];
        }
        revert("deposit leaf not found");
    }

    function _findEvcLeaf(ManageLeaf[] memory leafs, string memory sig, address account, address vault_)
        internal
        pure
        returns (ManageLeaf memory)
    {
        bytes32 sigH = keccak256(bytes(sig));
        for (uint256 i = 0; i < leafs.length; i++) {
            if (bytes(leafs[i].signature).length == 0) continue;
            if (
                keccak256(bytes(leafs[i].signature)) == sigH && leafs[i].argumentAddresses.length == 2
                    && leafs[i].argumentAddresses[0] == account && leafs[i].argumentAddresses[1] == vault_
            ) return leafs[i];
        }
        revert("evc leaf not found");
    }

    function _findBorrowLeaf(ManageLeaf[] memory leafs, address borrowVault)
        internal
        pure
        returns (ManageLeaf memory)
    {
        bytes32 sigH = keccak256("borrow(uint256,address)");
        for (uint256 i = 0; i < leafs.length; i++) {
            if (bytes(leafs[i].signature).length == 0) continue;
            if (keccak256(bytes(leafs[i].signature)) == sigH && leafs[i].target == borrowVault) return leafs[i];
        }
        revert("borrow leaf not found");
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        if (blockNumber == 0) {
            forkId = vm.createFork(vm.envString(rpcKey));
        } else {
            forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        }
        vm.selectFork(forkId);
    }
}
