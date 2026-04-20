  // SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BoringVault} from "src/base/BoringVault.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {ApyxUSDDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/ApyxUSDDecoderAndSanitizer.sol";
import {DecoderCustomTypes} from "src/interfaces/DecoderCustomTypes.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

import {Test, stdStorage, StdStorage, console} from "@forge-std/Test.sol";

contract ApyxStrategistIntegrationTest is Test, MerkleTreeHelper {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    // ----- Apyx-specific addresses (mainnet, on-chain verified). ---------------------
    address public constant APY_USD = 0x38EEb52F0771140d10c4E9A9a72349A329Fe8a6A;
    address public constant APX_USD = 0x98A878b1Cd98131B271883B390f68D2c90674665;
    address public constant CURVE_APXUSD_USDC_POOL = 0xE1B96555BbecA40E583BbB41a11C68Ca4706A414;
    address public constant PENDLE_APXUSD_MARKET = 0x50DCE085af29CABa28f7308beA57C4043757b491;
    bytes32 public constant MORPHO_APYUSD_USDC_MARKET_ID =
        0x9c28c8fa039a8df548a7f27adf062d751b0f2e9b9131931810535543adb23291;

    // ----- Test fixture ----------------------------------------------------------------
    ManagerWithMerkleVerification public manager;
    BoringVault public boringVault;
    address public rawDataDecoderAndSanitizer;
    RolesAuthority public rolesAuthority;

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 2;
    uint8 public constant MANAGER_INTERNAL_ROLE = 3;
    uint8 public constant ADMIN_ROLE = 4;
    uint8 public constant BORING_VAULT_ROLE = 5;
    uint8 public constant BALANCER_VAULT_ROLE = 6;

    function setUp() external {
        setSourceChainName("mainnet");
        _startFork("MAINNET_RPC_URL", 0);

        // Deploy a fresh apyxUSD-style architecture — mirrors what the Phase-1 deploy produces
        // but without going through the Veda Deployer (which rejects arbitrary senders).
        boringVault = new BoringVault(address(this), "Apyx Yield USD", "apyxUSD", 6);
        manager = new ManagerWithMerkleVerification(
            address(this), address(boringVault), getAddress(sourceChain, "vault")
        );
        rawDataDecoderAndSanitizer = address(new ApyxUSDDecoderAndSanitizer());

        // Register the architecture + Apyx addresses for the MerkleTreeHelper.
        setAddress(false, sourceChain, "boringVault", address(boringVault));
        setAddress(false, sourceChain, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizer);
        setAddress(false, sourceChain, "manager", address(manager));
        setAddress(false, sourceChain, "managerAddress", address(manager));
        setAddress(false, sourceChain, "accountantAddress", address(1));

        setAddress(false, sourceChain, "apyUSD", APY_USD);
        setAddress(false, sourceChain, "apxUSD", APX_USD);

        // Roles + capabilities.
        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        boringVault.setAuthority(rolesAuthority);
        manager.setAuthority(rolesAuthority);

        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, address(boringVault), bytes4(keccak256("manage(address,bytes,uint256)")), true
        );
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, address(boringVault), bytes4(keccak256("manage(address[],bytes[],uint256[])")), true
        );
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(manager),
            ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
            true
        );
        rolesAuthority.setRoleCapability(
            MANAGER_INTERNAL_ROLE,
            address(manager),
            ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
            true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(manager), ManagerWithMerkleVerification.setManageRoot.selector, true
        );
        rolesAuthority.setRoleCapability(
            BORING_VAULT_ROLE, address(manager), ManagerWithMerkleVerification.flashLoan.selector, true
        );
        rolesAuthority.setRoleCapability(
            BALANCER_VAULT_ROLE, address(manager), ManagerWithMerkleVerification.receiveFlashLoan.selector, true
        );

        rolesAuthority.setUserRole(address(this), STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(address(this), ADMIN_ROLE, true);
        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(address(manager), MANAGER_INTERNAL_ROLE, true);
        rolesAuthority.setUserRole(address(boringVault), BORING_VAULT_ROLE, true);
        rolesAuthority.setUserRole(getAddress(sourceChain, "vault"), BALANCER_VAULT_ROLE, true);
    }

    // ======================================================================================
    // Action 1: Mint apyUSD — ERC4626 deposit on the apyUSD wrapper over apxUSD.
    // ======================================================================================
    function testStrategistMintApyUSD() external {
        ERC4626 apyUSD = ERC4626(APY_USD);
        ERC20 apxUSD = ERC20(APX_USD);
        uint256 depositAmount = 1_000 * (10 ** apxUSD.decimals());
        deal(address(apxUSD), address(boringVault), depositAmount);

        ManageLeaf[] memory leafs = new ManageLeaf[](8);
        _addERC4626Leafs(leafs, apyUSD);
        bytes32[][] memory tree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), tree[tree.length - 1][0]);

        // leaf 0: approve(apxUSD, apyUSD). leaf 1: deposit(amount, boringVault).
        ManageLeaf[] memory used = new ManageLeaf[](2);
        used[0] = leafs[0];
        used[1] = leafs[1];
        bytes32[][] memory proofs = _getProofsUsingTree(used, tree);

        address[] memory targets = new address[](2);
        targets[0] = address(apxUSD);
        targets[1] = address(apyUSD);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", address(apyUSD), type(uint256).max);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", depositAmount, address(boringVault));

        address[] memory decoders = new address[](2);
        decoders[0] = rawDataDecoderAndSanitizer;
        decoders[1] = rawDataDecoderAndSanitizer;

        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, data, new uint256[](2));

        assertGt(apyUSD.balanceOf(address(boringVault)), 0, "apyUSD not minted to vault");
    }

    // ======================================================================================
    // Action 2: LP on apxUSD Pendle market — mintSyFromToken is the LP-entry gateway.
    // ======================================================================================
    function testStrategistPendleMintSy() external {
        ERC20 apxUSD = ERC20(APX_USD);
        address pendleRouter = getAddress(sourceChain, "pendleRouter");
        uint256 mintAmount = 1_000 * (10 ** apxUSD.decimals());
        deal(address(apxUSD), address(boringVault), mintAmount);

        bytes32[][] memory proofs;
        {
            ManageLeaf[] memory leafs = new ManageLeaf[](32);
            _addPendleMarketLeafs(leafs, PENDLE_APXUSD_MARKET, false);
            bytes32[][] memory tree = _generateMerkleTree(leafs);
            manager.setManageRoot(address(this), tree[tree.length - 1][0]);

            ManageLeaf[] memory used = new ManageLeaf[](2);
            for (uint256 i; i < leafs.length; ++i) {
                if (leafs[i].target == address(apxUSD) && _equal(leafs[i].signature, "approve(address,uint256)")) {
                    used[0] = leafs[i];
                }
                if (
                    leafs[i].target == pendleRouter
                        && _equal(
                            leafs[i].signature,
                            "mintSyFromToken(address,address,uint256,(address,uint256,address,address,(uint8,address,bytes,bool)))"
                        ) && leafs[i].argumentAddresses[2] == address(apxUSD)
                ) {
                    used[1] = leafs[i];
                }
            }
            require(used[0].target != address(0), "apxUSD approve leaf missing");
            require(used[1].target != address(0), "mintSy apxUSD leaf missing");
            proofs = _getProofsUsingTree(used, tree);
        }

        // Discover the SY address and record vault's SY balance before.
        (address sy,,) = PendleMarket(PENDLE_APXUSD_MARKET).readTokens();
        uint256 syBefore = ERC20(sy).balanceOf(address(boringVault));

        DecoderCustomTypes.SwapData memory swapData =
            DecoderCustomTypes.SwapData(DecoderCustomTypes.SwapType.NONE, address(0), hex"", false);
        DecoderCustomTypes.TokenInput memory tokenInput =
            DecoderCustomTypes.TokenInput(address(apxUSD), mintAmount, address(apxUSD), address(0), swapData);

        address[] memory targets = new address[](2);
        targets[0] = address(apxUSD);
        targets[1] = pendleRouter;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", pendleRouter, type(uint256).max);
        data[1] = abi.encodeWithSignature(
            "mintSyFromToken(address,address,uint256,(address,uint256,address,address,(uint8,address,bytes,bool)))",
            address(boringVault),
            sy,
            0,
            tokenInput
        );

        address[] memory decoders = new address[](2);
        decoders[0] = rawDataDecoderAndSanitizer;
        decoders[1] = rawDataDecoderAndSanitizer;

        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, data, new uint256[](2));

        assertGt(ERC20(sy).balanceOf(address(boringVault)), syBefore, "SY not minted to vault");
    }

    // ======================================================================================
    // Action 3: LP apxUSD/USDC on Curve — add_liquidity on the stable-ng factory pool.
    // ======================================================================================
    function testStrategistCurveAddLiquidity() external {
        address pool = CURVE_APXUSD_USDC_POOL;
        ERC20 usdc = ERC20(getAddress(sourceChain, "USDC"));
        ERC20 apxUSD = ERC20(APX_USD);

        uint256 usdcAmount = 1_000 * (10 ** usdc.decimals());
        uint256 apxUSDAmount = 1_000 * (10 ** apxUSD.decimals());
        deal(address(usdc), address(boringVault), usdcAmount);
        deal(address(apxUSD), address(boringVault), apxUSDAmount);

        bytes32[][] memory proofs;
        {
            ManageLeaf[] memory leafs = new ManageLeaf[](16);
            _addCurveLeafs(leafs, pool, 2, address(0));
            bytes32[][] memory tree = _generateMerkleTree(leafs);
            manager.setManageRoot(address(this), tree[tree.length - 1][0]);

            ManageLeaf[] memory used = new ManageLeaf[](3);
            for (uint256 i; i < leafs.length; ++i) {
                if (leafs[i].target == address(usdc) && _equal(leafs[i].signature, "approve(address,uint256)")) {
                    used[0] = leafs[i];
                }
                if (leafs[i].target == address(apxUSD) && _equal(leafs[i].signature, "approve(address,uint256)")) {
                    used[1] = leafs[i];
                }
                if (leafs[i].target == pool && _equal(leafs[i].signature, "add_liquidity(uint256[],uint256)")) {
                    used[2] = leafs[i];
                }
            }
            require(used[2].target != address(0), "add_liquidity leaf missing");
            proofs = _getProofsUsingTree(used, tree);
        }

        // Curve stable-ng pool.coins(0)/coins(1) tells us which index is which token.
        uint256[] memory amounts = new uint256[](2);
        address coin0 = CurvePool(pool).coins(0);
        if (coin0 == address(usdc)) {
            amounts[0] = usdcAmount;
            amounts[1] = apxUSDAmount;
        } else {
            amounts[0] = apxUSDAmount;
            amounts[1] = usdcAmount;
        }

        address[] memory targets = new address[](3);
        targets[0] = address(usdc);
        targets[1] = address(apxUSD);
        targets[2] = pool;

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", pool, type(uint256).max);
        data[1] = abi.encodeWithSignature("approve(address,uint256)", pool, type(uint256).max);
        data[2] = abi.encodeWithSignature("add_liquidity(uint256[],uint256)", amounts, 0);

        address[] memory decoders = new address[](3);
        decoders[0] = rawDataDecoderAndSanitizer;
        decoders[1] = rawDataDecoderAndSanitizer;
        decoders[2] = rawDataDecoderAndSanitizer;

        uint256 lpBefore = ERC20(pool).balanceOf(address(boringVault));
        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, data, new uint256[](3));
        assertGt(ERC20(pool).balanceOf(address(boringVault)), lpBefore, "Curve LP not minted to vault");
    }

    // ======================================================================================
    // Action 4: Morpho Blue — supplyCollateral(apyUSD) + borrow(USDC). Note the direction is
    // reversed from the assignment text ("supply USDC, borrow apyUSD") because the only live
    // Apyx Morpho market is apyUSD-collateral / USDC-loan. Test is direction-agnostic; it reads
    // collateralToken/loanToken straight off MarketParams.
    // ======================================================================================
    function testStrategistMorphoSupplyAndBorrow() external {
        address morphoBlue = getAddress(sourceChain, "morphoBlue");

        // The Morpho helper fetches MarketParams via idToMarketParams; we do the same so our
        // tx calldata encodes exactly the same tuple that produced the leaves.
        DecoderCustomTypes.MarketParams memory params =
            IMB(morphoBlue).idToMarketParams(MORPHO_APYUSD_USDC_MARKET_ID);
        ERC20 collateral = ERC20(params.collateralToken);
        ERC20 loan = ERC20(params.loanToken);

        uint256 collateralAmount = 10_000 * (10 ** collateral.decimals());
        uint256 borrowAmount = 1_000 * (10 ** loan.decimals());
        deal(address(collateral), address(boringVault), collateralAmount);

        bytes32[][] memory proofs;
        {
            ManageLeaf[] memory leafs = new ManageLeaf[](16);
            _addMorphoBlueCollateralLeafs(leafs, MORPHO_APYUSD_USDC_MARKET_ID);
            bytes32[][] memory tree = _generateMerkleTree(leafs);
            manager.setManageRoot(address(this), tree[tree.length - 1][0]);

            ManageLeaf[] memory used = new ManageLeaf[](3);
            for (uint256 i; i < leafs.length; ++i) {
                if (leafs[i].target == address(collateral) && _equal(leafs[i].signature, "approve(address,uint256)")) {
                    used[0] = leafs[i];
                }
                if (
                    leafs[i].target == morphoBlue
                        && _equal(
                            leafs[i].signature,
                            "supplyCollateral((address,address,address,address,uint256),uint256,address,bytes)"
                        )
                ) {
                    used[1] = leafs[i];
                }
                if (
                    leafs[i].target == morphoBlue
                        && _equal(
                            leafs[i].signature,
                            "borrow((address,address,address,address,uint256),uint256,uint256,address,address)"
                        )
                ) {
                    used[2] = leafs[i];
                }
            }
            require(used[1].target != address(0), "supplyCollateral leaf missing");
            require(used[2].target != address(0), "borrow leaf missing");
            proofs = _getProofsUsingTree(used, tree);
        }

        address[] memory targets = new address[](3);
        targets[0] = address(collateral);
        targets[1] = morphoBlue;
        targets[2] = morphoBlue;

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", morphoBlue, type(uint256).max);
        data[1] = abi.encodeWithSignature(
            "supplyCollateral((address,address,address,address,uint256),uint256,address,bytes)",
            params,
            collateralAmount,
            address(boringVault),
            hex""
        );
        data[2] = abi.encodeWithSignature(
            "borrow((address,address,address,address,uint256),uint256,uint256,address,address)",
            params,
            borrowAmount,
            0,
            address(boringVault),
            address(boringVault)
        );

        address[] memory decoders = new address[](3);
        decoders[0] = rawDataDecoderAndSanitizer;
        decoders[1] = rawDataDecoderAndSanitizer;
        decoders[2] = rawDataDecoderAndSanitizer;

        uint256 loanBefore = loan.balanceOf(address(boringVault));
        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, data, new uint256[](3));
        assertEq(loan.balanceOf(address(boringVault)), loanBefore + borrowAmount, "loan asset not received");
    }

    // ========================================= HELPERS =========================================

    function _equal(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        // blockNumber=0 → fork from latest (apyUSD/apxUSD are recent deployments, pre-deploy blocks
        // won't have them).
        forkId = blockNumber == 0 ? vm.createFork(vm.envString(rpcKey)) : vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}

// Minimal interfaces used by the test only — match the helpers' call signatures.
interface PendleMarket {
    function readTokens() external view returns (address sy, address pt, address yt);
}

interface CurvePool {
    function coins(uint256) external view returns (address);
}

interface IMB {
    function idToMarketParams(bytes32) external view returns (DecoderCustomTypes.MarketParams memory);
}
