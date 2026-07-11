// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {AaveV3DecoderAndSanitizer} from "./Protocols/AaveV3DecoderAndSanitizer.sol";
import {CctpCoreDepositWalletDecoderAndSanitizer} from "./Protocols/CctpCoreDepositWalletDecoderAndSanitizer.sol";

contract DnEnaPtHedgeHyperEvmDecoderAndSanitizer is
    AaveV3DecoderAndSanitizer,
    CctpCoreDepositWalletDecoderAndSanitizer
{
    error DnEnaPtHedgeHyperEvmDecoderAndSanitizer__InvalidCoreWriterAction();

    uint24 internal constant ACTION_LIMIT_ORDER = 1;
    uint24 internal constant ACTION_USD_CLASS_TRANSFER = 7;
    uint24 internal constant ACTION_SEND_ASSET = 13;

    function sendRawAction(bytes calldata data) external pure returns (bytes memory addressesFound) {
        if (data.length < 4 || data[0] != 0x01) {
            revert DnEnaPtHedgeHyperEvmDecoderAndSanitizer__InvalidCoreWriterAction();
        }

        uint24 actionId = uint24(uint8(data[1])) << 16 | uint24(uint8(data[2])) << 8 | uint24(uint8(data[3]));
        address actionIdAddress = address(uint160(actionId));

        if (actionId == ACTION_LIMIT_ORDER) {
            (uint32 asset,,,,,,) = abi.decode(data[4:], (uint32, bool, uint64, uint64, bool, uint8, uint128));
            addressesFound = abi.encodePacked(actionIdAddress, address(uint160(asset)));
        } else if (actionId == ACTION_USD_CLASS_TRANSFER) {
            addressesFound = abi.encodePacked(actionIdAddress);
        } else if (actionId == ACTION_SEND_ASSET) {
            (address destination, address subAccount,,, uint64 token,) =
                abi.decode(data[4:], (address, address, uint32, uint32, uint64, uint64));
            addressesFound = abi.encodePacked(actionIdAddress, destination, subAccount, address(uint160(token)));
        } else {
            revert DnEnaPtHedgeHyperEvmDecoderAndSanitizer__InvalidCoreWriterAction();
        }
    }

    function depositForBurn(
        uint256,
        uint32,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256,
        uint32
    ) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(
            address(uint160(uint256(mintRecipient))), burnToken, address(uint160(uint256(destinationCaller)))
        );
    }

    function depositForBurnWithHook(
        uint256,
        uint32,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256,
        uint32,
        bytes calldata
    ) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(
            address(uint160(uint256(mintRecipient))), burnToken, address(uint160(uint256(destinationCaller)))
        );
    }
}
