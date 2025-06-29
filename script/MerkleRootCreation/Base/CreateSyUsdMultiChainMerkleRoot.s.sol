// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

contract CreateSyUsdMultiChainMerkleRootScript is Script, MerkleTreeHelper {
    using FixedPointMathLib for uint256;

    uint256 public privateKeyOwner;
    uint256 public privateKeyMorphoAgent;

    address public accountantAddress = 0x03D9a9cE13D16C7cFCE564f41bd7E85E5cde8Da6;
    address public boringVault = 0x279CAD277447965AF3d24a78197aad1B02a2c589;
    address public managerAddress = 0x9B3e565ffC70c4b72516BC2dbec4b3c790940CE8;
    address public rawDataDecoderAndSanitizer01 = 0xedbB1308b8E213d7C76F65Ca11cF38136b8a8a83;

    function setUp() external {
        setSourceChainName(base);
        vm.createSelectFork(sourceChain);
    }

    function run() external {
        _generateSyUsdMultiChainMerkleRoot();
    }

    function _generateSyUsdMultiChainMerkleRoot() public {
        setAddress(true, base, "boringVault", boringVault);
        setAddress(true, base, "managerAddress", managerAddress);
        setAddress(true, base, "accountantAddress", accountantAddress);
        setAddress(true, base, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizer01);

        ManageLeaf[] memory leafs = new ManageLeaf[](1024);
        ERC20[] memory feeAssets = new ERC20[](2);
        feeAssets[0] = getERC20(sourceChain, "USDC");
        feeAssets[1] = getERC20(sourceChain, "USDS");
        _addLeafsForFeeClaiming(leafs, getAddress(sourceChain, "accountantAddress"), feeAssets, false);

        ERC20[] memory bridgeAssets = new ERC20[](1);
        bridgeAssets[0] = getERC20(sourceChain, "USDC");
        ERC20[] memory feeTokens = new ERC20[](2);
        feeTokens[0] = getERC20(sourceChain, "WETH");
        feeTokens[1] = getERC20(sourceChain, "GHO");
        _addCcipBridgeLeafs(leafs, ccipMainnetChainSelector, bridgeAssets, feeTokens);
        _addCcipBridgeLeafs(leafs, ccipArbitrumChainSelector, bridgeAssets, feeTokens);
        _addCcipBridgeLeafs(leafs, ccipBscChainSelector, bridgeAssets, feeTokens);

        _addBalancerFlashloanLeafs(leafs, getAddress(sourceChain, "USDC"));
        _addBalancerFlashloanLeafs(leafs, getAddress(sourceChain, "WETH"));

        // 1inch assets;
        address[] memory oneInchAssets = new address[](2);
        oneInchAssets[0] = getAddress(sourceChain, "USDC");
        oneInchAssets[1] = getAddress(sourceChain, "USDS");
        SwapKind[] memory kind = new SwapKind[](2);
        kind[0] = SwapKind.BuyAndSell;
        kind[1] = SwapKind.BuyAndSell;

        _addLeafsFor1InchGeneralSwapping(leafs, oneInchAssets, kind);
        _addOdosSwapLeafs(leafs, oneInchAssets, kind);

        _addERC4626Leafs(leafs, ERC4626(getAddress(sourceChain, "YearnOgUsdc")));

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        ManagerWithMerkleVerification manager = ManagerWithMerkleVerification(managerAddress);
        vm.startBroadcast(vm.envUint("BORING_OWNER"));
        manager.setManageRoot(managerAddress, manageTree[manageTree.length - 1][0]);
        manager.setManageRoot(vm.addr(vm.envUint("BORING_MORPHO_AGENT")), manageTree[manageTree.length - 1][0]);
        vm.stopBroadcast();
    }
}
