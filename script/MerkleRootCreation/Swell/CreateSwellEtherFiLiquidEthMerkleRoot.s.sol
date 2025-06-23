// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import "forge-std/Script.sol";

/**
 *  source .env && forge script script/MerkleRootCreation/Swell/CreateSwellEtherFiLiquidEthMerkleRoot.s.sol:CreateSwellEtherFiLiquidEthMerkleRoot --rpc-url $SWELL_CHAIN_RPC_URL
 */
// contract CreateSwellEtherFiLiquidEthMerkleRoot is Script, MerkleTreeHelper {
//     using FixedPointMathLib for uint256;
//
//     address public boringVault = 0xf0bb20865277aBd641a307eCe5Ee04E79073416C;
//     address public managerAddress = 0xDEa7AF4a96A762c9d43A7eE02acecD20A3C6D8B6;
//     address public accountantAddress = 0x0d05D94a5F1E76C18fbeB7A13d17C8a314088198;
//     address public rawDataDecoderAndSanitizer = 0xA81BA0b3A4743207a4801882b7a050d959f26f35;
//
//     function setUp() external {}
//
//     /**
//      * @notice Uncomment which script you want to run.
//      */
//     function run() external {
//         generateMerkleRoot();
//     }
//
//     function generateMerkleRoot() public {
//         setSourceChainName(swell);
//         setAddress(false, swell, "boringVault", boringVault);
//         setAddress(false, swell, "managerAddress", managerAddress);
//         setAddress(false, swell, "accountantAddress", accountantAddress);
//         setAddress(false, swell, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizer);
//
//         ManageLeaf[] memory leafs = new ManageLeaf[](64);
//
//         // ========================== Native Wrapping ==========================
//         _addNativeLeafs(leafs);
//
//         // ========================== LayerZero ==========================
//         _addLayerZeroLeafs(
//             leafs, getERC20(sourceChain, "WEETH"), getAddress(sourceChain, "WEETH"), layerZeroMainnetEndpointId
//         );
//
//         // ========================== Standard Bridge ==========================
//         ERC20[] memory localTokens = new ERC20[](0);
//         ERC20[] memory remoteTokens = new ERC20[](0);
//         _addStandardBridgeLeafs(
//             leafs,
//             mainnet,
//             address(0),
//             address(0),
//             getAddress(sourceChain, "standardBridge"),
//             address(0),
//             localTokens,
//             remoteTokens
//         );
//
//         // ========================== Euler ==========================
//         {
//         ERC4626[] memory depositVaults = new ERC4626[](2);
//         depositVaults[0] = ERC4626(getAddress(sourceChain, "eulerWETH"));
//         depositVaults[1] = ERC4626(getAddress(sourceChain, "eulerWEETH"));
//
//         address[] memory subaccounts = new address[](1);
//         subaccounts[0] = address(boringVault);
//
//         ERC4626[] memory borrowVaults = new ERC4626[](1);
//         borrowVaults[0] = ERC4626(getAddress(sourceChain, "eulerWETH"));
//
//         _addEulerDepositLeafs(leafs, depositVaults, subaccounts);
//         _addEulerBorrowLeafs(leafs, borrowVaults, subaccounts);
//         }
//
//         // ========================== Merkl ==========================
//         ERC20[] memory tokensToClaim = new ERC20[](1);
//         tokensToClaim[0] = getERC20(sourceChain, "WSWELL");
//         _addMerklLeafs(
//             leafs, getAddress(sourceChain, "merklDistributor"), getAddress(sourceChain, "dev1Address"), tokensToClaim
//         );
//
//         // ========================== Velodrome ==========================
//         address[] memory token0 = new address[](1);
//         token0[0] = getAddress(sourceChain, "WETH");
//         address[] memory token1 = new address[](1);
//         token1[0] = getAddress(sourceChain, "WEETH");
//         address[] memory gauges = new address[](1);
//         gauges[0] = getAddress(sourceChain, "velodrome_weth_weeth_v3_gauge");
//         _addVelodromeV3Leafs(
//             leafs, token0, token1, getAddress(sourceChain, "velodromeNonFungiblePositionManager"), gauges
//         );
//
//         // ========================== Ambient ==========================
//         _addAmbientLPLeafs(leafs, getAddress(sourceChain, "WEETH"), getAddress(sourceChain, "ETH"));
//         _addAmbientSwapLeafs(leafs, getAddress(sourceChain, "WEETH"), getAddress(sourceChain, "ETH")); //can remove if they don't want/need swapping between the two
//
//         // ========================== Verify & Generate ==========================
//
//         _verifyDecoderImplementsLeafsFunctionSelectors(leafs);
//
//         string memory filePath = "./leafs/Swell/EtherFiLiquidEth.json";
//
//         bytes32[][] memory manageTree = _generateMerkleTree(leafs);
//
//         _generateLeafs(filePath, leafs, manageTree[manageTree.length - 1][0], manageTree);
//     }
// }
