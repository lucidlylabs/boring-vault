// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {ERC20} from "../../../lib/solmate/src/tokens/ERC20.sol";
import {LucidlyChainlinkOracleBaseV1} from "./LucidlyChainlinkOracleBaseV1.sol";
import {AggregatorV3Interface} from "../libraries/ChainlinkDataFeedLib.sol";

interface IRoycoVaultTranche {
    struct AssetClaims {
        uint256 stAssets;
        uint256 jtAssets;
        uint256 nav;
    }

    // nav is the per-share NAV already denominated in USD; do not multiply by a price feed.
    function convertToAssets(uint256 shares) external view returns (AssetClaims memory);
}

/// @title LucidlyChainlinkRoycoVaultTrancheOracleV1
/// @author Lucidly Labs
/// @notice Lucidly Strategies royco vault tranche oracle contract base using Chainlink-compliant feeds.
contract LucidlyChainlinkRoycoVaultTrancheOracleV1 is LucidlyChainlinkOracleBaseV1 {
    IRoycoVaultTranche public immutable TRANCHE;

    /// @param tranche royco tranche address
    /// @param baseFeed1 1st chainlink feed. address zero if price = 1
    /// @param baseFeed2 2nd chainlink feed. address zero if price = 1
    /// @param outputDecimals desired output decimals (e.g., 8 to match chainlink convention)
    constructor(
        IRoycoVaultTranche tranche,
        AggregatorV3Interface baseFeed1,
        AggregatorV3Interface baseFeed2,
        uint8 outputDecimals,
        string memory _oracleDescription
    ) LucidlyChainlinkOracleBaseV1(baseFeed1, baseFeed2, 18, outputDecimals, _oracleDescription) {
        require(address(tranche) != address(0), "tranche is zero");
        require(ERC20(address(tranche)).decimals() == 18, "tranche must be 18 dec");
        TRANCHE = tranche;
    }

    function _getBaseAmount() internal view override returns (uint256) {
        return TRANCHE.convertToAssets(1e18).nav;
    }
}
