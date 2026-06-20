// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract CreateHighYieldUsdcLendingClusterMerkleRoot is Script, MerkleTreeHelper {
    address internal constant ACCOUNTANT = 0xEfCC1C565385Db805563365A4A06030268B02648;
    address internal constant BORING_VAULT = 0xA762361D505E33D08D5170DfcBf8254a2d58C2B8;
    address internal constant MANAGER = 0x5Eee7d06Dd44446aA626357cAc5af0aa2C9755A2;
    address internal constant DECODER_AND_SANITIZER = 0x02649C96083c61C5419e3b3516fEDC0f5E8115C2;

    function setUp() external {
        setSourceChainName(mainnet);
        vm.createSelectFork(sourceChain);
        setAddress(true, mainnet, "accountantAddress", ACCOUNTANT);
        setAddress(true, mainnet, "boringVault", BORING_VAULT);
        setAddress(true, mainnet, "managerAddress", MANAGER);
        setAddress(true, mainnet, "rawDataDecoderAndSanitizer", DECODER_AND_SANITIZER);
    }

    function run() external {
        ManageLeaf[] memory leafs = new ManageLeaf[](16);

        _addMorphoBlueSupplyLeafs(leafs, getBytes32(sourceChain, "cbBTC_USDC_86"));
        _addMorphoBlueSupplyLeafs(leafs, getBytes32(sourceChain, "AA_FalconXUSDC_USDC_77"));
        _addMorphoBlueSupplyLeafs(leafs, getBytes32(sourceChain, "mF_ONE_USDC_915"));
        _addMorphoBlueSupplyLeafs(leafs, getBytes32(sourceChain, "srRoyUSDC_USDC_915"));
        _addMorphoBlueSupplyLeafs(leafs, getBytes32(sourceChain, "fxSAVE_USDC_86"));

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        bytes32 manageRoot = manageTree[manageTree.length - 1][0];

        _generateLeafs("./leafs/Mainnet/HighYieldUsdcLendingClusterStrategistLeafs.json", leafs, manageRoot, manageTree);
        console2.logBytes32(manageRoot);
    }
}
