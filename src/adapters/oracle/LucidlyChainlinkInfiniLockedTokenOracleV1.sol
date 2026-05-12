// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {ERC20} from "../../../lib/solmate/src/tokens/ERC20.sol";
import {LucidlyChainlinkOracleBaseV1} from "./LucidlyChainlinkOracleBaseV1.sol";
import {AggregatorV3Interface} from "../libraries/ChainlinkDataFeedLib.sol";

interface IEulerPriceOracle {
    function getQuote(uint256 amount, address base, address quote) external view returns (uint256);
}

/// @title LucidlyChainlinkInfiniLockedTokenOracleV1
/// @author Lucidly Labs
/// @notice Chainlink-compliant oracle for an Infini locked-iUSD token (e.g. liUSD-13w).
///         Reads the USD value of one full token from Euler's market price oracle and
///         exposes it as a standard `latestRoundData()` feed.
contract LucidlyChainlinkInfiniLockedTokenOracleV1 is LucidlyChainlinkOracleBaseV1 {
    IEulerPriceOracle public immutable EULER_ORACLE;
    address public immutable LOCKED_TOKEN;

    /// @dev Euler convention: ISO 4217 numeric code 840 (USD) as a pseudo-address.
    address public constant USD_PSEUDO = 0x0000000000000000000000000000000000000348;

    /// @param eulerOracle Euler price oracle exposing getQuote(amount, base, quote)
    /// @param lockedToken Infini locked-iUSD token (18 decimals)
    /// @param baseFeed1 1st chainlink feed. address zero if price = 1
    /// @param baseFeed2 2nd chainlink feed. address zero if price = 1
    /// @param outputDecimals desired output decimals (e.g., 8 to match chainlink convention)
    constructor(
        IEulerPriceOracle eulerOracle,
        address lockedToken,
        AggregatorV3Interface baseFeed1,
        AggregatorV3Interface baseFeed2,
        uint8 outputDecimals,
        string memory _oracleDescription
    ) LucidlyChainlinkOracleBaseV1(baseFeed1, baseFeed2, 18, outputDecimals, _oracleDescription) {
        require(address(eulerOracle) != address(0), "euler oracle is zero");
        require(lockedToken != address(0), "locked token is zero");
        require(ERC20(lockedToken).decimals() == 18, "locked token must be 18 dec");
        EULER_ORACLE = eulerOracle;
        LOCKED_TOKEN = lockedToken;
    }

    /// @inheritdoc LucidlyChainlinkOracleBaseV1
    function _getBaseAmount() internal view override returns (uint256) {
        return EULER_ORACLE.getQuote(1e18, LOCKED_TOKEN, USD_PSEUDO);
    }
}
