// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import {AerodromeDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/AerodromeDecoderAndSanitizer.sol";
import {VelodromeDecoderAndSanitizer} from "./Protocols/VelodromeDecoderAndSanitizer.sol";
import {MagpieDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/MagpieDecoderAndSanitizer.sol";
import {
    NativeWrapperDecoderAndSanitizer
} from "src/base/DecodersAndSanitizers/Protocols/NativeWrapperDecoderAndSanitizer.sol";
import {
    MorphoV1FlashLoanAdapterDecoderAndSanitizer
} from "src/base/DecodersAndSanitizers/Protocols/MorphoV1FlashLoanAdapterDecoderAndSanitizer.sol";

contract AerodromeV3MagpieFullDecoderAndSanitizer is
    AerodromeDecoderAndSanitizer,
    MagpieDecoderAndSanitizer,
    NativeWrapperDecoderAndSanitizer,
    MorphoV1FlashLoanAdapterDecoderAndSanitizer
{
    constructor(address _aerodromeNonFungiblePositionManager, address _magpieRouter)
        AerodromeDecoderAndSanitizer(_aerodromeNonFungiblePositionManager)
        MagpieDecoderAndSanitizer(_magpieRouter)
    {}

    // handle function collisions

    /**
     * @notice NativeWrapper specifies a `deposit()`,
     *         all cases are handled the same way.
     */
    function deposit() external pure override(NativeWrapperDecoderAndSanitizer) returns (bytes memory addressesFound) {
        return addressesFound;
    }

    /**
     * @notice NativeWrapper specifies a `withdraw(uint256)`,
     *         all cases are handled the same way.
     */
    function withdraw(uint256)
        external
        pure
        override(NativeWrapperDecoderAndSanitizer, VelodromeDecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        // Nothing to sanitize or return
        return addressesFound;
    }
}
