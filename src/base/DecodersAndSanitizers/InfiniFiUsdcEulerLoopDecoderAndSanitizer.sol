// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer} from "./BaseDecoderAndSanitizer.sol";
import {ERC4626DecoderAndSanitizer} from "./Protocols/ERC4626DecoderAndSanitizer.sol";
import {EulerEVKDecoderAndSanitizer} from "./Protocols/EulerEVKDecoderAndSanitizer.sol";
import {InfiniDecoderAndSanitizer} from "./Protocols/InfiniDecoderAndSanitizer.sol";
import {MorphoV1FlashLoanAdapterDecoderAndSanitizer} from
    "./Protocols/MorphoV1FlashLoanAdapterDecoderAndSanitizer.sol";

contract InfiniFiUsdcEulerLoopDecoderAndSanitizer is
    EulerEVKDecoderAndSanitizer,
    InfiniDecoderAndSanitizer,
    MorphoV1FlashLoanAdapterDecoderAndSanitizer
{
    //============================== HANDLE FUNCTION COLLISIONS ===============================

    /**
     * @notice ERC4626 deposit(uint256,address). Euler inherits ERC4626.
     */
    function deposit(uint256, address receiver)
        external
        pure
        override(ERC4626DecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(receiver);
    }
}
