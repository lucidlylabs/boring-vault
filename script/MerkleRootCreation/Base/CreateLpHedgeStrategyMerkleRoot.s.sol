// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {Script} from "forge-std/Script.sol";

/**
 * source .env && forge script script/MerkleRootCreation/Base/CreateLpHedgeStrategyMerkleRoot.s.sol \
 *   --rpc-url $BASE_RPC_URL --broadcast
 */
contract CreateLpHedgeStrategyMerkleRootScript is Script, MerkleTreeHelper {
    int24 internal constant AERODROME_WETH_CBBTC_TICK_SPACING = 10;

    address public accountantAddress;
    address public boringVault;
    address public managerAddress;
    address public rawDataDecoderAndSanitizer;
    address public strategist;

    function setUp() external {
        setSourceChainName(base);
        vm.createSelectFork(sourceChain);

        accountantAddress = vm.envAddress("ACCOUNTANT_ADDRESS");
        boringVault = vm.envAddress("BORING_VAULT_ADDRESS");
        managerAddress = vm.envAddress("MANAGER_ADDRESS");
        rawDataDecoderAndSanitizer = vm.envAddress("DECODER_AND_SANITIZER_ADDRESS");
        strategist = vm.envAddress("LP_HEDGE_STRATEGIST");
    }

    function run() external {
        _generateMerkleRoot();
    }

    function _generateMerkleRoot() public {
        setAddress(true, base, "boringVault", boringVault);
        setAddress(true, base, "managerAddress", managerAddress);
        setAddress(true, base, "accountantAddress", accountantAddress);
        setAddress(true, base, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizer);

        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        ERC20[] memory feeAssets = new ERC20[](2);
        feeAssets[0] = getERC20(sourceChain, "cbBTC");
        feeAssets[1] = getERC20(sourceChain, "WETH");
        _addLeafsForFeeClaiming(leafs, getAddress(sourceChain, "accountantAddress"), feeAssets, false);

        ERC20[] memory supplyAssets = new ERC20[](1);
        supplyAssets[0] = getERC20(sourceChain, "cbBTC");

        ERC20[] memory borrowAssets = new ERC20[](1);
        borrowAssets[0] = getERC20(sourceChain, "WETH");
        _addAaveV3Leafs(leafs, supplyAssets, borrowAssets);

        address[] memory token0 = new address[](1);
        token0[0] = getAddress(sourceChain, "WETH");
        address[] memory token1 = new address[](1);
        token1[0] = getAddress(sourceChain, "cbBTC");
        address[] memory gauges = new address[](1);
        gauges[0] = address(0);
        _addVelodromeV3Leafs(
            leafs, token0, token1, getAddress(sourceChain, "aerodromeNonFungiblePositionManager"), gauges
        );

        _addAerodromeSlipstreamSwapLeafs(
            leafs,
            getAddress(sourceChain, "WETH"),
            getAddress(sourceChain, "cbBTC"),
            AERODROME_WETH_CBBTC_TICK_SPACING,
            getAddress(sourceChain, "aerodromeSlipstreamSwapRouter")
        );

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        string memory filePath = "./leafs/Base/LpHedgeStrategyLeafs.json";
        _generateLeafs(filePath, leafs, manageTree[manageTree.length - 1][0], manageTree);

        ManagerWithMerkleVerification manager = ManagerWithMerkleVerification(managerAddress);
        vm.startBroadcast(vm.envUint("PK"));
        manager.setManageRoot(managerAddress, manageTree[manageTree.length - 1][0]);
        manager.setManageRoot(strategist, manageTree[manageTree.length - 1][0]);
        vm.stopBroadcast();
    }
}
