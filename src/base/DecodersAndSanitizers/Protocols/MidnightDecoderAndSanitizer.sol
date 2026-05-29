// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

/// @notice DecoderAndSanitizer for Midnight (Morpho fixed-rate, orderbook credit).
/// @dev covers the lender (taker) path: `take` to buy credit and `withdraw` to redeem at maturity.
abstract contract MidnightDecoderAndSanitizer is BaseDecoderAndSanitizer {
    //============================== ERRORS ===============================

    error MidnightDecoderAndSanitizer__TakerCallbackNotSupported();
    error MidnightDecoderAndSanitizer__BorrowNotSupported();

    // midnight

    function take(
        DecoderCustomTypes.MidnightOffer calldata offer,
        bytes calldata, /* ratifierData */
        uint256, /* units */
        address taker,
        address receiverIfTakerIsSeller,
        address takerCallback,
        bytes calldata takerCallbackData
    ) external pure returns (bytes memory addressesFound) {
        // lender-only
        if (offer.buy) revert MidnightDecoderAndSanitizer__BorrowNotSupported();
        if (takerCallback != address(0) || takerCallbackData.length > 0) {
            revert MidnightDecoderAndSanitizer__TakerCallbackNotSupported();
        }
        addressesFound = abi.encodePacked(_packMarket(offer.market), taker, receiverIfTakerIsSeller);
    }

    function withdraw(
        DecoderCustomTypes.MidnightMarket calldata market,
        uint256, /* units */
        address onBehalf,
        address receiver
    ) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(_packMarket(market), onBehalf, receiver);
    }

    // internal

    /// @dev packs the market-identifying addresses in a deterministic order:
    /// loanToken, then (token, oracle) for each collateral, then the two gates.
    function _packMarket(DecoderCustomTypes.MidnightMarket calldata market)
        internal
        pure
        returns (bytes memory packed)
    {
        packed = abi.encodePacked(market.loanToken);
        uint256 len = market.collateralParams.length;
        for (uint256 i; i < len; ++i) {
            packed = abi.encodePacked(packed, market.collateralParams[i].token, market.collateralParams[i].oracle);
        }
        packed = abi.encodePacked(packed, market.enterGate, market.liquidatorGate);
    }
}
