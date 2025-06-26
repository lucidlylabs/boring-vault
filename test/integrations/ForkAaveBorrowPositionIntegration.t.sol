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
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {BalancerVault} from "src/interfaces/BalancerVault.sol";

import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";

contract ForkAaveBorrowPositionIntegration is Test, MerkleTreeHelper {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    address public rawDataDecoderAndSanitizer;
    RolesAuthority internal rolesAuthority = RolesAuthority(0xf7F3ace7f6cA2Cb1E7ccbE3Bf2Da13D001D36fdF);
    BoringVault internal boringVault = BoringVault(payable(0x279CAD277447965AF3d24a78197aad1B02a2c589));
    LayerZeroTeller internal teller = LayerZeroTeller(0xaefc11908fF97c335D16bdf9F2Bf720817423825);
    ManagerWithMerkleVerification internal manager =
        ManagerWithMerkleVerification(0x9B3e565ffC70c4b72516BC2dbec4b3c790940CE8);
    AccountantWithRateProviders internal accountant =
        AccountantWithRateProviders(0x03D9a9cE13D16C7cFCE564f41bd7E85E5cde8Da6);
    BoringOnChainQueue internal queue = BoringOnChainQueue(0xF632c10b19f2a0451cD4A653fC9ca0c15eA1040b);
    BoringSolver internal solver = BoringSolver(0x1d82e9bCc8F325caBBca6E6A3B287fE586536805);

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

    function setUp() external {
        setSourceChainName("mainnet");
        vm.createSelectFork(sourceChain);

        rawDataDecoderAndSanitizer =
            address(new SyUsdDecoderAndSanitizer(getAddress(sourceChain, "uniswapV3NonFungiblePositionManager")));

        setAddress(false, sourceChain, "boringVault", address(boringVault));
        setAddress(false, sourceChain, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizer);
        setAddress(false, sourceChain, "manager", address(manager));
        setAddress(false, sourceChain, "managerAddress", address(manager));
        setAddress(false, sourceChain, "accountantAddress", address(accountant));

        vm.startPrank(rolesAuthority.owner());
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE, address(manager), manager.manageVaultWithMerkleVerification.selector, true
        );
        rolesAuthority.setUserRole(address(this), STRATEGIST_ROLE, true);
        vm.stopPrank();
    }

    function testAaveFlashBorrow() external {
        uint256 flashloanAmount = 100_000 * 1e6; // 100k USDC
        deal(getAddress(sourceChain, "SUSDE"), address(boringVault), 100_000e18);

        // create ManageLeaf array for all operations
        ManageLeaf[] memory leafs = new ManageLeaf[](16);

        // add AaveV3 Leafs
        ERC20[] memory supplyAssets = new ERC20[](1);
        supplyAssets[0] = getERC20(sourceChain, "SUSDE");
        ERC20[] memory borrowAssets = new ERC20[](1);
        borrowAssets[0] = getERC20(sourceChain, "USDC");
        _addBalancerFlashloanLeafs(leafs, getAddress(sourceChain, "USDC")); // 1 leaf
        _addAaveV3Leafs(leafs, supplyAssets, borrowAssets); //  10 leafs
        _addCurveLeafs(
            leafs, getAddress(sourceChain, "Usde_Usdc_Curve_Pool"), 2, getAddress(sourceChain, "Usde_Usdc_Curve_Gauge")
        ); // 8 leafs
        _addERC4626Leafs(leafs, ERC4626(getAddress(sourceChain, "SUSDE"))); // 5 leafs

        // // add flashloan leaf at the end
        // leafs[15] = ManageLeaf(
        //     getAddress(sourceChain, "balancerVault"),
        //     false,
        //     "flashLoan(address,address[],uint256[],bytes)",
        //     new address[](2),
        //     "",
        //     getAddress(sourceChain, "rawDataDecoderAndSanitizer")
        // );
        // leafs[15].argumentAddresses[0] = address(manager);
        // leafs[15].argumentAddresses[1] = getAddress(sourceChain, "USDC");

        // // add usdc swapping leafs for swapping usdc to usde using curve
        // leafs[10] = ManageLeaf(
        //     getAddress(sourceChain, "USDC"),
        //     false,
        //     "approve(address,uint256)",
        //     new address[](1),
        //     "",
        //     rawDataDecoderAndSanitizer
        // );
        // leafs[10].argumentAddresses[0] = getAddress(sourceChain, "Usde_Usdc_Curve_Pool");

        // leafs[11] = ManageLeaf(
        //     getAddress(sourceChain, "Usde_Usdc_Curve_Pool"),
        //     false,
        //     "exchange(int128,int128,uint256,uint256)",
        //     new address[](0),
        //     "",
        //     getAddress(sourceChain, "rawDataDecoderAndSanitizer")
        // );
        // leafs[12] = ManageLeaf(
        //     getAddress(sourceChain, "USDE"),
        //     false,
        //     "approve(address,uint256)",
        //     new address[](1),
        //     "",
        //     rawDataDecoderAndSanitizer
        // );
        // leafs[12].argumentAddresses[0] = getAddress(sourceChain, "SUSDE");

        // leafs[13] = ManageLeaf(
        //     getAddress(sourceChain, "SUSDE"),
        //     false,
        //     "deposit(uint256,address)",
        //     new address[](1),
        //     "",
        //     rawDataDecoderAndSanitizer
        // );
        // leafs[13].argumentAddresses[0] = getAddress(sourceChain, "boringVault");

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        vm.prank(manager.owner());
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);

        vm.prank(manager.owner());
        manager.setManageRoot(address(manager), manageTree[manageTree.length - 1][0]);

        bytes memory userData;
        {
            ManageLeaf[] memory flashloanLeafs = new ManageLeaf[](7);

            // approve curve pool to spend USDC
            flashloanLeafs[0] = ManageLeaf(
                getAddress(sourceChain, "USDC"),
                false,
                "approve(address,uint256)",
                new address[](1),
                "",
                rawDataDecoderAndSanitizer
            );
            flashloanLeafs[0].argumentAddresses[0] = getAddress(sourceChain, "Usde_Usdc_Curve_Pool");

            // swap USDC for USDE on curve pool
            flashloanLeafs[1] = ManageLeaf(
                getAddress(sourceChain, "Usde_Usdc_Curve_Pool"),
                false,
                "exchange(int128,int128,uint256,uint256)",
                new address[](0),
                "",
                getAddress(sourceChain, "rawDataDecoderAndSanitizer")
            );

            // approve SUSDE to spend USDE
            flashloanLeafs[2] = ManageLeaf(
                getAddress(sourceChain, "USDE"),
                false,
                "approve(address,uint256)",
                new address[](1),
                "",
                rawDataDecoderAndSanitizer
            );
            flashloanLeafs[2].argumentAddresses[0] = getAddress(sourceChain, "SUSDE");

            // deposit USDE into SUSDE contract
            flashloanLeafs[3] = ManageLeaf(
                getAddress(sourceChain, "SUSDE"),
                false,
                "deposit(uint256,address)",
                new address[](1),
                "",
                rawDataDecoderAndSanitizer
            );
            flashloanLeafs[3].argumentAddresses[0] = getAddress(sourceChain, "boringVault");

            // approve aave to spend SUSDE
            flashloanLeafs[4] = ManageLeaf(
                getAddress(sourceChain, "SUSDE"),
                false,
                "approve(address,uint256)",
                new address[](1),
                "",
                rawDataDecoderAndSanitizer
            );
            flashloanLeafs[4].argumentAddresses[0] = getAddress(sourceChain, "poolV3");

            flashloanLeafs[5] = leafs[3];
            // supply susde to aave
            flashloanLeafs[5] = ManageLeaf();

            flashloanLeafs[6] = leafs[4]; // borrow usdc from aave

            bytes32[][] memory flashloanManageProofs = _getProofsUsingTree(flashloanLeafs, manageTree);

            address[] memory targets = new address[](7);
            targets[0] = getAddress(sourceChain, "USDC"); // approve curve usde_usdc pool to spend usdc
            targets[1] = getAddress(sourceChain, "Usde_Usdc_Curve_Pool"); // swap usdc to usde
            targets[2] = getAddress(sourceChain, "USDE"); // approve susde contract to spend usde
            targets[3] = getAddress(sourceChain, "SUSDE"); // deposit usde into susde contract
            targets[4] = getAddress(sourceChain, "v3Pool"); // approve aave to spend susde
            targets[5] = getAddress(sourceChain, "v3Pool"); // supply susde from aave
            targets[6] = getAddress(sourceChain, "v3Pool"); // borrow usdc from aave

            bytes[] memory targetData = new bytes[](7);
            targetData[0] = abi.encodeWithSignature(
                "approve(address,uint256)", getAddress(sourceChain, "Usde_Usdc_Curve_Pool"), flashloanAmount
            );

            bytes memory exchangeCalldata = abi.encodeWithSelector(
                bytes4(keccak256("get_dy(int128,int128,uint256)")),
                int128(1), // usdc
                int128(0), // usde
                uint256(flashloanAmount)
            );
            (, bytes memory result) = getAddress(sourceChain, "Usde_Usdc_Curve_Pool").staticcall(exchangeCalldata);

            targetData[1] = abi.encodeWithSignature(
                "exchange(int128,int128,uint256,uint256)",
                int128(1),
                int128(0),
                flashloanAmount,
                abi.decode(result, (uint256))
            );

            targetData[2] = abi.encodeWithSignature(
                "approve(address,uint256)", getAddress(sourceChain, "SUSDE"), abi.decode(result, (uint256))
            );

            bytes memory previewDepositCalldata =
                abi.encodeWithSelector(bytes4(keccak256("previewDeposit(uint256)")), abi.decode(result, (uint256)));
            (, bytes memory previewDepositResult) = getAddress(sourceChain, "SUSDE").staticcall(previewDepositCalldata);
            targetData[3] = abi.encodeWithSignature(
                "deposit(uint256,address)", abi.decode(result, (uint256)), getAddress(sourceChain, "boringVault")
            );

            uint256 totalSusdeBalanceAfterFlashloan = 100_000e18 + abi.decode(previewDepositResult, (uint256));
            targetData[4] = abi.encodeWithSignature(
                "approve(address,uint256)", getAddress(sourceChain, "v3Pool"), totalSusdeBalanceAfterFlashloan
            );

            targetData[5] = abi.encodeWithSignature(
                "supply(address,uint256,address,uint16)",
                getAddress(sourceChain, "SUSDE"),
                totalSusdeBalanceAfterFlashloan,
                getAddress(sourceChain, "boringVault"),
                0
            );

            targetData[6] = abi.encodeWithSignature(
                "borrow(address,uint256,uint256,uint16,address)",
                getAddress(sourceChain, "USDC"),
                flashloanAmount,
                2,
                0,
                getAddress(sourceChain, "boringVault")
            );

            uint256[] memory values = new uint256[](7);
            address[] memory decodersAndSanitizers = new address[](7);
            for (uint256 i = 0; i < 7; i++) {
                decodersAndSanitizers[i] = getAddress(sourceChain, "rawDataDecoderAndSanitizer");
            }

            userData = abi.encode(flashloanManageProofs, decodersAndSanitizers, targets, targetData, values);
        }

        {
            address[] memory targets = new address[](1);
            targets[0] = getAddress(sourceChain, "manager");

            address[] memory tokensToBorrow = new address[](1);
            tokensToBorrow[0] = getAddress(sourceChain, "USDC");
            uint256[] memory amountsToBorrow = new uint256[](1);
            amountsToBorrow[0] = flashloanAmount;
            bytes[] memory targetData = new bytes[](1);
            targetData[0] = abi.encodeWithSelector(
                BalancerVault.flashLoan.selector, address(manager), tokensToBorrow, amountsToBorrow, userData
            );

            ManageLeaf[] memory manageLeafs = new ManageLeaf[](1);
            manageLeafs[0] = leafs[15];

            bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

            uint256[] memory values = new uint256[](1);
            address[] memory decodersAndSanitizers = new address[](1);
            decodersAndSanitizers[0] = getAddress(sourceChain, "rawDataDecoderAndSanitizer");

            vm.prank(manager.owner());
            manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);
        }
    }
}
