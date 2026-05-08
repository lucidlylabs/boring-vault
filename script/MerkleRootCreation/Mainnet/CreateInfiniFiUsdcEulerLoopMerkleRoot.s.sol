// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {Script} from "forge-std/Script.sol";

contract CreateInfiniFiUsdcEulerLoopMerkleRootScript is Script, MerkleTreeHelper {
    using FixedPointMathLib for uint256;

    // InfiniFiUsdcCluster (deployed)
    address public boringVault = 0x96Ee83F0C132A8b29866c8Ae6E149D6e6822b291;
    address public managerAddress = 0x617f47CC5021607a46d9d76942d8103d5cc47175;
    address public accountantAddress = 0x2E6B1bA9CdE7fAD66E34122ad744c3B004adAdaF;
    RolesAuthority public rolesAuthority = RolesAuthority(0xF312FC97f7552299cd581C9238768D435A8B00B8);

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 7;

    // TODO: set after deploying InfiniFiUsdcEulerLoopDecoderAndSanitizer.
    address public rawDataDecoderAndSanitizer = address(0);

    // TODO: set after deploying a vault-bound MorphoFlashLoanAdapter for InfiniFiUsdcCluster.
    address public flashLoanAdapter = address(0);

    // TODO: set to the strategist EOA / multisig that submits manage txs for this vault.
    address public strategist = address(0);

    function setUp() external {
        setSourceChainName(mainnet);
        vm.createSelectFork(sourceChain);
    }

    function run() external {
        _generateMerkleRoot();
    }

    function _generateMerkleRoot() public {
        require(rawDataDecoderAndSanitizer != address(0), "set decoder address");
        require(flashLoanAdapter != address(0), "set flashloan adapter address");
        require(strategist != address(0), "set strategist address");

        setAddress(true, mainnet, "boringVault", boringVault);
        setAddress(true, mainnet, "managerAddress", managerAddress);
        setAddress(true, mainnet, "manager", managerAddress);
        setAddress(true, mainnet, "accountantAddress", accountantAddress);
        setAddress(true, mainnet, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizer);
        setAddress(true, mainnet, "morphoBlueFlashLoanAdapterAddress", flashLoanAdapter);

        ManageLeaf[] memory leafs = new ManageLeaf[](64);

        // Fee claiming on USDC.
        ERC20[] memory feeAssets = new ERC20[](1);
        feeAssets[0] = getERC20(sourceChain, "USDC");
        _addLeafsForFeeClaiming(leafs, getAddress(sourceChain, "accountantAddress"), feeAssets, false);

        // The full looped locked-iUSD strategy.
        _addInfiniFiUsdcEulerLoopLeafs(leafs);

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        string memory filePath = "./leafs/Mainnet/InfiniFiUsdcEulerLoopStrategistLeafs.json";
        _generateLeafs(filePath, leafs, manageTree[manageTree.length - 1][0], manageTree);

        ManagerWithMerkleVerification manager = ManagerWithMerkleVerification(managerAddress);
        vm.startBroadcast(vm.envUint("BORING_DEVELOPER"));
        manager.setManageRoot(strategist, manageTree[manageTree.length - 1][0]);
        manager.setManageRoot(flashLoanAdapter, manageTree[manageTree.length - 1][0]);

        rolesAuthority.setUserRole(flashLoanAdapter, MANAGER_ROLE, true);
        rolesAuthority.setUserRole(flashLoanAdapter, STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(strategist, STRATEGIST_ROLE, true);
        vm.stopBroadcast();
    }
}
