// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {MainnetAddresses} from "test/resources/MainnetAddresses.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {LayerZeroTeller} from "src/base/Roles/CrossChain/Bridges/LayerZero/LayerZeroTeller.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {BoringOnChainQueue} from "src/base/Roles/BoringQueue/BoringOnChainQueue.sol";
import {BoringSolver} from "src/base/Roles/BoringQueue/BoringSolver.sol";
import {SyUsdDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/SyUsdDecoderAndSanitizer.sol";
import {DecoderCustomTypes} from "src/interfaces/DecoderCustomTypes.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {
    MerkleTreeHelper,
    IMB,
    PendleMarket,
    PendleSy,
    ISilo
} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {BalancerVault} from "src/interfaces/BalancerVault.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/DeployDecoderAndSanitizer.s.sol:DeployDecoderAndSanitizerScript --broadcast --etherscan-api-key $ETHERSCAN_KEY --verify --with-gas-price 30000000000
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract CreateTestVault1Leafs is Script, MerkleTreeHelper {
    uint256 public privateKey;

    // {
    //   "Drones": {
    //     "drone-0": "0xea7ef93FC9cd6b81E1F6639F778cf54133E38EAA"
    //   },
    //   "contractAddresses": {
    //     "AccountantWithRateProviders": "0xEb16B2B5B2d0cdAcd370003BF1b4167e33aC9408",
    //     "BoringOnChainQueue": "0xFAbC727173bC80EDd021C064a7DF783Ed491e1b6",
    //     "BoringVault": "0x4dBAd8E2e62CAF522081b769e04AbCA560FFA137",
    //     "Lens": "0x18131744903bD787053bcb8A7AC8360817d65701",
    //     "ManagerWithMerkleVerification": "0x01d08F4D4C00DF23AC2B56301ef06C889B993a35",
    //     "Pauser": "0x2beEbc06f2758e9124cCADbC9F49595aF3E01fFD",
    //     "QueueSolver": "0xDAc2eB3D07272Ac169BdbfF0a5394E2136918a8A",
    //     "RolesAuthority": "0xcd5E9EBC1E35f20Af809E9668810c55cCc15b28E",
    //     "TellerWithLayerZero": "0xc4E16Ab37dD34D824C7f7c76AA25127159aeA662",
    //     "Timelock": "0xf7e8B778Df540484BfcD42f917C022B7AFC51A46"
    //   }
    // }

    address public rawDataDecoderAndSanitizerHyperevm = 0x0Ac1819A5EA6cAf05306b8955bC1a1680fA7B63A;

    RolesAuthority internal rolesAuthority = RolesAuthority(0xcd5E9EBC1E35f20Af809E9668810c55cCc15b28E);
    BoringVault internal boringVault = BoringVault(payable(0x4dBAd8E2e62CAF522081b769e04AbCA560FFA137));
    LayerZeroTeller internal teller = LayerZeroTeller(0xc4E16Ab37dD34D824C7f7c76AA25127159aeA662);
    ManagerWithMerkleVerification internal manager =
        ManagerWithMerkleVerification(0x01d08F4D4C00DF23AC2B56301ef06C889B993a35);
    AccountantWithRateProviders internal accountant =
        AccountantWithRateProviders(0xEb16B2B5B2d0cdAcd370003BF1b4167e33aC9408);
    BoringOnChainQueue internal boringOnChainQueue = BoringOnChainQueue(0xFAbC727173bC80EDd021C064a7DF783Ed491e1b6);
    BoringSolver internal boringSolver = BoringSolver(0xDAc2eB3D07272Ac169BdbfF0a5394E2136918a8A);

    address agent = 0xF171cAf19B2a55B015a68D80C337a16216775509;

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant MINTER_ROLE = 2;
    uint8 public constant BURNER_ROLE = 3;
    uint8 public constant MANAGER_INTERNAL_ROLE = 4;
    uint8 public constant PAUSER_ROLE = 5;
    uint8 public constant SOLVER_ROLE = 12;
    uint8 public constant OWNER_ROLE = 8;
    uint8 public constant MULTISIG_ROLE = 9;
    uint8 public constant STRATEGIST_MULTISIG_ROLE = 10;
    uint8 public constant STRATEGIST_ROLE = 7;
    uint8 public constant UPDATE_EXCHANGE_RATE_ROLE = 11;
    uint8 public constant GENERIC_PAUSER_ROLE = 14;
    uint8 public constant GENERIC_UNPAUSER_ROLE = 15;
    uint8 public constant PAUSE_ALL_ROLE = 16;
    uint8 public constant UNPAUSE_ALL_ROLE = 17;
    uint8 public constant SENDER_PAUSER_ROLE = 18;
    uint8 public constant SENDER_UNPAUSER_ROLE = 19;
    uint8 public constant CAN_SOLVE_ROLE = 31;
    uint8 public constant ONLY_QUEUE_ROLE = 32;
    uint8 public constant SOLVER_ORIGIN_ROLE = 33;

    function setUp() external {
        privateKey = vm.envUint("BORING_DEVELOPER");
        vm.createSelectFork("hyperevm");
        setSourceChainName("hyperevm");

        setAddress(true, hyperevm, "boringVault", address(boringVault));
        setAddress(true, hyperevm, "managerAddress", address(manager));
        setAddress(true, hyperevm, "manager", address(manager));
        setAddress(true, hyperevm, "accountantAddress", address(accountant));
        setAddress(true, hyperevm, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizerHyperevm);
    }

    function run() public {
        ManageLeaf[] memory leafs = new ManageLeaf[](64);
        _addLeafs(leafs);
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        string memory filePath = "./leafs/Hyperevm/TestVault1HyperevmLeafs.json";
        _generateLeafs(filePath, leafs, manageTree[manageTree.length - 1][0], manageTree);

        vm.startBroadcast(privateKey);
        manager.setManageRoot(agent, manageTree[manageTree.length - 1][0]);
        manager.setManageRoot(0xa86b3Bf249478488B4304B50726c7D4689aD6320, manageTree[manageTree.length - 1][0]);
        manager.setManageRoot(getAddress(sourceChain, "managerAddress"), manageTree[manageTree.length - 1][0]);
        manager.setManageRoot(0x0307AD25281C99F22A8F3Af9e272fE3968810239, manageTree[manageTree.length - 1][0]);
        vm.stopBroadcast();
    }

    function _addLeafs(ManageLeaf[] memory leafs) internal {
        ERC20[] memory feeAssets = new ERC20[](1);
        feeAssets[0] = getERC20(sourceChain, "USDT0");
        _addLeafsForFeeClaiming(leafs, getAddress(sourceChain, "accountantAddress"), feeAssets, false);

        _addUsdt0HlInteractionLeafs(leafs);
        _addCoreWriterLeaves(leafs);
    }
}
