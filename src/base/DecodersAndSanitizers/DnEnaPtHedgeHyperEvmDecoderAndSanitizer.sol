// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {CctpCoreDepositWalletDecoderAndSanitizer} from "./Protocols/CctpCoreDepositWalletDecoderAndSanitizer.sol";
import {CoreWriterDecoderAndSanitizer} from "./Protocols/HlCoreWriterDecoderAndSanitizerTemp.sol";

contract DnEnaPtHedgeHyperEvmDecoderAndSanitizer is
    CctpCoreDepositWalletDecoderAndSanitizer,
    CoreWriterDecoderAndSanitizer
{
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
