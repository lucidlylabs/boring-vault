// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BoringVault} from "src/base/BoringVault.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

import {Test, console} from "@forge-std/Test.sol";

contract ApyxDeployedE2ETest is Test, MerkleTreeHelper {
   
    address public constant APYX_USD_BORING_VAULT = 0x2505008ECe764719064E35AF7db5250cE2b0ff72;
    address public constant APYX_USD_MANAGER = 0xd5d867C86CaDdf1D3Bbfd04ae59F497a265Fd9D7;
    address public constant APYX_USD_ACCOUNTANT = 0x86474454f19957F286c59cf1ec7970EE9eA44F66;
    address public constant APYX_USD_ROLES_AUTHORITY = 0x3bDC72fDd59C1835F48d0Ab4ef202e3E7F6B3De2;
    address public constant APYX_USD_DECODER_AND_SANITIZER = 0x0A0962164D43C564d9d53a63a836D6B027B183ac;

   
    address public constant APYX_ADMIN = 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5;

    
    address public constant APY_USD = 0x38EEb52F0771140d10c4E9A9a72349A329Fe8a6A;
    address public constant APX_USD = 0x98A878b1Cd98131B271883B390f68D2c90674665;

    
    uint8 public constant STRATEGIST_ROLE = 7;

    address public strategist;

    function setUp() external {
        setSourceChainName("mainnet");
        _startFork("MAINNET_RPC_URL");

        strategist = makeAddr("apyxStrategist");

        
        setAddress(false, sourceChain, "boringVault", APYX_USD_BORING_VAULT);
        setAddress(false, sourceChain, "managerAddress", APYX_USD_MANAGER);
        setAddress(false, sourceChain, "accountantAddress", APYX_USD_ACCOUNTANT);
        setAddress(false, sourceChain, "rawDataDecoderAndSanitizer", APYX_USD_DECODER_AND_SANITIZER);
        setAddress(false, sourceChain, "apyUSD", APY_USD);
        setAddress(false, sourceChain, "apxUSD", APX_USD);
    }

    function test_E2E_mintApyUSD_onDeployedArchitecture() external {
       
        ManageLeaf[] memory leafs = new ManageLeaf[](8);
        _addERC4626Leafs(leafs, ERC4626(APY_USD));
        bytes32[][] memory tree = _generateMerkleTree(leafs);
        bytes32 root = tree[tree.length - 1][0];
        console.log("Computed merkle root:");
        console.logBytes32(root);

       
        vm.startPrank(APYX_ADMIN);
        RolesAuthority(APYX_USD_ROLES_AUTHORITY).setUserRole(strategist, STRATEGIST_ROLE, true);
        ManagerWithMerkleVerification(APYX_USD_MANAGER).setManageRoot(strategist, root);
        vm.stopPrank();

        assertTrue(
            RolesAuthority(APYX_USD_ROLES_AUTHORITY).doesUserHaveRole(strategist, STRATEGIST_ROLE),
            "strategist missing STRATEGIST_ROLE"
        );
        assertEq(
            ManagerWithMerkleVerification(APYX_USD_MANAGER).manageRoot(strategist),
            root,
            "manageRoot not set for strategist"
        );

        
        uint256 depositAmount = 1_000 * (10 ** ERC20(APX_USD).decimals());
        deal(APX_USD, APYX_USD_BORING_VAULT, depositAmount);

        
        uint256 apyUSDBefore = ERC20(APY_USD).balanceOf(APYX_USD_BORING_VAULT);
        uint256 apxUSDBefore = ERC20(APX_USD).balanceOf(APYX_USD_BORING_VAULT);

        _executeMintApyUSD(leafs, tree, depositAmount);

        uint256 apyUSDAfter = ERC20(APY_USD).balanceOf(APYX_USD_BORING_VAULT);
        uint256 apxUSDAfter = ERC20(APX_USD).balanceOf(APYX_USD_BORING_VAULT);

        assertGt(apyUSDAfter, apyUSDBefore, "apyUSD not minted into deployed vault");
        assertLt(apxUSDAfter, apxUSDBefore, "apxUSD not spent from deployed vault");

        console.log("apxUSD deposited:", apxUSDBefore - apxUSDAfter);
        console.log("apyUSD received:", apyUSDAfter - apyUSDBefore);
    }

    function test_E2E_unauthorizedAction_reverts() external {
        ManageLeaf[] memory leafs = new ManageLeaf[](8);
        _addERC4626Leafs(leafs, ERC4626(APY_USD));
        bytes32[][] memory tree = _generateMerkleTree(leafs);
        bytes32 root = tree[tree.length - 1][0];

        vm.startPrank(APYX_ADMIN);
        RolesAuthority(APYX_USD_ROLES_AUTHORITY).setUserRole(strategist, STRATEGIST_ROLE, true);
        ManagerWithMerkleVerification(APYX_USD_MANAGER).setManageRoot(strategist, root);
        vm.stopPrank();

        // USDT is not in the apyUSD-only tree — any proof we submit must fail.
        address usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

        bytes32[][] memory fakeProofs = new bytes32[][](1);
        fakeProofs[0] = new bytes32[](tree.length - 1);
        for (uint256 i; i < tree.length - 1; ++i) {
            fakeProofs[0][i] = tree[i][0];
        }

        address[] memory targets = new address[](1);
        targets[0] = usdt;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", strategist, type(uint256).max);

        address[] memory decoders = new address[](1);
        decoders[0] = APYX_USD_DECODER_AND_SANITIZER;

        vm.prank(strategist);
        vm.expectRevert(
            abi.encodeWithSelector(
                ManagerWithMerkleVerification.ManagerWithMerkleVerification__FailedToVerifyManageProof.selector,
                usdt,
                data[0],
                0
            )
        );
        ManagerWithMerkleVerification(APYX_USD_MANAGER).manageVaultWithMerkleVerification(
            fakeProofs, decoders, targets, data, new uint256[](1)
        );
    }

    function _executeMintApyUSD(ManageLeaf[] memory leafs, bytes32[][] memory tree, uint256 depositAmount) internal {
        ManageLeaf[] memory used = new ManageLeaf[](2);
        used[0] = leafs[0];
        used[1] = leafs[1];
        bytes32[][] memory proofs = _getProofsUsingTree(used, tree);

        address[] memory targets = new address[](2);
        targets[0] = APX_USD;
        targets[1] = APY_USD;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", APY_USD, type(uint256).max);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", depositAmount, APYX_USD_BORING_VAULT);

        address[] memory decoders = new address[](2);
        decoders[0] = APYX_USD_DECODER_AND_SANITIZER;
        decoders[1] = APYX_USD_DECODER_AND_SANITIZER;

        vm.prank(strategist);
        ManagerWithMerkleVerification(APYX_USD_MANAGER).manageVaultWithMerkleVerification(
            proofs, decoders, targets, data, new uint256[](2)
        );
    }

    function _startFork(string memory rpcKey) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey));
        vm.selectFork(forkId);
    }
}
