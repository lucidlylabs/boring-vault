// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

import "forge-std/Script.sol";

// Run with the VAULT OWNER key (0x651D…): setManageRoot + setUserRole are owner-gated, so this step does
// NOT need the Veda-whitelisted deployer key (that was only for the vault deploy itself).
//   source .env && forge script script/MerkleRootCreation/Mainnet/CreateLoopOptimiserClusterMerkleRoot.s.sol:CreateLoopOptimiserClusterLeafs --rpc-url $MAINNET_RPC_URL --broadcast
contract CreateLoopOptimiserClusterLeafs is Script, MerkleTreeHelper {
    uint256 public privateKey;

    // Deployed 2026-06-16 (deployments/addresses/Mainnet/LoopOptimiserCluster.json)
    address internal constant BORING_VAULT = 0x31aCffb26E80A319018cbd049CeA3389635dFc41;
    address internal constant MANAGER = 0x7141A06771fc62f9F5aa714CeD79EA7dc8Bce64F;
    address internal constant ACCOUNTANT = 0xd050B8f3b1568dF89e1659a0812c7beDc626881c;
    address internal constant ROLES_AUTHORITY = 0xFbe001B540eA54cAbae89EF6D1C34ef8CcA7A837;
    // LoopOptimiserClusterDecoderAndSanitizer, deployed + verified 2026-06-16
    address internal constant DECODER_AND_SANITIZER = 0x2953352655062b1D9f589fE60e9A247BEdcfcb21;
    // Shared Morpho flashloan adapter (manager-agnostic; passes target manager via callback data). Verify it
    // can call THIS manager before relying on it; otherwise deploy a dedicated one and update both places.
    address internal constant FLASHLOAN_ADAPTER = 0x82baFd173334e9cd34eB746BA6b55ffcb4d06a4d;

    address internal constant STRATEGIST = 0x651D67e5Daf82C5E2c8e4159f6E2E9c6e2d99057;

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 7;

    function setUp() external {
        privateKey = vm.envUint("LOOP_OPTIMISER_OWNER"); // must be the vault owner (0x651D…)
        vm.createSelectFork("mainnet");
        setSourceChainName("mainnet");

        setAddress(true, mainnet, "boringVault", BORING_VAULT);
        setAddress(true, mainnet, "managerAddress", MANAGER);
        setAddress(true, mainnet, "manager", MANAGER);
        setAddress(true, mainnet, "accountantAddress", ACCOUNTANT);
        setAddress(true, mainnet, "rawDataDecoderAndSanitizer", DECODER_AND_SANITIZER);
        setAddress(true, mainnet, "morphoBlueFlashLoanAdapterAddress", FLASHLOAN_ADAPTER);
    }

    function run() external {
        ManageLeaf[] memory leafs = new ManageLeaf[](512);
        _addLeafs(leafs);

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        bytes32 manageRoot = manageTree[manageTree.length - 1][0];
        _generateLeafs("./leafs/Mainnet/LoopOptimiserClusterStrategistLeafs.json", leafs, manageRoot, manageTree);

        ManagerWithMerkleVerification manager = ManagerWithMerkleVerification(MANAGER);
        RolesAuthority rolesAuthority = RolesAuthority(ROLES_AUTHORITY);

        vm.startBroadcast(privateKey);
        // Strategist EOA submits manage calls; the flashloan adapter re-enters the manager, so it needs the
        // SAME root under its own address plus MANAGER + STRATEGIST roles.
        manager.setManageRoot(STRATEGIST, manageRoot);
        manager.setManageRoot(FLASHLOAN_ADAPTER, manageRoot);
        rolesAuthority.setUserRole(STRATEGIST, STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(FLASHLOAN_ADAPTER, MANAGER_ROLE, true);
        rolesAuthority.setUserRole(FLASHLOAN_ADAPTER, STRATEGIST_ROLE, true);
        vm.stopBroadcast();
    }

    function _addLeafs(ManageLeaf[] memory leafs) internal {
        // ======================= shared across all loops =======================
        ERC20[] memory feeAssets = new ERC20[](1);
        feeAssets[0] = getERC20(sourceChain, "USDC");
        _addLeafsForFeeClaiming(leafs, getAddress(sourceChain, "accountantAddress"), feeAssets, false);
        // Morpho 0%-fee USDC flashloan (lever / unwind atomically) — one set covers every USDC loop
        _addMorphoBlueFlashLoanLeafs(leafs, getAddress(sourceChain, "USDC"));

        // ======================= loop 1: siUSD =======================
        // wrap: Infini gateway USDC <-> siUSD (mintAndStake / unstake -> iUSD -> redeem)
        _addInfiniV1Leafs(leafs, getAddress(sourceChain, "USDC"));
        // collateral: supplyCollateral / borrow / repay / withdrawCollateral on siUSD/USDC
        _addMorphoBlueCollateralLeafs(leafs, getBytes32(sourceChain, "siUSD_USDC_915"));
        // public allocator: whitelist every v1.1 MetaMorpho vault that lists the siUSD market, so the
        // strategist can reallocate from whichever has capacity. All maxIn==0 today (inert until a curator
        // opens inbound flow), but the leaves are ready. V2 vaults that list the market are NOT reachable by
        // the classic PublicAllocator and are intentionally omitted.
        address[] memory siusdSuppliers = new address[](8);
        siusdSuppliers[0] = 0xF9bdDd4A9b3A45f980e11fDDE96e16364dDBEc49; // Yearn OG USDC
        siusdSuppliers[1] = 0xc582F04d8a82795aa2Ff9c8bb4c1c889fe7b754e; // Gauntlet USDC Frontier
        siusdSuppliers[2] = 0xBEeFFF209270748ddd194831b3fa287a5386f5bC; // Smokehouse USDC
        siusdSuppliers[3] = 0xbEEf390D2e65d6E43A67875106d4A48f700F2832; // Safe x Smokehouse USDC
        siusdSuppliers[4] = 0xBEeF1f5Bd88285E5B239B6AAcb991d38ccA23Ac9; // Steakhouse infiniFi USDC
        siusdSuppliers[5] = 0x8eB67A509616cd6A7c1B3c8C21D48FF57df3d458; // Gauntlet USDC Core
        siusdSuppliers[6] = 0x777791C4d6DC2CE140D00D2828a7C93503c67777; // Hyperithm USDC Apex
        siusdSuppliers[7] = 0x62fE596d59fB077c2Df736dF212E0AFfb522dC78; // Clearstar USDC Reactor
        for (uint256 i; i < siusdSuppliers.length; ++i) {
            _addMorphoPublicAllocatorLeafs(leafs, siusdSuppliers[i], getBytes32(sourceChain, "siUSD_USDC_915"));
        }

        // ======================= loop 2: USD3 =======================
        // wrap: USD3 is ERC4626 over USDC -> deposit/redeem directly (no external gateway)
        _addERC4626Leafs(leafs, ERC4626(getAddress(sourceChain, "USD3")));
        // collateral: supplyCollateral / borrow / repay / withdrawCollateral on USD3/USDC
        _addMorphoBlueCollateralLeafs(leafs, getBytes32(sourceChain, "USD3_USDC_915"));
        // public allocator: 3Jane Ecosystem Vault is the only supplier of the USD3 market — but it is a
        // Vault V2 and has NOT enrolled the classic PublicAllocator, so this leaf is currently inert (the call
        // would revert). Kept per design; revisit once a v1.1 supplier or a V2 reallocation path exists.
        _addMorphoPublicAllocatorLeafs(
            leafs, 0xe05faDf242331808f504661BEA65972594869826, getBytes32(sourceChain, "USD3_USDC_915")
        );
    }
}
