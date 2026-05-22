// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {AaveV3DecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/AaveV3DecoderAndSanitizer.sol";
import {AerodromeDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/AerodromeDecoderAndSanitizer.sol";
import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import {VelodromeDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/VelodromeDecoderAndSanitizer.sol";

contract LpHedgeStrategyDecoderAndSanitizer is AerodromeDecoderAndSanitizer, AaveV3DecoderAndSanitizer {
    error LpHedgeStrategyDecoderAndSanitizer__BadPathFormat();
    error LpHedgeStrategyDecoderAndSanitizer__TokenIdNotAllowed();

    uint256[] public allowedTokenIds;

    constructor(address _aerodromeNonFungiblePositionManager, uint256[] memory _allowedTokenIds)
        AerodromeDecoderAndSanitizer(_aerodromeNonFungiblePositionManager)
    {
        allowedTokenIds = _allowedTokenIds;
    }

    function exactInput(DecoderCustomTypes.ExactInputParams calldata params)
        external
        pure
        returns (bytes memory addressesFound)
    {
        uint256 chunkSize = 23; // 20 bytes token + 3 bytes tickSpacing/fee per hop.
        uint256 pathLength = params.path.length;
        if (pathLength % chunkSize != 20) revert LpHedgeStrategyDecoderAndSanitizer__BadPathFormat();

        uint256 pathAddressLength = 1 + (pathLength / chunkSize);
        uint256 pathIndex;
        for (uint256 i; i < pathAddressLength; ++i) {
            addressesFound = abi.encodePacked(addressesFound, params.path[pathIndex:pathIndex + 20]);
            pathIndex += chunkSize;
        }
        addressesFound = abi.encodePacked(addressesFound, params.recipient);
    }

    function increaseLiquidity(DecoderCustomTypes.IncreaseLiquidityParams calldata params)
        external
        view
        override(VelodromeDecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        _checkTokenId(params.tokenId);
        address owner = velodromeNonFungiblePositionManager.ownerOf(params.tokenId);
        (, address operator, address token0, address token1,,,,,,,,) =
            velodromeNonFungiblePositionManager.positions(params.tokenId);
        addressesFound = abi.encodePacked(operator, token0, token1, owner);
    }

    function decreaseLiquidity(DecoderCustomTypes.DecreaseLiquidityParams calldata params)
        external
        view
        override(VelodromeDecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        _checkTokenId(params.tokenId);
        address owner = velodromeNonFungiblePositionManager.ownerOf(params.tokenId);
        addressesFound = abi.encodePacked(owner);
    }

    function collect(DecoderCustomTypes.CollectParams calldata params)
        external
        view
        override(VelodromeDecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        _checkTokenId(params.tokenId);
        address owner = velodromeNonFungiblePositionManager.ownerOf(params.tokenId);
        addressesFound = abi.encodePacked(params.recipient, owner);
    }

    function withdraw(address asset, uint256, address to)
        external
        pure
        override(AaveV3DecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(asset, to);
    }

    function withdraw(uint256)
        external
        pure
        override(VelodromeDecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        return addressesFound;
    }

    function _checkTokenId(uint256 tokenId) internal view {
        for (uint256 i; i < allowedTokenIds.length; ++i) {
            if (allowedTokenIds[i] == tokenId) return;
        }
        revert LpHedgeStrategyDecoderAndSanitizer__TokenIdNotAllowed();
    }
}
