// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test, stdStorage, StdStorage, stdError, console, Vm} from "../../lib/forge-std/src/Test.sol";
import {BoringVault, Auth} from "../../src/base/BoringVault.sol";
import {ManagerWithMerkleVerification} from "../../src/base/Roles/ManagerWithMerkleVerification.sol";
import {SafeTransferLib} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {RolesAuthority, Authority} from "../../lib/solmate/src/auth/authorities/RolesAuthority.sol";
import {MerkleTreeHelper} from "../../test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {AddressToBytes32Lib} from "../../src/helper/AddressToBytes32Lib.sol";
import {DecoderCustomTypes} from "../../src/interfaces/DecoderCustomTypes.sol";
import {KyberSwapDecoderAndSanitizer} from
    "../../src/base/DecodersAndSanitizers/Protocols/KyberSwapDecoderAndSanitizer.sol";

contract KyberSwapIntegTest is Test, MerkleTreeHelper {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;
    using AddressToBytes32Lib for address;

    ManagerWithMerkleVerification public manager;
    BoringVault public boringVault;
    address public rawDataDecoderAndSanitizer;
    RolesAuthority public rolesAuthority;

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 2;
    uint8 public constant MANGER_INTERNAL_ROLE = 3;
    uint8 public constant ADMIN_ROLE = 4;
    uint8 public constant BORING_VAULT_ROLE = 5;
    uint8 public constant BALANCER_VAULT_ROLE = 6;

    function _setUp() internal {
        setSourceChainName("mainnet");
        _startFork("MAINNET_RPC_URL", 20000000);

        boringVault = new BoringVault(address(this), "Boring Vault", "BV", 18);

        manager =
            new ManagerWithMerkleVerification(address(this), address(boringVault), getAddress(sourceChain, "vault"));

        rawDataDecoderAndSanitizer = address(
            new FullKyberSwapDecoderAndSanitizer(getAddress(sourceChain, "kyberAggregationRouterV2"))
        );

        setAddress(false, sourceChain, "boringVault", address(boringVault));
        setAddress(false, sourceChain, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizer);
        setAddress(false, sourceChain, "manager", address(manager));
        setAddress(false, sourceChain, "managerAddress", address(manager));
        setAddress(false, sourceChain, "accountantAddress", address(1));

        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        boringVault.setAuthority(rolesAuthority);
        manager.setAuthority(rolesAuthority);

        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(boringVault),
            bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)"))),
            true
        );
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(boringVault),
            bytes4(keccak256(abi.encodePacked("manage(address[],bytes[],uint256[])"))),
            true
        );
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(manager),
            ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
            true
        );
        rolesAuthority.setRoleCapability(
            MANGER_INTERNAL_ROLE,
            address(manager),
            ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
            true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(manager), ManagerWithMerkleVerification.setManageRoot.selector, true
        );

        rolesAuthority.setUserRole(address(this), STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(address(manager), MANGER_INTERNAL_ROLE, true);
        rolesAuthority.setUserRole(address(this), ADMIN_ROLE, true);
        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(address(boringVault), BORING_VAULT_ROLE, true);
    }

    function testKyberSwapDecoderReturnsSensitiveAddresses() external {
        _setUp();

        address weth = getAddress(sourceChain, "WETH");
        address usdc = getAddress(sourceChain, "USDC");

        DecoderCustomTypes.SwapExecutionParams memory execution = _buildSwap(weth, usdc, address(boringVault));

        // The manager extracts addresses by calling the decoder with the exact swap calldata.
        bytes memory addressesFound = FullKyberSwapDecoderAndSanitizer(rawDataDecoderAndSanitizer).swap(execution);

        assertEq(addressesFound, abi.encodePacked(weth, usdc, address(boringVault)), "decoder packed wrong addresses");
    }

    function testKyberSwapSwapThroughManager() external {
        _setUp();

        address weth = getAddress(sourceChain, "WETH");
        address usdc = getAddress(sourceChain, "USDC");
        address router = getAddress(sourceChain, "kyberAggregationRouterV2");

        deal(weth, address(boringVault), 1_000e18);

        // Build the merkle tree using the production leaf builder.
        address[] memory tokens = new address[](3);
        SwapKind[] memory kind = new SwapKind[](3);
        tokens[0] = usdc;
        kind[0] = SwapKind.BuyAndSell;
        tokens[1] = weth;
        kind[1] = SwapKind.BuyAndSell;
        tokens[2] = getAddress(sourceChain, "USDT");
        kind[2] = SwapKind.BuyAndSell;

        ManageLeaf[] memory leafs = new ManageLeaf[](16);
        _addKyberSwapLeafs(leafs, tokens, kind);

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);

        // Mock the router runtime so the swap call executes without a live route.
        vm.etch(router, address(new MockKyberRouter()).code);

        // Re-create the two leafs we will actually use: approve + swap (WETH -> USDC).
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](2);
        manageLeafs[0] = ManageLeaf(
            weth, false, "approve(address,uint256)", new address[](1), "", rawDataDecoderAndSanitizer
        );
        manageLeafs[0].argumentAddresses[0] = router;
        manageLeafs[1] = ManageLeaf(
            router,
            false,
            "swap((address,address,bytes,(address,address,address[],uint256[],address[],uint256[],address,uint256,uint256,uint256,bytes),bytes))",
            new address[](3),
            "",
            rawDataDecoderAndSanitizer
        );
        manageLeafs[1].argumentAddresses[0] = weth;
        manageLeafs[1].argumentAddresses[1] = usdc;
        manageLeafs[1].argumentAddresses[2] = address(boringVault);

        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        address[] memory targets = new address[](2);
        targets[0] = weth;
        targets[1] = router;

        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSignature("approve(address,uint256)", router, type(uint256).max);
        targetData[1] = abi.encodeWithSelector(
            KyberSwapDecoderAndSanitizer.swap.selector, _buildSwap(weth, usdc, address(boringVault))
        );

        address[] memory decodersAndSanitizers = new address[](2);
        decodersAndSanitizers[0] = rawDataDecoderAndSanitizer;
        decodersAndSanitizers[1] = rawDataDecoderAndSanitizer;

        uint256[] memory values = new uint256[](2);

        // Verifies the proofs against the root, decodes via the KyberSwap decoder, and executes.
        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);
    }

    function _buildSwap(address srcToken, address dstToken, address dstReceiver)
        internal
        pure
        returns (DecoderCustomTypes.SwapExecutionParams memory execution)
    {
        DecoderCustomTypes.SwapDescriptionV2 memory desc;
        desc.srcToken = srcToken;
        desc.dstToken = dstToken;
        desc.srcReceivers = new address[](0);
        desc.srcAmounts = new uint256[](0);
        desc.feeReceivers = new address[](0);
        desc.feeAmounts = new uint256[](0);
        desc.dstReceiver = dstReceiver;
        desc.amount = 1e18;
        desc.minReturnAmount = 1;
        desc.flags = 0;
        desc.permit = hex"";

        execution.callTarget = address(0);
        execution.approveTarget = address(0);
        execution.targetData = hex"";
        execution.desc = desc;
        execution.clientData = hex"";
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}

contract FullKyberSwapDecoderAndSanitizer is KyberSwapDecoderAndSanitizer {
    constructor(address _kyberRouter) KyberSwapDecoderAndSanitizer(_kyberRouter) {}
}

contract MockKyberRouter {
    function swap(DecoderCustomTypes.SwapExecutionParams calldata)
        external
        payable
        returns (uint256 returnAmount, uint256 gasUsed)
    {
        return (0, 0);
    }
}
