// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {BoringOnChainQueue} from "src/base/Roles/BoringQueue/BoringOnChainQueue.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {MorphoFlashLoanAdapter} from "src/base/Roles/MorphoFlashLoan/MorphoFlashLoanAdapter.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

contract CreateHedgedBtcMmVaultMerkleRootScript is Script, MerkleTreeHelper {
    using FixedPointMathLib for uint256;

    uint256 public privateKey;

    AccountantWithRateProviders public accountant =
        AccountantWithRateProviders(0x702E248Ce74bEFA7f4552d54e8E1cabeA7FB2a6c);
    BoringVault public boringVault = BoringVault(payable(0xbEA97618434D925B0F9EdAB63aDF4Ce46F373b51));
    BoringOnChainQueue public queue = BoringOnChainQueue(0x159145B1adE6b22A9D79e59021178970A38F89E7);
    ManagerWithMerkleVerification public manager =
        ManagerWithMerkleVerification(0xCED7B28a74A40D300f54f3e01DF0385238672451);
    address public rawDataDecoderAndSanitizer01 = 0x21Ec5d32FB4Ac17feBdC95ab979e2eF8E2C913Df;
    RolesAuthority public rolesAuthority = RolesAuthority(0x4E0A3F169380a4bD91d4A727d91eE2724d3c7B08);
    TellerWithMultiAssetSupport public teller = TellerWithMultiAssetSupport(0x6FbA48cd418dF5b8048Cd74c52890323bb0dB784);
    MorphoFlashLoanAdapter internal flashLoanAdapter =
        MorphoFlashLoanAdapter(0x2c8e905169298454226bC2A5eF13416E8B057737);

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 7;

    function setUp() external {
        privateKey = vm.envUint("DEPLOYER");
        vm.createSelectFork("base");
        setSourceChainName("base");

        setAddress(true, base, "boringVault", address(boringVault));
        setAddress(true, base, "managerAddress", address(manager));
        setAddress(true, base, "manager", address(manager));
        setAddress(true, base, "accountantAddress", address(accountant));
        setAddress(true, base, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizer01);
    }

    function run() external {
        ManageLeaf[] memory leafs = new ManageLeaf[](256);
        _addLeafs(leafs);
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        string memory filePath = "./leafs/Base/HedgedBtcMmStrategistLeafs.json";
        _generateLeafs(filePath, leafs, manageTree[manageTree.length - 1][0], manageTree);

        vm.startBroadcast(privateKey);
        manager.setManageRoot(0xACF7E58ef1033833b24E9B5D0556626d5Cc0535C, manageTree[manageTree.length - 1][0]);
        manager.setManageRoot(address(flashLoanAdapter), manageTree[manageTree.length - 1][0]);

        rolesAuthority.setUserRole(address(flashLoanAdapter), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(address(flashLoanAdapter), STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(0xACF7E58ef1033833b24E9B5D0556626d5Cc0535C, STRATEGIST_ROLE, true);
        vm.stopBroadcast();
    }

    function _addLeafs(ManageLeaf[] memory leafs) internal {
        // fee claiming
        ERC20[] memory feeAssets = new ERC20[](1);
        feeAssets[0] = getERC20(sourceChain, "cbBTC");
        _addLeafsForFeeClaiming(leafs, getAddress(sourceChain, "accountantAddress"), feeAssets, false);

        // fly.trade
        address[] memory swapAssets = new address[](2);
        swapAssets[0] = getAddress(sourceChain, "cbBTC");
        swapAssets[1] = getAddress(sourceChain, "WETH");
        SwapKind[] memory kind = new SwapKind[](2);
        kind[0] = SwapKind.BuyAndSell;
        kind[1] = SwapKind.BuyAndSell;
        _addMagpieSwapLeafs(leafs, swapAssets, kind);

        // aave v3 core
        ERC20[] memory supplyAssets = new ERC20[](1);
        supplyAssets[0] = getERC20(sourceChain, "cbBTC");
        ERC20[] memory borrowAssets = new ERC20[](1);
        borrowAssets[0] = getERC20(sourceChain, "WETH");
        _addAaveV3Leafs(leafs, supplyAssets, borrowAssets);

        // morpho blue flashLoan
        _addMorphoBlueFlashLoanLeafs(leafs, getAddress(sourceChain, "cbBTC"));
        _addMorphoBlueFlashLoanLeafs(leafs, getAddress(sourceChain, "WETH"));

        // aerodrome v3
        address[] memory token0 = new address[](1);
        token0[0] = getAddress(sourceChain, "WETH");
        address[] memory token1 = new address[](1);
        token1[0] = getAddress(sourceChain, "cbBTC");
        address[] memory gauges = new address[](1);
        gauges[0] = getAddress(sourceChain, "aerodrome_Weth_CbBtc_v3_0125_gauge");

        _addVelodromeV3Leafs(
            leafs, token0, token1, getAddress(sourceChain, "aerodromeNonFungiblePositionManager"), gauges
        );
    }
}
