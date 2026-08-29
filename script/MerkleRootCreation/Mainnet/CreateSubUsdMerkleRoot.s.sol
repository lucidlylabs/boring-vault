// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {Script} from "forge-std/Script.sol";

contract CreateSubUsdMerkleRootScript is Script, MerkleTreeHelper {
    using FixedPointMathLib for uint256;

    // subUSD addresses — fill in after running DeployArcticArchitectureWithConfig.s.sol with subUSD.json
    address public boringVault = address(0);
    address public managerAddress = address(0);
    address public accountantAddress = address(0);
    address public rolesAuthority = address(0);

    // Fill in after deploying SubUsdDecoderAndSanitizer via `forge create`
    address public rawDataDecoderAndSanitizer = address(0);

    // Strategist EOA / multisig — mentor will provide
    address public strategist = address(0);

    // syUSD architecture (already deployed on mainnet)
    address public syUsdVault = 0x279CAD277447965AF3d24a78197aad1B02a2c589;
    address public syUsdWithdrawQueue = 0xF632c10b19f2a0451cD4A653fC9ca0c15eA1040b;
    address public syUsdTeller = 0xaefc11908fF97c335D16bdf9F2Bf720817423825;
    address public syUsdQueueSolver = 0x1d82e9bCc8F325caBBca6E6A3B287fE586536805;

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 7;

    function setUp() external {
        setSourceChainName(mainnet);
        vm.createSelectFork(sourceChain);
    }

    function run() external {
        _generateMerkleRoot();
    }

    function _generateMerkleRoot() public {
        require(boringVault != address(0), "set boringVault");
        require(managerAddress != address(0), "set managerAddress");
        require(accountantAddress != address(0), "set accountantAddress");
        require(rolesAuthority != address(0), "set rolesAuthority");
        require(rawDataDecoderAndSanitizer != address(0), "set decoder");
        require(strategist != address(0), "set strategist");

        setAddress(true, mainnet, "boringVault", boringVault);
        setAddress(true, mainnet, "managerAddress", managerAddress);
        setAddress(true, mainnet, "manager", managerAddress);
        setAddress(true, mainnet, "accountantAddress", accountantAddress);
        setAddress(true, mainnet, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizer);

        ManageLeaf[] memory leafs = new ManageLeaf[](32);

        ERC20[] memory assets = new ERC20[](1);
        assets[0] = getERC20(sourceChain, "USDC");
        _addLeafsForFeeClaiming(leafs, getAddress(sourceChain, "accountantAddress"), assets, false);

        _addTellerLeafs(leafs, syUsdTeller, assets, false, true);
        _addWithdrawQueueLeafs(leafs, syUsdWithdrawQueue, syUsdVault, assets);
        _addSelfSolveLeafs(leafs, assets, syUsdQueueSolver, boringVault, syUsdTeller);

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        string memory filePath = "./leafs/Mainnet/SubUsdStrategistLeafs.json";
        _generateLeafs(filePath, leafs, manageTree[manageTree.length - 1][0], manageTree);

        RolesAuthority authority = RolesAuthority(rolesAuthority);
        ManagerWithMerkleVerification manager = ManagerWithMerkleVerification(managerAddress);
        vm.startBroadcast(vm.envUint("DEPLOYER01"));
        manager.setManageRoot(strategist, manageTree[manageTree.length - 1][0]);

        authority.setUserRole(strategist, STRATEGIST_ROLE, true);
        vm.stopBroadcast();
    }
}
