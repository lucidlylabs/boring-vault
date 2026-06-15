// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract MorphoPublicAllocatorDecoderAndSanitizer is BaseDecoderAndSanitizer {
    struct Withdrawal {
        DecoderCustomTypes.MarketParams marketParams;
        uint128 amount;
    }

    // reallocateTo(address vault, Withdrawal[] withdrawals, MarketParams supplyMarketParams)
    // Pins the supplier MetaMorpho vault and the target supply market. The withdrawal source markets are
    // governed by the PublicAllocator's own per-market flow caps, so they are intentionally not pinned.
    function reallocateTo(
        address vault,
        Withdrawal[] calldata,
        DecoderCustomTypes.MarketParams calldata supplyMarketParams
    ) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(
            vault,
            supplyMarketParams.loanToken,
            supplyMarketParams.collateralToken,
            supplyMarketParams.oracle,
            supplyMarketParams.irm
        );
    }
}
