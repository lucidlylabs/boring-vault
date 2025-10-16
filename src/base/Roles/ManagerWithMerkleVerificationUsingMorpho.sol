// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {MerkleProofLib} from "@solmate/utils/MerkleProofLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {BalancerVault} from "src/interfaces/BalancerVault.sol";
import {IMorpho} from "src/interfaces/IMorpho.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {IPausable} from "src/interfaces/IPausable.sol";
import {DroneLib} from "src/base/Drones/DroneLib.sol";

contract ManagerWithMerkleVerificationUsingMorhpo is Auth, IPausable {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;
    using Address for address;

    // ========================================= STATE =========================================

    /**
     * @notice A merkle tree root that restricts what data can be passed to the BoringVault.
     * @dev Maps a strategist address to their specific merkle root.
     * @dev Each leaf is composed of the keccak256 hash of abi.encodePacked {decodersAndSanitizer, target, valueIsNonZero, selector, argumentAddress_0, ...., argumentAddress_N}
     *      Where:
     *             - decodersAndSanitizer is the addres to call to extract packed address arguments from the calldata
     *             - target is the address to make the call to
     *             - valueIsNonZero is a bool indicating whether or not the value is non-zero
     *             - selector is the function selector on target
     *             - argumentAddress is each allowed address argument in that call
     */
    mapping(address => bytes32) public manageRoot;

    /**
     * @notice Bool indicating whether or not this contract is actively performing a flash loan.
     * @dev Used to block flash loans that are initiated outside a manage call.
     */
    bool internal performingFlashLoan;

    /**
     * @notice keccak256 hash of flash loan data.
     */
    bytes32 internal flashLoanIntentHash = bytes32(0);

    /**
     * @notice Used to pause calls to `manageVaultWithMerkleVerification`.
     */
    bool public isPaused;

    //============================== ERRORS ===============================

    error ManagerWithMerkleVerification__InvalidManageProofLength();
    error ManagerWithMerkleVerification__InvalidTargetDataLength();
    error ManagerWithMerkleVerification__InvalidValuesLength();
    error ManagerWithMerkleVerification__InvalidDecodersAndSanitizersLength();
    error ManagerWithMerkleVerification__FlashLoanNotExecuted();
    error ManagerWithMerkleVerification__FlashLoanNotInProgress();
    error ManagerWithMerkleVerification__BadFlashLoanIntentHash();
    error ManagerWithMerkleVerification__FailedToVerifyManageProof(address target, bytes targetData, uint256 value);
    error ManagerWithMerkleVerification__Paused();
    error ManagerWithMerkleVerification__OnlyCallableByBoringVault();
    error ManagerWithMerkleVerification__OnlyCallableByBalancerVault();
    error ManagerWithMerkleVerification__OnlyCallableByMorpho();
    error ManagerWithMerkleVerification__TotalSupplyMustRemainConstantDuringPlatform();

    //============================== EVENTS ===============================

    event ManageRootUpdated(address indexed strategist, bytes32 oldRoot, bytes32 newRoot);
    event BoringVaultManaged(uint256 callsMade);
    event Paused();
    event Unpaused();

    //============================== IMMUTABLES ===============================

    /**
     * @notice The BoringVault this contract can manage.
     */
    BoringVault public immutable vault;

    /**
     * @notice morpho instance this contract can use for flashloans.
     */
    IMorpho public immutable morpho;

    constructor(address _owner, address _vault, address _morpho) Auth(_owner, Authority(address(0))) {
        vault = BoringVault(payable(_vault));
        morpho = IMorpho(_morpho);
    }

    // ========================================= ADMIN FUNCTIONS =========================================

    /**
     * @notice Sets the manageRoot.
     * @dev Callable by OWNER_ROLE.
     */
    function setManageRoot(address strategist, bytes32 _manageRoot) external requiresAuth {
        bytes32 oldRoot = manageRoot[strategist];
        manageRoot[strategist] = _manageRoot;
        emit ManageRootUpdated(strategist, oldRoot, _manageRoot);
    }

    /**
     * @notice Pause this contract, which prevents future calls to `manageVaultWithMerkleVerification`.
     * @dev Callable by MULTISIG_ROLE.
     */
    function pause() external requiresAuth {
        isPaused = true;
        emit Paused();
    }

    /**
     * @notice Unpause this contract, which allows future calls to `manageVaultWithMerkleVerification`.
     * @dev Callable by MULTISIG_ROLE.
     */
    function unpause() external requiresAuth {
        isPaused = false;
        emit Unpaused();
    }

    // ========================================= STRATEGIST FUNCTIONS =========================================

    /**
     * @notice Allows strategist to manage the BoringVault.
     * @dev The strategist must provide a merkle proof for every call that verifiees they are allowed to make that call.
     * @dev Callable by MANAGER_INTERNAL_ROLE.
     * @dev Callable by STRATEGIST_ROLE.
     * @dev Callable by MICRO_MANAGER_ROLE.
     */
    function manageVaultWithMerkleVerification(
        bytes32[][] calldata manageProofs,
        address[] calldata decodersAndSanitizers,
        address[] calldata targets,
        bytes[] calldata targetData,
        uint256[] calldata values
    ) external requiresAuth {
        if (isPaused) revert ManagerWithMerkleVerification__Paused();
        uint256 targetsLength = targets.length;
        if (targetsLength != manageProofs.length) revert ManagerWithMerkleVerification__InvalidManageProofLength();
        if (targetsLength != targetData.length) revert ManagerWithMerkleVerification__InvalidTargetDataLength();
        if (targetsLength != values.length) revert ManagerWithMerkleVerification__InvalidValuesLength();
        if (targetsLength != decodersAndSanitizers.length) {
            revert ManagerWithMerkleVerification__InvalidDecodersAndSanitizersLength();
        }

        bytes32 strategistManageRoot = manageRoot[msg.sender];
        uint256 totalSupply = vault.totalSupply();

        for (uint256 i; i < targetsLength; ++i) {
            _verifyCallData(
                strategistManageRoot, manageProofs[i], decodersAndSanitizers[i], targets[i], values[i], targetData[i]
            );
            vault.manage(targets[i], targetData[i], values[i]);
        }
        if (totalSupply != vault.totalSupply()) {
            revert ManagerWithMerkleVerification__TotalSupplyMustRemainConstantDuringPlatform();
        }
        emit BoringVaultManaged(targetsLength);
    }

    // ========================================= FLASH LOAN FUNCTIONS =========================================

    /**
     * @notice In order to perform a flash loan,
     *         1) Merkle root must contain the leaf(address(this), this.flashLoan.selector, ARGUMENT_ADDRESSES ...)
     *         2) Strategist must initiate the flash loan using `manageVaultWithMerkleVerification`
     *         3) balancerVault MUST callback to this contract with the same userData
     */
    function flashLoan(address token, uint256 amount, bytes calldata userData) external {
        if (msg.sender != address(vault)) revert ManagerWithMerkleVerification__OnlyCallableByBoringVault();

        flashLoanIntentHash = keccak256(userData);
        performingFlashLoan = true;
        morpho.flashLoan(token, amount, userData);
        performingFlashLoan = false;
        if (flashLoanIntentHash != bytes32(0)) revert ManagerWithMerkleVerification__FlashLoanNotExecuted();
    }

    /**
     * @notice Add support for morpho flashloans.
     * @dev userData can optionally have salt encoded at the end of it, in order to change the intentHash,
     *      if a flash loan is exact userData is being repeated, and their is fear of 3rd parties
     *      front-running the rebalance.
     */
    function onMorphoFlashLoan(uint256 amount, bytes calldata userData) external {
        if (msg.sender != address(morpho)) revert ManagerWithMerkleVerification__OnlyCallableByMorpho();
        if (!performingFlashLoan) revert ManagerWithMerkleVerification__FlashLoanNotInProgress();

        (address token, bytes memory baseUserData) = abi.decode(userData, (address, bytes));

        // validate userData using intentHash
        bytes32 intentHash = keccak256(userData);
        if (intentHash != flashLoanIntentHash) revert ManagerWithMerkleVerification__BadFlashLoanIntentHash();
        // reset intent hash to prevent replays
        flashLoanIntentHash = bytes32(0);

        // transfer tokens to vault
        ERC20(token).safeTransfer(address(vault), amount);
        {
            (
                bytes32[][] memory manageProofs,
                address[] memory decodersAndSanitizers,
                address[] memory targets,
                bytes[] memory data,
                uint256[] memory values
            ) = abi.decode(userData, (bytes32[][], address[], address[], bytes[], uint256[]));

            ManagerWithMerkleVerificationUsingMorhpo(address(this)).manageVaultWithMerkleVerification(
                manageProofs, decodersAndSanitizers, targets, data, values
            );
        }

        // approve morpho to transfer back tokens
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        bytes[] memory approveData = new bytes[](1);
        approveData[0] = abi.encodeWithSelector(ERC20.approve.selector, address(morpho), amount);
        vault.manage(tokens, approveData, new uint256[](1));
    }

    // ========================================= INTERNAL HELPER FUNCTIONS =========================================

    /**
     * @notice Helper function to decode, sanitize, and verify call data.
     */
    function _verifyCallData(
        bytes32 currentManageRoot,
        bytes32[] calldata manageProof,
        address decoderAndSanitizer,
        address target,
        uint256 value,
        bytes calldata targetData
    ) internal view {
        // Use address decoder to get addresses in call data.
        bytes memory packedArgumentAddresses = abi.decode(decoderAndSanitizer.functionStaticCall(targetData), (bytes));
        address droneTarget = DroneLib.extractTargetFromInput(targetData);
        if (droneTarget != address(0)) {
            packedArgumentAddresses = abi.encodePacked(packedArgumentAddresses, droneTarget);
        }

        if (
            !_verifyManageProof(
                currentManageRoot,
                manageProof,
                target,
                decoderAndSanitizer,
                value,
                bytes4(targetData),
                packedArgumentAddresses
            )
        ) {
            revert ManagerWithMerkleVerification__FailedToVerifyManageProof(target, targetData, value);
        }
    }

    /**
     * @notice Helper function to verify a manageProof is valid.
     */
    function _verifyManageProof(
        bytes32 root,
        bytes32[] calldata proof,
        address target,
        address decoderAndSanitizer,
        uint256 value,
        bytes4 selector,
        bytes memory packedArgumentAddresses
    ) internal pure returns (bool) {
        bool valueNonZero = value > 0;
        bytes32 leaf =
            keccak256(abi.encodePacked(decoderAndSanitizer, target, valueNonZero, selector, packedArgumentAddresses));
        return MerkleProofLib.verify(proof, root, leaf);
    }
}
