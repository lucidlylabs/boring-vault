// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "./BaseDecoderAndSanitizer.sol";
import {ERC4626DecoderAndSanitizer} from "./Protocols/ERC4626DecoderAndSanitizer.sol";
import {EthenaWithdrawDecoderAndSanitizer} from "./Protocols/EthenaWithdrawDecoderAndSanitizer.sol";
import {MagpieDecoderAndSanitizer} from "./MagpieDecoderAndSanitizer.sol";
import {PendleRouterDecoderAndSanitizer} from "./Protocols/PendleRouterDecoderAndSanitizer.sol";

contract DnEnaPtHedgeEthereumDecoderAndSanitizer is
    BaseDecoderAndSanitizer,
    ERC4626DecoderAndSanitizer,
    EthenaWithdrawDecoderAndSanitizer,
    MagpieDecoderAndSanitizer,
    PendleRouterDecoderAndSanitizer
{
    constructor(address _magpieRouter) MagpieDecoderAndSanitizer(_magpieRouter) {}

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

    function swapExactTokenForPt(
        address receiver,
        address market,
        uint256,
        DecoderCustomTypes.ApproxParams calldata,
        DecoderCustomTypes.TokenInput calldata input,
        DecoderCustomTypes.LimitOrderData calldata limit
    ) external pure returns (bytes memory addressesFound) {
        if (
            input.swapData.swapType != DecoderCustomTypes.SwapType.NONE || input.swapData.extRouter != address(0)
                || input.pendleSwap != address(0) || input.tokenIn != input.tokenMintSy
        ) {
            revert PendleRouterDecoderAndSanitizer__AggregatorSwapsNotPermitted();
        }

        addressesFound = abi.encodePacked(
            receiver,
            market,
            input.tokenIn,
            input.tokenMintSy,
            input.pendleSwap,
            input.swapData.extRouter,
            _sanitizeLimitOrderData(limit)
        );
    }

    function swapExactPtForToken(
        address receiver,
        address market,
        uint256,
        DecoderCustomTypes.TokenOutput calldata output,
        DecoderCustomTypes.LimitOrderData calldata limit
    ) external pure returns (bytes memory addressesFound) {
        if (
            output.swapData.swapType != DecoderCustomTypes.SwapType.NONE || output.swapData.extRouter != address(0)
                || output.pendleSwap != address(0) || output.tokenOut != output.tokenRedeemSy
        ) {
            revert PendleRouterDecoderAndSanitizer__AggregatorSwapsNotPermitted();
        }

        addressesFound = abi.encodePacked(
            receiver, market, output.tokenOut, output.tokenRedeemSy, output.pendleSwap, _sanitizeLimitOrderData(limit)
        );
    }
}
