// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

/**
 * @notice Safe-multisig variant of CreateLoopOptimiserClusterMerkleRoot. Builds the SAME leafs +
 *         merkle root as the EOA script and writes the leafs JSON, then -- instead of broadcasting --
 *         emits the two setManageRoot calls as calldata + a Safe Transaction Builder batch for the
 *         loop-cluster owner Safe to execute. Needs NO private key.
 *
 *  Run (note: NO --broadcast, NO key):
 *    forge script \
 *      script/MerkleRootCreation/Mainnet/CreateLoopOptimiserClusterMerkleRootSafe.s.sol:CreateLoopOptimiserClusterLeafsSafe \
 *      --rpc-url $ETHEREUM_RPC_URL -vvvv
 *
 *  Outputs:
 *    - ./leafs/Mainnet/LoopOptimiserClusterStrategistLeafs.json  (leafs -- identical to the EOA script)
 *    - ./leafs/Mainnet/LoopOptimiserClusterSafeBatch.json        (Safe Transaction Builder import file)
 *    - console: the new root + per-tx (to, data)
 *
 *  Then in the Safe web app -> Apps -> Transaction Builder, import LoopOptimiserClusterSafeBatch.json
 *  (or paste each (to, data) as a raw custom transaction, value 0), sign, execute.
 *
 *  The strategist/flashloan-adapter ROLES are already granted (the cluster is live), so only the two
 *  setManageRoot(strategist|flashLoanAdapter, newRoot) calls are emitted.
 */
contract CreateLoopOptimiserClusterLeafsSafe is Script, MerkleTreeHelper {
    address internal constant BORING_VAULT = 0x31aCffb26E80A319018cbd049CeA3389635dFc41;
    address internal constant MANAGER = 0x7141A06771fc62f9F5aa714CeD79EA7dc8Bce64F;
    address internal constant ACCOUNTANT = 0xd050B8f3b1568dF89e1659a0812c7beDc626881c;
    address internal constant ROLES_AUTHORITY = 0xFbe001B540eA54cAbae89EF6D1C34ef8CcA7A837;
    // Loop-cluster decoder, redeployed 2026-06-20 to add the Cap mixin (cUSD mint/burn) for the
    // stcUSD/USDT loop. The prior 0x2953... lacked Cap -> stcUSD lever reverted FunctionSelectorNotSupported.
    address internal constant DECODER_AND_SANITIZER = 0x9B5954c691aC131e7c07eE49f56287227D2a9AB5;
    address internal constant FLASHLOAN_ADAPTER = 0x3D4cC0b99ffcA3B373769834Ab8Dd5D5616a14Ed;
    // The LIVE loop-cluster strategist EOA (verified on-chain: it currently holds the manage root).
    address internal constant STRATEGIST = 0x451c73033a4548553b916ce7AF69AB8c8FA34504;

    function setUp() external {
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
        bytes32 newRoot = manageTree[manageTree.length - 1][0];
        _generateLeafs("./leafs/Mainnet/LoopOptimiserClusterStrategistLeafs.json", leafs, newRoot, manageTree);

        // The only privileged calls the Safe must execute: re-point both manage roots to the new root.
        // (The flashloan adapter re-enters the manager so it carries the same root.)
        address[] memory tos = new address[](2);
        bytes[] memory datas = new bytes[](2);
        string[] memory labels = new string[](2);

        tos[0] = MANAGER;
        datas[0] = abi.encodeWithSelector(ManagerWithMerkleVerification.setManageRoot.selector, STRATEGIST, newRoot);
        labels[0] = "manager.setManageRoot(strategist, newRoot)";

        tos[1] = MANAGER;
        datas[1] =
            abi.encodeWithSelector(ManagerWithMerkleVerification.setManageRoot.selector, FLASHLOAN_ADAPTER, newRoot);
        labels[1] = "manager.setManageRoot(flashLoanAdapter, newRoot)";

        console.log("=== new manage root ===");
        console.logBytes32(newRoot);
        console.log("=== Safe transactions (chainId 1, value 0) ===");
        for (uint256 i; i < tos.length; ++i) {
            console.log(labels[i]);
            console.log("  to:");
            console.logAddress(tos[i]);
            console.log("  data:");
            console.logBytes(datas[i]);
        }

        _writeSafeBatch(tos, datas);
    }

    /// @dev Writes a Safe Transaction Builder import file (https://app.safe.global -> Transaction Builder).
    function _writeSafeBatch(address[] memory tos, bytes[] memory datas) internal {
        string memory txs = "";
        for (uint256 i; i < tos.length; ++i) {
            string memory one = string.concat(
                '{"to":"',
                vm.toString(tos[i]),
                '","value":"0","data":"',
                vm.toString(datas[i]),
                '","contractMethod":null,"contractInputsValues":null}'
            );
            txs = i == 0 ? one : string.concat(txs, ",", one);
        }
        string memory batch = string.concat(
            '{"version":"1.0","chainId":"1","createdAt":',
            vm.toString(block.timestamp * 1000),
            ',"meta":{"name":"LoopOptimiserCluster: setManageRoot (add stcUSD/USDT loop)",',
            '"description":"Generated by CreateLoopOptimiserClusterMerkleRootSafe.s.sol"},"transactions":[',
            txs,
            "]}"
        );
        string memory outPath = "./leafs/Mainnet/LoopOptimiserClusterSafeBatch.json";
        vm.writeFile(outPath, batch);
        console.log("Wrote Safe Transaction Builder batch:");
        console.log(outPath);
    }

    function _addLeafs(ManageLeaf[] memory leafs) internal {
        // shared across all loops
        ERC20[] memory feeAssets = new ERC20[](1);
        feeAssets[0] = getERC20(sourceChain, "USDC");
        _addLeafsForFeeClaiming(leafs, getAddress(sourceChain, "accountantAddress"), feeAssets, false);
        _addMorphoBlueFlashLoanLeafs(leafs, getAddress(sourceChain, "USDC"));

        // siUSD loop: Infini gateway wrap + Morpho collateral. Supply leafs first (approve(USDC->Morpho)).
        _addInfiniV1Leafs(leafs, getAddress(sourceChain, "USDC"));
        _addMorphoBlueSupplyLeafs(leafs, getBytes32(sourceChain, "siUSD_USDC_915"));
        _addMorphoBlueCollateralLeafs(leafs, getBytes32(sourceChain, "siUSD_USDC_915"));
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

        // USD3 loop: ERC4626 wrap + Morpho collateral.
        _addERC4626Leafs(leafs, ERC4626(getAddress(sourceChain, "USD3")));
        _addMorphoBlueSupplyLeafs(leafs, getBytes32(sourceChain, "USD3_USDC_915"));
        _addMorphoBlueCollateralLeafs(leafs, getBytes32(sourceChain, "USD3_USDC_915"));
        _addMorphoPublicAllocatorLeafs(
            leafs, 0xe05faDf242331808f504661BEA65972594869826, getBytes32(sourceChain, "USD3_USDC_915")
        );

        // stcUSD loop (NON-USDC loan): collateral = stcUSD, loan = USDT. USDC->cUSD(Cap mint)->stcUSD,
        // + Morpho stcUSD/USDT, + Magpie USDT<->USDC bridge (both directions).
        address[] memory capDepositTokens = new address[](1);
        capDepositTokens[0] = getAddress(sourceChain, "USDC");
        _addCapLeafs(leafs, capDepositTokens);
        _addMorphoBlueSupplyLeafs(leafs, getBytes32(sourceChain, "stcUsdUsdtMarketId"));
        _addMorphoBlueCollateralLeafs(leafs, getBytes32(sourceChain, "stcUsdUsdtMarketId"));
        address[] memory magpieTokens = new address[](2);
        magpieTokens[0] = getAddress(sourceChain, "USDC");
        magpieTokens[1] = getAddress(sourceChain, "USDT");
        SwapKind[] memory magpieKind = new SwapKind[](2);
        magpieKind[0] = SwapKind.BuyAndSell;
        magpieKind[1] = SwapKind.BuyAndSell;
        _addMagpieSwapLeafs(leafs, magpieTokens, magpieKind);
    }
}
