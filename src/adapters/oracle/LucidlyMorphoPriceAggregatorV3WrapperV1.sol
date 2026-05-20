// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

interface IMorphoOracle {
    function price() external view returns (uint256);
}

/// @title LucidlyMorphoPriceAggregatorV3WrapperV1
/// @author Lucidly Labs
/// @notice Wraps a Morpho-style `price()` oracle into a Chainlink AggregatorV3Interface.
contract LucidlyMorphoPriceAggregatorV3WrapperV1 {
    IMorphoOracle public immutable SOURCE_ORACLE;
    uint256 public immutable SCALE_DOWN;
    uint8 public immutable OUTPUT_DECIMALS;
    string private _description;

    /// @param sourceOracle address of the Morpho-style oracle exposing `price()`
    /// @param sourceDecimals decimals of the raw `price()` output (e.g., 24 for 18-dec collateral against 6-dec loan)
    /// @param outputDecimals desired output decimals (e.g., 8 to match Chainlink convention)
    /// @param oracleDescription human-readable description
    constructor(address sourceOracle, uint256 sourceDecimals, uint8 outputDecimals, string memory oracleDescription) {
        require(sourceOracle != address(0), "source is zero");
        require(sourceDecimals >= outputDecimals, "source < output decimals");
        SOURCE_ORACLE = IMorphoOracle(sourceOracle);
        SCALE_DOWN = 10 ** (sourceDecimals - outputDecimals);
        OUTPUT_DECIMALS = outputDecimals;
        _description = oracleDescription;
    }

    function decimals() external view returns (uint8) {
        return OUTPUT_DECIMALS;
    }

    function description() external view returns (string memory) {
        return _description;
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert("not implemented");
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        uint256 raw = SOURCE_ORACLE.price();
        answer = int256(raw / SCALE_DOWN);
        roundId = 0;
        startedAt = 0;
        updatedAt = block.timestamp;
        answeredInRound = 0;
    }
}
