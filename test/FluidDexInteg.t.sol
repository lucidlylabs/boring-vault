// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test, stdStorage, StdStorage, stdError, console, Vm} from "@forge-std/Test.sol";
import {BoringVault, Auth} from "src/base/BoringVault.sol";
import {LayerZeroTeller} from "src/base/Roles/CrossChain/Bridges/LayerZero/LayerZeroTeller.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {
    ChainlinkCCIPTeller,
    CrossChainTellerWithGenericBridge
} from "src/base/Roles/CrossChain/Bridges/CCIP/ChainlinkCCIPTeller.sol";
import {Deployer} from "src/helper/Deployer.sol";
import {Pauser} from "src/base/Roles/Pauser.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {MockLayerZeroEndPoint} from "src/helper/MockLayerZeroEndPoint.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {BoringOnChainQueue} from "src/base/Roles/BoringQueue/BoringOnChainQueue.sol";
import {BoringSolver} from "src/base/Roles/BoringQueue/BoringSolver.sol";
import {GenericRateProvider} from "src/helper/GenericRateProvider.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {AddressToBytes32Lib} from "src/helper/AddressToBytes32Lib.sol";
import {
    EtherFiLiquidDecoderAndSanitizer,
    UniswapV3DecoderAndSanitizer
} from "src/base/DecodersAndSanitizers/EtherFiLiquidDecoderAndSanitizer.sol";
import {FluidDexDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/FluidDexDecoderAndSanitizer.sol";
import {DecoderCustomTypes} from "src/interfaces/DecoderCustomTypes.sol";

// struct ManageLeaf {
//     address target;
//     bool canSendValue;
//     string signature;
//     address[] argumentAddresses;
//     string description;
//     address decoderAndSanitizer;
// }

contract FluidIntegTest is Test, MerkleTreeHelper {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;
    using AddressToBytes32Lib for address;

    ERC20 public USDC;
    ERC20 public USDT;
    ERC20 public WBTC;
    ERC20 public cbBTC;
    address public owner;
    address user01 = makeAddr("user01");
    address user02 = makeAddr("user02");
    RolesAuthority internal rolesAuthority = RolesAuthority(0xf7F3ace7f6cA2Cb1E7ccbE3Bf2Da13D001D36fdF);
    BoringVault internal boringVault = BoringVault(payable(0x279CAD277447965AF3d24a78197aad1B02a2c589));
    LayerZeroTeller internal teller = LayerZeroTeller(0xaefc11908fF97c335D16bdf9F2Bf720817423825);
    ManagerWithMerkleVerification internal manager =
        ManagerWithMerkleVerification(0x9B3e565ffC70c4b72516BC2dbec4b3c790940CE8);
    AccountantWithRateProviders internal accountant =
        AccountantWithRateProviders(0x03D9a9cE13D16C7cFCE564f41bd7E85E5cde8Da6);
    BoringOnChainQueue internal queue = BoringOnChainQueue(0xF632c10b19f2a0451cD4A653fC9ca0c15eA1040b);
    BoringSolver internal solver = BoringSolver(0x1d82e9bCc8F325caBBca6E6A3B287fE586536805);
    Deployer internal deployer = Deployer(0x771263e3Bc6aCDa5aE388A3F8A0c2dd7A17275FC);
    Pauser internal pauser = Pauser(0x31b9236A58f6EF7e0431811DAbBa8C706AFB0F2D);
    address public rawDataDecoderAndSanitizer;
    address public uniswapV3NonFungiblePositionManager;

    /// roles
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

    struct DepositAsset {
        ERC20 asset;
        bool isPeggedToBase;
        address rateProvider;
        string genericRateProviderName;
        address target;
        bytes4 selector;
        bytes32[8] params;
    }

    struct AddressOrName {
        address address_;
        string name;
    }

    struct WithdrawAsset {
        AddressOrName addressOrName;
        uint16 maxDiscount;
        uint16 minDiscount;
        uint24 minimumSecondsToDeadline;
        uint96 minimumShares;
        uint24 secondsToMaturity;
    }

    DepositAsset[] public depositAssets;
    WithdrawAsset[] public withdrawAssets;

    function setUp() external {
        setSourceChainName("mainnet");
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 24003640;

        _startFork(rpcKey, blockNumber);
        
        vm.createSelectFork(sourceChain);
        owner = 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5;
        USDC = getERC20(sourceChain, "USDC");
        USDT= getERC20(sourceChain, "USDT");
        WBTC = getERC20(sourceChain, "WBTC");
        cbBTC = getERC20(sourceChain, "cbBTC");

        rawDataDecoderAndSanitizer = address(new FluidDexFullDecoderAndSanitizer());

        setAddress(false, sourceChain, "boringVault", address(boringVault));
        setAddress(false, sourceChain, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizer);
        setAddress(false, sourceChain, "manager", address(manager));
        setAddress(false, sourceChain, "managerAddress", address(manager));
        setAddress(false, sourceChain, "accountantAddress", address(accountant));
    }

    // Fluid smart collat Integration
    function test__FluidSmartCollatInteg() public {
        // give roles

        vm.startPrank(rolesAuthority.owner());
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE, address(manager), manager.manageVaultWithMerkleVerification.selector, true
        );
        rolesAuthority.setUserRole(address(this), STRATEGIST_ROLE, true);
        vm.stopPrank();

        deal(getAddress(sourceChain, "WBTC"), address(boringVault), 1_00e18);
        deal(getAddress(sourceChain, "cbBTC"), address(boringVault), 1_00e18);

        ERC20[] memory supplyTokens = new ERC20[](2);
        supplyTokens[0] = getERC20(sourceChain, "WBTC");
        supplyTokens[1] = getERC20(sourceChain, "cbBTC");

        ERC20[] memory borrowTokens = new ERC20[](1);
        borrowTokens[0] = getERC20(sourceChain, "USDC");

        uint256 dexType = 2000;

        //3 approvals, 1 leaf for `operate()`, 1 leaf for `operatePerfect()`
        ManageLeaf[] memory leafs = new ManageLeaf[](32);
        _addFluidDexLeafs(
            leafs, getAddress(sourceChain, "wBTC-cbBTCDex-USDC"), dexType, supplyTokens, borrowTokens, false
        );

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        
        vm.prank(manager.owner());
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);

        for (uint256 i = 0; i < 32; i++) {
            console.log(leafs[i].description);
        }

        ManageLeaf[] memory manageLeafs = new ManageLeaf[](4);
        manageLeafs[0] = leafs[0]; //approval supply
        manageLeafs[1] = leafs[1]; //approval borrow0
        manageLeafs[2] = leafs[2]; //approval borrow1
        manageLeafs[3] = leafs[3]; //operate() deposit and borrow params
        // manageLeafs[4] = leafs[3]; //operate() borrow params
        // manageLeafs[5] = leafs[3]; //operate() payback params

        
        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        address[] memory targets = new address[](4);
        targets[0] = getAddress(sourceChain, "WBTC");
        targets[1] = getAddress(sourceChain, "cbBTC");
        targets[2] = getAddress(sourceChain, "USDC");
        targets[3] = getAddress(sourceChain, "wBTC-cbBTCDex-USDC");
        // targets[4] = getAddress(sourceChain, "wBTC-cbBTCDex-USDC");
        // targets[5] = getAddress(sourceChain, "wBTC-cbBTCDex-USDC");


        bytes[] memory targetData = new bytes[](4);
        targetData[0] =
            abi.encodeWithSignature("approve(address,uint256)", getAddress(sourceChain, "wBTC-cbBTCDex-USDC"), 1000e18);
        targetData[1] =
            abi.encodeWithSignature("approve(address,uint256)", getAddress(sourceChain, "wBTC-cbBTCDex-USDC"), 1000e18);
        targetData[2] =
            abi.encodeWithSignature("approve(address,uint256)", getAddress(sourceChain, "wBTC-cbBTCDex-USDC"), 1000e18);
        //deposit and borrow in 1 transaction
        targetData[3] = abi.encodeWithSignature(
            "operate(uint256,int256,int256,int256,int256,address)",
            0,
            10e8, // supply token0
            10e8, // suply token1
            10,
            100000e6, // debt token to
            getAddress(sourceChain, "boringVault")
        );
        // //borrow
        // targetData[4] = abi.encodeWithSignature(
        //     "operate(uint256,int256,int256,int256,int256,address)",
        //     nftId,
        //     0,
        //     0,
        //     0,
        //     1e6,
        //     getAddress(sourceChain, "boringVault")
        // );
        // //payback
        // targetData[5] = abi.encodeWithSignature(
        //     "operate(uint256,int256,int256,int256,int256,address)",
        //     nftId,
        //     0,
        //     0,
        //     0,
        //     -1e5,
        //     getAddress(sourceChain, "boringVault")
        // );
        uint256[] memory values = new uint256[](4);
        
        address[] memory decodersAndSanitizers = new address[](4);
        decodersAndSanitizers[0] = rawDataDecoderAndSanitizer;
        decodersAndSanitizers[1] = rawDataDecoderAndSanitizer;
        decodersAndSanitizers[2] = rawDataDecoderAndSanitizer;
        decodersAndSanitizers[3] = rawDataDecoderAndSanitizer;

        uint256 cachedUSDC = USDC.balanceOf(getAddress(sourceChain, "boringVault"));
        uint256 cachedWBTC = WBTC.balanceOf(getAddress(sourceChain, "boringVault"));
        uint256 cachedcbBTC = cbBTC.balanceOf(getAddress(sourceChain, "boringVault"));



        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);


        console.log("Cached balance of USDC",cachedUSDC);
        console.log("Cached balance of WBTC",cachedWBTC);
        console.log("Cached balance of cbBTC",cachedcbBTC);

        console.log("Balance of USDC",USDC.balanceOf(getAddress(sourceChain, "boringVault")));
        console.log("Balance of WBTC",WBTC.balanceOf(getAddress(sourceChain, "boringVault")));
        console.log("Balance of cbBTC",cbBTC.balanceOf(getAddress(sourceChain, "boringVault")));
    }

    // Fluid smart debt Integration
    function test__FluidSmartDebtInteg() public {
        // give roles

        vm.startPrank(rolesAuthority.owner());
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE, address(manager), manager.manageVaultWithMerkleVerification.selector, true
        );
        rolesAuthority.setUserRole(address(this), STRATEGIST_ROLE, true);
        vm.stopPrank();

        deal(getAddress(sourceChain, "WBTC"), address(boringVault), 1_00e18);
        // deal(getAddress(sourceChain, "cbBTC"), address(boringVault), 1_00e18);

        ERC20[] memory supplyTokens = new ERC20[](1);
        supplyTokens[0] = getERC20(sourceChain, "WBTC");

        ERC20[] memory borrowTokens = new ERC20[](2);
        borrowTokens[0] = getERC20(sourceChain, "USDC");
        borrowTokens[1] = getERC20(sourceChain, "USDT");

        uint256 dexType = 3000; //T3 VAULT

        //3 approvals, 1 leaf for `operate()`, 1 leaf for `operatePerfect()`
        ManageLeaf[] memory leafs = new ManageLeaf[](32);
        _addFluidDexLeafs(
            leafs, getAddress(sourceChain, "wBTC-DexUSDC-USDT"), dexType, supplyTokens, borrowTokens, false
        );

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        
        vm.prank(manager.owner());
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);

        for (uint256 i = 0; i < 32; i++) {
            console.log(leafs[i].description);
        }

        ManageLeaf[] memory manageLeafs = new ManageLeaf[](5);
        manageLeafs[0] = leafs[0]; //approval supply
        manageLeafs[1] = leafs[1]; //approval borrow0
        manageLeafs[2] = leafs[2]; //approval borrow1
        manageLeafs[3] = leafs[3]; //operate() deposit and borrow params
        manageLeafs[4] = leafs[3]; //operate() borrow params
        // manageLeafs[5] = leafs[3]; //operate() payback params

        
        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        address[] memory targets = new address[](5);
        targets[0] = getAddress(sourceChain, "WBTC");
        targets[1] = getAddress(sourceChain, "USDC");
        targets[2] = getAddress(sourceChain, "USDT");
        targets[3] = getAddress(sourceChain, "wBTC-DexUSDC-USDT");
        targets[4] = getAddress(sourceChain, "wBTC-DexUSDC-USDT");
        // targets[4] = getAddress(sourceChain, "wBTC-cbBTCDex-USDC");
        // targets[5] = getAddress(sourceChain, "wBTC-cbBTCDex-USDC");


        bytes[] memory targetData = new bytes[](5);
        targetData[0] =
            abi.encodeWithSignature("approve(address,uint256)", getAddress(sourceChain, "wBTC-DexUSDC-USDT"), 1000e18);
        targetData[1] =
            abi.encodeWithSignature("approve(address,uint256)", getAddress(sourceChain, "wBTC-DexUSDC-USDT"), 1000e18);
        targetData[2] =
            abi.encodeWithSignature("approve(address,uint256)", getAddress(sourceChain, "wBTC-DexUSDC-USDT"), 1000e18);
        //deposit and borrow in 1 transaction
        targetData[3] = abi.encodeWithSignature(
            "operate(uint256,int256,int256,int256,int256,address)",
            0,
            10e8, // collat to supply
            100e6, // debt token 0 to borrow
            100e6, // debt token 1 to borrow
            type(int256).max, // positive for borrowing
            getAddress(sourceChain, "boringVault")
        );
        uint256 nftId = 9338;
        targetData[4] = abi.encodeWithSignature(
            "operate(uint256,int256,int256,int256,int256,address)",
            nftId,
            0,
            10e6,
            10e6,
            type(int256).max,
            getAddress(sourceChain, "boringVault")
        );
        // //borrow
        // targetData[4] = abi.encodeWithSignature(
        //     "operate(uint256,int256,int256,int256,int256,address)",
        //     nftId,
        //     0,
        //     0,
        //     0,
        //     1e6,
        //     getAddress(sourceChain, "boringVault")
        // );
        // //payback
        // targetData[5] = abi.encodeWithSignature(
        //     "operate(uint256,int256,int256,int256,int256,address)",
        //     nftId,
        //     0,
        //     0,
        //     0,
        //     -1e5,
        //     getAddress(sourceChain, "boringVault")
        // );
        uint256[] memory values = new uint256[](5);
        
        address[] memory decodersAndSanitizers = new address[](5);
        decodersAndSanitizers[0] = rawDataDecoderAndSanitizer;
        decodersAndSanitizers[1] = rawDataDecoderAndSanitizer;
        decodersAndSanitizers[2] = rawDataDecoderAndSanitizer;
        decodersAndSanitizers[3] = rawDataDecoderAndSanitizer;
        decodersAndSanitizers[4] = rawDataDecoderAndSanitizer;

        uint256 cachedUSDC = USDC.balanceOf(getAddress(sourceChain, "boringVault"));
        uint256 cachedWBTC = WBTC.balanceOf(getAddress(sourceChain, "boringVault"));
        uint256 cachedUSDT = USDT.balanceOf(getAddress(sourceChain, "boringVault"));



        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);


        console.log("Cached balance of USDC",cachedUSDC);
        console.log("Cached balance of WBTC",cachedWBTC);
        console.log("Cached balance of USDT",cachedUSDT);

        console.log("Balance of USDC",USDC.balanceOf(getAddress(sourceChain, "boringVault")));
        console.log("Balance of WBTC",WBTC.balanceOf(getAddress(sourceChain, "boringVault")));
        console.log("Balance of USDT",USDT.balanceOf(getAddress(sourceChain, "boringVault")));
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}

contract FluidDexFullDecoderAndSanitizer is FluidDexDecoderAndSanitizer {}
