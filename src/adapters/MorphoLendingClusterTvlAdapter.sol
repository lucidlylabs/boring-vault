// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {IMorpho, MarketParams, Id, Position} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {SharesMathLib} from "../../lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {AggregatorV3Interface} from "./libraries/ChainlinkDataFeedLib.sol";

/// @notice Lending-only adapter. Does not value collateral or borrow positions.
contract MorphoLendingClusterTvlAdapter {
    using MorphoBalancesLib for IMorpho;
    using SharesMathLib for uint256;

    error ZeroAddress();
    error InvalidPrice();
    error InvalidUpdatedAt();
    error StalePrice();

    IMorpho public morpho;
    Id public immutable marketId;
    address public constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    address public immutable loanToken;
    address public immutable baseToken;

    AggregatorV3Interface public immutable loanUsdFeed;
    AggregatorV3Interface public immutable baseUsdFeed;

    uint8 public immutable loanDecimals;
    uint8 public immutable baseDecimals;
    uint8 public immutable loanFeedDecimals;
    uint8 public immutable baseFeedDecimals;
    uint256 public immutable maxFeedAge;

    constructor(
        bytes32 _marketId,
        address _loanUsdFeed,
        address _baseUsdFeed,
        address _baseToken,
        uint256 _maxFeedAge
    ) {
        if (_loanUsdFeed == address(0)) revert ZeroAddress();
        if (_baseUsdFeed == address(0)) revert ZeroAddress();
        if (_baseToken == address(0)) revert ZeroAddress();

        marketId = Id.wrap(_marketId);
        morpho = IMorpho(MORPHO);

        MarketParams memory marketParams = morpho.idToMarketParams(marketId);
        loanToken = marketParams.loanToken;

        loanUsdFeed = AggregatorV3Interface(_loanUsdFeed);
        baseUsdFeed = AggregatorV3Interface(_baseUsdFeed);
        baseToken = _baseToken;
        maxFeedAge = _maxFeedAge;

        loanDecimals = ERC20(loanToken).decimals();
        baseDecimals = ERC20(_baseToken).decimals();
        loanFeedDecimals = loanUsdFeed.decimals();
        baseFeedDecimals = baseUsdFeed.decimals();
    }

    function _assetToBase(
        uint256 assetAmount,
        uint8 assetDecimals,
        AggregatorV3Interface assetUsdFeed,
        uint8 assetFeedDecimals
    ) internal view returns (uint256 baseAmount) {
        uint256 assetUsd = _getPrice1e18(assetUsdFeed, assetFeedDecimals);
        uint256 baseUsd = _getPrice1e18(baseUsdFeed, baseFeedDecimals);

        baseAmount = (assetAmount * assetUsd * 10 ** baseDecimals) / (10 ** assetDecimals) / baseUsd;
    }

    function _getPrice1e18(AggregatorV3Interface feed, uint8 feedDecimals) internal view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        if (answer <= 0) revert InvalidPrice();
        if (updatedAt == 0) revert InvalidUpdatedAt();
        if (block.timestamp - updatedAt > maxFeedAge) revert StalePrice();

        uint256 price = uint256(answer);

        if (feedDecimals < 18) return price * (10 ** (18 - feedDecimals));
        if (feedDecimals > 18) return price / (10 ** (feedDecimals - 18));
        return price;
    }

    /// @dev Returns lending-only supplied value in base terms. Collateral and debt are intentionally ignored.
    function getUserTvl(address _user) external view returns (uint256 tvl) {
        tvl = getUserSuppliedValue(_user);
    }

    function getUserSuppliedValue(address _user) public view returns (uint256 supplied) {
        uint256 suppliedAssets = getUserSupplyAssets(_user);
        if (loanToken == baseToken) return suppliedAssets;

        supplied = _assetToBase(suppliedAssets, loanDecimals, loanUsdFeed, loanFeedDecimals);
    }

    function getUserSupplyAssets(address user) public view returns (uint256) {
        MarketParams memory marketParams = morpho.idToMarketParams(marketId);
        (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) = morpho.expectedMarketBalances(marketParams);

        Position memory userPosition = morpho.position(marketId, user);

        return userPosition.supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
    }

    function getMarketParams() external view returns (MarketParams memory) {
        return morpho.idToMarketParams(marketId);
    }
}
