// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

import "forge-std/Script.sol";

contract CreateLoopOptimiserClusterLeafs is Script, MerkleTreeHelper {
    uint256 public privateKey;

    address internal constant BORING_VAULT = 0x31aCffb26E80A319018cbd049CeA3389635dFc41;
    address internal constant MANAGER = 0x7141A06771fc62f9F5aa714CeD79EA7dc8Bce64F;
    address internal constant ACCOUNTANT = 0xd050B8f3b1568dF89e1659a0812c7beDc626881c;
    address internal constant ROLES_AUTHORITY = 0xFbe001B540eA54cAbae89EF6D1C34ef8CcA7A837;
    address internal constant DECODER_AND_SANITIZER = 0x2953352655062b1D9f589fE60e9A247BEdcfcb21;
    address internal constant FLASHLOAN_ADAPTER = 0x82baFd173334e9cd34eB746BA6b55ffcb4d06a4d;
    address internal constant STRATEGIST = 0x651D67e5Daf82C5E2c8e4159f6E2E9c6e2d99057;

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 7;

    function setUp() external {
        privateKey = vm.envUint("LOOP_OPTIMISER_OWNER");
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
        // The flashloan adapter re-enters the manager, so it carries the same root and the manage roles.
        manager.setManageRoot(STRATEGIST, manageRoot);
        manager.setManageRoot(FLASHLOAN_ADAPTER, manageRoot);
        rolesAuthority.setUserRole(STRATEGIST, STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(FLASHLOAN_ADAPTER, MANAGER_ROLE, true);
        rolesAuthority.setUserRole(FLASHLOAN_ADAPTER, STRATEGIST_ROLE, true);
        vm.stopBroadcast();
    }

    function _addLeafs(ManageLeaf[] memory leafs) internal {
        // shared across all loops
        ERC20[] memory feeAssets = new ERC20[](1);
        feeAssets[0] = getERC20(sourceChain, "USDC");
        _addLeafsForFeeClaiming(leafs, getAddress(sourceChain, "accountantAddress"), feeAssets, false);
        _addMorphoBlueFlashLoanLeafs(leafs, getAddress(sourceChain, "USDC"));

        // siUSD loop: Infini gateway wrap + Morpho collateral.
        // Supply leafs first: they add the approve(USDC -> MorphoBlue) the repay path needs
        // (the collateral helper alone skips it). Mirrors the ETH/BTC carry cluster scripts.
        _addInfiniV1Leafs(leafs, getAddress(sourceChain, "USDC"));
        _addMorphoBlueSupplyLeafs(leafs, getBytes32(sourceChain, "siUSD_USDC_915"));
        _addMorphoBlueCollateralLeafs(leafs, getBytes32(sourceChain, "siUSD_USDC_915"));
        // PublicAllocator suppliers of the siUSD market (one leaf per source vault)
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

        // USD3 loop: ERC4626 wrap (USD3 is an ERC4626 over USDC) + Morpho collateral.
        // Supply leafs first for the approve(USDC -> MorphoBlue) repay leaf (see siUSD note).
        _addERC4626Leafs(leafs, ERC4626(getAddress(sourceChain, "USD3")));
        _addMorphoBlueSupplyLeafs(leafs, getBytes32(sourceChain, "USD3_USDC_915"));
        _addMorphoBlueCollateralLeafs(leafs, getBytes32(sourceChain, "USD3_USDC_915"));
        // PublicAllocator supplier of the USD3 market
        _addMorphoPublicAllocatorLeafs(
            leafs, 0xe05faDf242331808f504661BEA65972594869826, getBytes32(sourceChain, "USD3_USDC_915")
        );
    }
}
