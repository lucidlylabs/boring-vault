// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer} from "./BaseDecoderAndSanitizer.sol";
import {ERC4626DecoderAndSanitizer} from "./Protocols/ERC4626DecoderAndSanitizer.sol";
import {CurveDecoderAndSanitizer} from "./Protocols/CurveDecoderAndSanitizer.sol";
import {MorphoBlueDecoderAndSanitizer} from "./Protocols/MorphoBlueDecoderAndSanitizer.sol";
import {PendleRouterDecoderAndSanitizer} from "./Protocols/PendleRouterDecoderAndSanitizer.sol";

contract ApyxUSDDecoderAndSanitizer is
    ERC4626DecoderAndSanitizer,
    CurveDecoderAndSanitizer,
    MorphoBlueDecoderAndSanitizer,
    PendleRouterDecoderAndSanitizer
{
    // ERC4626 and Curve both declare deposit(uint256,address); override resolves the collision.
    function deposit(uint256, address receiver)
        external
        pure
        override(ERC4626DecoderAndSanitizer, CurveDecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(receiver);
    }
}
