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
import {MerkleTreeHelper, IMB} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {BalancerVault} from "src/interfaces/BalancerVault.sol";

import {Test, console} from "forge-std/Test.sol";
import "forge-std/StdJson.sol";

contract CreateMorphoLoopPosition is Test, MerkleTreeHelper {
    address public rawDataDecoderAndSanitizerEthereum = 0xedbB1308b8E213d7C76F65Ca11cF38136b8a8a83;
    address public rawDataDecoderAndSanitizerBase01 = 0x53F0b212d28320DD0aB504AbD6871941EFf5AD45;
    address public rawDataDecoderAndSanitizerArbitrum01 = 0x53F0b212d28320DD0aB504AbD6871941EFf5AD45;
    RolesAuthority internal rolesAuthority = RolesAuthority(0xf7F3ace7f6cA2Cb1E7ccbE3Bf2Da13D001D36fdF);
    BoringVault internal boringVault = BoringVault(payable(0x279CAD277447965AF3d24a78197aad1B02a2c589));
    LayerZeroTeller internal teller = LayerZeroTeller(0xaefc11908fF97c335D16bdf9F2Bf720817423825);
    ManagerWithMerkleVerification internal manager =
        ManagerWithMerkleVerification(0x9B3e565ffC70c4b72516BC2dbec4b3c790940CE8);
    AccountantWithRateProviders internal accountant =
        AccountantWithRateProviders(0x03D9a9cE13D16C7cFCE564f41bd7E85E5cde8Da6);
    BoringOnChainQueue internal queue = BoringOnChainQueue(0xF632c10b19f2a0451cD4A653fC9ca0c15eA1040b);
    BoringSolver internal solver = BoringSolver(0x1d82e9bCc8F325caBBca6E6A3B287fE586536805);

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
        vm.createSelectFork("base");
        setSourceChainName("base");

        setAddress(true, base, "boringVault", address(boringVault));
        setAddress(true, base, "managerAddress", address(manager));
        setAddress(true, base, "accountantAddress", address(accountant));
        setAddress(true, base, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizerEthereum);
    }

    function test__BridgeUsingCcip() external {
        address agent = 0xF171cAf19B2a55B015a68D80C337a16216775509;
        ManageLeaf[] memory leafs = new ManageLeaf[](1024);

        {
            ERC20[] memory feeAssets = new ERC20[](3);
            feeAssets[0] = getERC20(sourceChain, "USDC");
            feeAssets[1] = getERC20(sourceChain, "USDT");
            feeAssets[2] = getERC20(sourceChain, "USDS");
            _addLeafsForFeeClaiming(leafs, getAddress(sourceChain, "accountantAddress"), feeAssets, false);

            ERC20[] memory bridgeAssets = new ERC20[](2);
            bridgeAssets[0] = getERC20(sourceChain, "USDC");
            bridgeAssets[1] = getERC20(sourceChain, "USDT");
            ERC20[] memory feeTokens = new ERC20[](2);
            feeTokens[0] = getERC20(sourceChain, "WETH");
            feeTokens[1] = getERC20(sourceChain, "GHO");

            _addCcipBridgeLeafs(leafs, ccipBaseChainSelector, bridgeAssets, feeTokens);
            _addCcipBridgeLeafs(leafs, ccipArbitrumChainSelector, bridgeAssets, feeTokens);
            _addCcipBridgeLeafs(leafs, ccipBscChainSelector, bridgeAssets, feeTokens);

            _addInfiniV1Leafs(leafs, getAddress(sourceChain, "USDC"));

            _addBalancerFlashloanLeafs(leafs, getAddress(sourceChain, "USDC"));
            _addBalancerFlashloanLeafs(leafs, getAddress(sourceChain, "USDT"));
            _addBalancerFlashloanLeafs(leafs, getAddress(sourceChain, "DAI"));
            _addBalancerFlashloanLeafs(leafs, getAddress(sourceChain, "USDS"));
            _addBalancerFlashloanLeafs(leafs, getAddress(sourceChain, "WETH"));

            _addMorphoBlueSupplyLeafs(leafs, getBytes32(sourceChain, "syrupUSDC_USDC_915"));
            _addMorphoBlueSupplyLeafs(leafs, getBytes32(sourceChain, "PT-syrupUSDC-28AUG2025_USDC_915"));
            _addMorphoBlueSupplyLeafs(leafs, getBytes32(sourceChain, "PT-iUSD-4SEP2025_USDC_915"));
            _addMorphoBlueCollateralLeafs(leafs, getBytes32(sourceChain, "syrupUSDC_USDC_915"));
            _addMorphoBlueCollateralLeafs(leafs, getBytes32(sourceChain, "PT-syrupUSDC-28AUG2025_USDC_915"));
            _addMorphoBlueCollateralLeafs(leafs, getBytes32(sourceChain, "PT-iUSD-4SEP2025_USDC_915"));

            _addPendleMarketLeafs(leafs, getAddress(sourceChain, "pendle_iUSD_09_04_2025"), false);
            _addPendleMarketLeafs(leafs, getAddress(sourceChain, "pendle_syrupUSDC_08_28_2025"), false);

            // 1inch assets;
            address[] memory oneInchAssets = new address[](10);
            oneInchAssets[0] = getAddress(sourceChain, "USDC");
            oneInchAssets[1] = getAddress(sourceChain, "SUSDE");
            oneInchAssets[2] = getAddress(sourceChain, "USDS");
            oneInchAssets[3] = getAddress(sourceChain, "USDT");
            oneInchAssets[4] = getAddress(sourceChain, "USDE");
            oneInchAssets[5] = getAddress(sourceChain, "lvlUSD");
            oneInchAssets[6] = getAddress(sourceChain, "RLP");
            oneInchAssets[7] = getAddress(sourceChain, "USR");
            oneInchAssets[8] = getAddress(sourceChain, "wstUSR");
            oneInchAssets[9] = getAddress(sourceChain, "cUSDO");
            SwapKind[] memory kind = new SwapKind[](10);
            kind[0] = SwapKind.BuyAndSell;
            kind[1] = SwapKind.BuyAndSell;
            kind[2] = SwapKind.BuyAndSell;
            kind[3] = SwapKind.BuyAndSell;
            kind[4] = SwapKind.BuyAndSell;
            kind[5] = SwapKind.BuyAndSell;
            kind[6] = SwapKind.BuyAndSell;
            kind[7] = SwapKind.BuyAndSell;
            kind[8] = SwapKind.BuyAndSell;
            kind[9] = SwapKind.BuyAndSell;
            _addLeafsFor1InchGeneralSwapping(leafs, oneInchAssets, kind);
            _addOdosSwapLeafs(leafs, oneInchAssets, kind);

            ERC20[] memory supplyAssets = new ERC20[](1);
            supplyAssets[0] = getERC20(sourceChain, "SUSDE");
            ERC20[] memory borrowAssets = new ERC20[](2);
            borrowAssets[0] = getERC20(sourceChain, "USDC");
            borrowAssets[1] = getERC20(sourceChain, "USDT");
            _addAaveV3Leafs(leafs, supplyAssets, borrowAssets);

            _addERC4626Leafs(leafs, ERC4626(getAddress(sourceChain, "SUSDE")));
        }

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        vm.startPrank(manager.owner());
        manager.setManageRoot(agent, manageTree[manageTree.length - 1][0]);
        manager.setManageRoot(getAddress(sourceChain, "managerAddress"), manageTree[manageTree.length - 1][0]);
        vm.stopPrank();

        // 1. approve pendle router to spend USDC
        // 2. mint SY-iUSD
        // 3. swap SY for PT
        // 4. approve morpho to spend PT-iUSD
        // 5. deposit PT-iUSD on morpho
        // 6. borrow USDC

        uint256 flashloanAmount = 100000e6;

        ManageLeaf[] memory manageLeafs = new ManageLeaf[](3);

        bytes memory userData;
        {
            ManageLeaf[] memory flashloanLeafs = new ManageLeaf[6];

            // approve pendle router to spend usdc
            flashloanLeafs[0] = ManageLeaf(
                getAddress(sourceChain, "USDC"),
                false,
                "approve(address,uint256)",
                new address[](1),
                "",
                getAddress(sourceChain, "rawDataDecoderAndSanitizer")
            );
            flashloanLeafs[0].argumentAddresses[0] = getAddress(sourceChain, "pendleRouter");

            // mint SY-iUSD using USDC
            flashloanLeafs[1] = ManageLeaf(
                getAddress(sourceChain, "pendleRouter"),
                false,
                "mintSyFromToken(address,address,uint256,(address,uint256,address,address,(uint8,address,bytes,bool)))",
                new address[](6),
                "",
                getAddress(sourceChain, "rawDataDecoderAndSanitizer")
            );
            leafs[1].argumentAddresses[0] = getAddress(sourceChain, "boringVault");
            leafs[1].argumentAddresses[1] = getAddress(sourceChain, "SY_iUSD_9_04_202");
            leafs[1].argumentAddresses[2] = getAddress(sourceChain, "USDC");
            leafs[1].argumentAddresses[3] = getAddress(sourceChain, "USDC");
            leafs[1].argumentAddresses[4] = address(0);
            leafs[1].argumentAddresses[5] = address(0);

            // swap SY for PT
            flashloanLeafs[2] = ManageLeaf(
                getAddress(sourceChain, "pendleRouter"),
                false,
                "swapExactSyForPt(address,address,uint256,uint256,(uint256,uint256,uint256,uint256,uint256),(address,uint256,((uint256,uint256,uint256,uint8,address,address,address,address,uint256,uint256,uint256,bytes),bytes,uint256)[],((uint256,uint256,uint256,uint8,address,address,address,address,uint256,uint256,uint256,bytes),bytes,uint256)[],bytes))",
                new address[](2),
                "",
                getAddress(sourceChain, "rawDataDecoderAndSanitizer")
            );
            flashloanLeafs[2].argumentAddresses[0] = getAddress(sourceChain, "boringVault");
            flashloanLeafs[2].argumentAddresses[1] = getAddress(sourceChain, "LP_iUSD_9_04_2025");

            // approve morpho to spend PT-iUSD
            flashloanLeafs[3] = ManageLeaf(
                getAddress(sourceChain, "PT_iUSD_9_04_2025"),
                false,
                "approve(address,uint256)",
                new address[](1),
                "",
                getAddress(sourceChain, "rawDataDecoderAndSanitizer")
            );
            flashloanLeafs[0].argumentAddresses[0] = getAddress(sourceChain, "pendleRouter");

            IMB.MarketParams memory marketParams = IMB(getAddress(sourceChain, "morphoBlue")).idToMarketParams(
                getBytes32(sourceChain, "PT-iUSD-4SEP2025_USDC_915")
            );

            // supply PT-iUSD collateral on morpho
            flashloanLeafs[4] = ManageLeaf(
                getAddress(sourceChain, "morphoBlue"),
                false,
                "supplyCollateral((address,address,address,address,uint256),uint256,address,bytes)",
                new address[](5),
                "",
                getAddress(sourceChain, "rawDataDecoderAndSanitizer")
            );
            flashloanLeafs[4].argumentAddresses[0] = marketParams.loanToken;
            flashloanLeafs[4].argumentAddresses[1] = marketParams.collateralToken;
            flashloanLeafs[4].argumentAddresses[2] = marketParams.oracle;
            flashloanLeafs[4].argumentAddresses[3] = marketParams.irm;
            flashloanLeafs[4].argumentAddresses[4] = getAddress(sourceChain, "boringVault");

            flashloanLeafs[5] = ManageLeaf(
                getAddress(sourceChain, "morphoBlue"),
                false,
                "borrow((address,address,address,address,uint256),uint256,uint256,address,address)",
                new address[](6),
                "",
                getAddress(sourceChain, "rawDataDecoderAndSanitizer")
            );
            flashloanLeafs[5].argumentAddresses[0] = marketParams.loanToken;
            flashloanLeafs[5].argumentAddresses[1] = marketParams.collateralToken;
            flashloanLeafs[5].argumentAddresses[2] = marketParams.oracle;
            flashloanLeafs[5].argumentAddresses[3] = marketParams.irm;
            flashloanLeafs[5].argumentAddresses[4] = getAddress(sourceChain, "boringVault");
            flashloanLeafs[5].argumentAddresses[5] = getAddress(sourceChain, "boringVault");

            address[] memory targets = new address[](6);
            targets[0] = getAddress(sourceChain, "USDC");
            targets[1] = getAddress(sourceChain, "pendleRouter");
            targets[2] = getAddress(sourceChain, "pendleRouter");
            targets[3] = getAddress(sourceChain, "PT_iUSD_9_04_2025");
            targets[4] = getAddress(sourceChain, "morphoBlue");
            targets[5] = getAddress(sourceChain, "morphoBlue");

            bytes[] memory targetData = new bytes[](6);

            targetData[0] = abi.encodeWithSignature(
                "approve(address,uint256)", getAddress(sourceChain, "pendleRouter"), type(uint256).max
            );
        }

        vm.prank(agent);
        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);
    }
}
