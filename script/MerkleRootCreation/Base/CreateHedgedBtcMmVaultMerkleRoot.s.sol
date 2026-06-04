// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

contract CreateHedgedBtcMmVaultMerkleRootScript is Script, MerkleTreeHelper {
    using FixedPointMathLib for uint256;

    uint256 public privateKeyOwner;

    uint8 public MANAGER_INTERNAL_ROLE = 4;

    address public accountantAddress = 0x702E248Ce74bEFA7f4552d54e8E1cabeA7FB2a6c;
    address public boringVault = 0xbEA97618434D925B0F9EdAB63aDF4Ce46F373b51;
    address public queue = 0xe805DBa580Fd26DD205ce554D12Fa53eA7b8d899;
    ManagerWithMerkleVerification public managerAddress =
        ManagerWithMerkleVerification(0x4dDb20a7d144787cb994F0D57bD836FB37Fe3980);
    address public rawDataDecoderAndSanitizer01 = 0xD267710e4726ad7a27B03C27EBE4a87Cfb318f2b;
    RolesAuthority public rolesAuthority = RolesAuthority(0x9E77719CD5AF96CD405fB27761c49215101A1dcA);
    address public teller = 0x1A82209E4120a6DfAab14fFb58F67b33A10ca836;

    function setUp() external {
        setSourceChainName(base);
        vm.createSelectFork(sourceChain);
    }

    function run() external {
        _generateSyUsdMultiChainMerkleRoot();
    }

    function _generateSyUsdMultiChainMerkleRoot() public {
        setAddress(true, base, "boringVault", boringVault);
        setAddress(true, base, "managerAddress", managerAddress);
        setAddress(true, base, "accountantAddress", accountantAddress);
        setAddress(true, base, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizer01);

        ManageLeaf[] memory leafs = new ManageLeaf[](512);
        ERC20[] memory feeAssets = new ERC20[](1);
        feeAssets[0] = getERC20(sourceChain, "USDC");
        _addLeafsForFeeClaiming(leafs, getAddress(sourceChain, "accountantAddress"), feeAssets, false);

        vm.startBroadcast(vm.envUint("DEPLOYER"));

        if (!rolesAuthority.doesRoleHaveCapability(
                MANAGER_INTERNAL_ROLE,
                managerAddress,
                ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector
            )) {
            rolesAuthority.setRoleCapability(
                MANAGER_INTERNAL_ROLE,
                managerAddress,
                ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
                true
            );
        }

        vm.stopBroadcast();
    }
}
