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

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/DeployDecoderAndSanitizer.s.sol:DeployDecoderAndSanitizerScript --broadcast --etherscan-api-key $ETHERSCAN_KEY --verify --with-gas-price 30000000000
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract SetStrategistRoles is Script, MerkleTreeHelper {
    uint256 public privateKey;

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
        privateKey = vm.envUint("BORING_DEVELOPER");
    }

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;

        vm.createSelectFork("mainnet");
        setSourceChainName("mainnet");
        vm.startBroadcast(privateKey);

        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE, address(manager), manager.manageVaultWithMerkleVerification.selector, true
        );
        rolesAuthority.setUserRole(vm.addr(vm.envUint("BORING_MORPHO_AGENT")), STRATEGIST_ROLE, true);

        vm.stopBroadcast();

        vm.createSelectFork("base");
        setSourceChainName("base");
        vm.startBroadcast(privateKey);

        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE, address(manager), manager.manageVaultWithMerkleVerification.selector, true
        );
        rolesAuthority.setUserRole(vm.addr(vm.envUint("BORING_MORPHO_AGENT")), STRATEGIST_ROLE, true);

        vm.stopBroadcast();
    }
}
