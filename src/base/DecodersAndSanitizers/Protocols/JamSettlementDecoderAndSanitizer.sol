// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract JamSettlementDecoderAndSanitizer is BaseDecoderAndSanitizer {
    error JamSettlementDecoderAndSanitizer__InvalidTokenArrayLength();
    error JamSettlementDecoderAndSanitizer__InvalidInteractionsLength();
    error JamSettlementDecoderAndSanitizer__HooksNotSupported();

    //============================== JAM SETTLEMENT ===============================
    // Example TX https://etherscan.io/tx/0x9094a719fcbbe1882e0bf852b052983fa692af7532027256e344367e1c3fc5b5

    function settle(
        DecoderCustomTypes.JamOrder memory order,
        bytes memory,
        DecoderCustomTypes.JamInteractionData[] memory interactions,
        bytes memory hooksData,
        address balanceRecipient
    ) external pure virtual returns (bytes memory addressesFound) {
        if (order.sellTokens.length != 1 || order.buyTokens.length != 1) {
            revert JamSettlementDecoderAndSanitizer__InvalidTokenArrayLength();
        }
        if (interactions.length != 1) {
            revert JamSettlementDecoderAndSanitizer__InvalidInteractionsLength();
        }
        if (hooksData.length != 0) {
            revert JamSettlementDecoderAndSanitizer__HooksNotSupported();
        }

        addressesFound = abi.encodePacked(
            order.taker,
            order.receiver,
            order.executor,
            order.sellTokens[0],
            order.buyTokens[0],
            balanceRecipient,
            interactions[0].to
        );
    }
}
