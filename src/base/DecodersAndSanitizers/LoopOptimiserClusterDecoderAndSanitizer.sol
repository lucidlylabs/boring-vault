// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer} from "./BaseDecoderAndSanitizer.sol";
import {MorphoBlueDecoderAndSanitizer} from "./Protocols/MorphoBlueDecoderAndSanitizer.sol";
import {ERC4626DecoderAndSanitizer} from "./Protocols/ERC4626DecoderAndSanitizer.sol";
import {NativeWrapperDecoderAndSanitizer} from "./Protocols/NativeWrapperDecoderAndSanitizer.sol";
import {InfiniDecoderAndSanitizer} from "./Protocols/InfiniDecoderAndSanitizer.sol";
import {MagpieDecoderAndSanitizer} from "./MagpieDecoderAndSanitizer.sol";
import {MorphoV1FlashLoanAdapterDecoderAndSanitizer} from "./Protocols/MorphoV1FlashLoanAdapterDecoderAndSanitizer.sol";
import {MorphoPublicAllocatorDecoderAndSanitizer} from "./Protocols/MorphoPublicAllocatorDecoderAndSanitizer.sol";

contract LoopOptimiserClusterDecoderAndSanitizer is
    MorphoBlueDecoderAndSanitizer,
    ERC4626DecoderAndSanitizer,
    NativeWrapperDecoderAndSanitizer,
    InfiniDecoderAndSanitizer,
    MagpieDecoderAndSanitizer,
    MorphoV1FlashLoanAdapterDecoderAndSanitizer,
    MorphoPublicAllocatorDecoderAndSanitizer
{
    constructor(address _magpieRouter) MagpieDecoderAndSanitizer(_magpieRouter) {}

    //============================== HANDLE FUNCTION COLLISIONS ===============================

    function deposit(uint256, address receiver)
        external
        pure
        override(ERC4626DecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(receiver);
    }

    function deposit() external pure override(NativeWrapperDecoderAndSanitizer) returns (bytes memory addressesFound) {
        return addressesFound;
    }

    function withdraw(uint256)
        external
        pure
        override(NativeWrapperDecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        return addressesFound;
    }
}
