// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {ChainlinkDataFeedLib, AggregatorV3Interface} from "./libraries/ChainlinkDataFeedLib.sol";

interface IEvkVault {
    function asset() external view returns (address);
    function balanceOf(address) external view returns (uint256);
    function convertToAssets(uint256) external view returns (uint256);
    function debtOf(address) external view returns (uint256);
}

contract EulerEVKTvlAdapter {
    address public immutable collateralVault;
    address public immutable borrowVault;

    address public immutable collateralToken;
    address public immutable debtToken;
    address public immutable baseToken;

    AggregatorV3Interface public immutable collateralUsdFeed;
    AggregatorV3Interface public immutable debtUsdFeed;
    AggregatorV3Interface public immutable baseUsdFeed;

    uint8 public immutable collateralDecimals;
    uint8 public immutable debtDecimals;
    uint8 public immutable baseDecimals;

    constructor(
        address _collateralVault,
        address _borrowVault,
        address _collateralUsdFeed,
        address _debtUsdFeed,
        address _baseUsdFeed,
        address _baseToken
    ) {
        collateralVault = _collateralVault;
        borrowVault = _borrowVault;
        collateralToken = IEvkVault(_collateralVault).asset();
        debtToken = IEvkVault(_borrowVault).asset();

        collateralUsdFeed = AggregatorV3Interface(_collateralUsdFeed);
        debtUsdFeed = AggregatorV3Interface(_debtUsdFeed);
        baseUsdFeed = AggregatorV3Interface(_baseUsdFeed);
        baseToken = _baseToken;

        collateralDecimals = ERC20(collateralToken).decimals();
        debtDecimals = ERC20(debtToken).decimals();
        baseDecimals = ERC20(_baseToken).decimals();
    }

    function _assetToBase(uint256 assetAmount, uint8 assetDecimals, AggregatorV3Interface assetUsdFeed)
        internal
        view
        returns (uint256 baseAmount)
    {
        uint256 assetUsd = _getPrice1e18(assetUsdFeed);
        uint256 baseUsd = _getPrice1e18(baseUsdFeed);

        baseAmount = (assetAmount * assetUsd * 10 ** baseDecimals) / (10 ** assetDecimals) / baseUsd;
    }

    function _getPrice1e18(AggregatorV3Interface feed) internal view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        require(answer > 0, "invalid price");
        require(updatedAt != 0, "stale round");

        uint8 feedDecimals = feed.decimals();
        uint256 price = uint256(answer);

        if (feedDecimals < 18) return price * (10 ** (18 - feedDecimals));
        if (feedDecimals > 18) return price / (10 ** (feedDecimals - 18));
        return price;
    }

    /// @dev returns net position value in base-token units
    function getUserTvl(address _user) external view returns (uint256 tvl) {
        (uint256 collateral, uint256 debt) = getUserPositionValues(_user);
        tvl = collateral > debt ? collateral - debt : 0;
    }

    /// @dev returns (collateral, debt) both in base-token units
    function getUserPositionValues(address _user)
        public
        view
        returns (uint256 collateral, uint256 debt)
    {
        uint256 collateralShares = IEvkVault(collateralVault).balanceOf(_user);
        uint256 collateralInTokenAmount = IEvkVault(collateralVault).convertToAssets(collateralShares);
        uint256 debtInTokenAmount = IEvkVault(borrowVault).debtOf(_user);

        collateral = _assetToBase(collateralInTokenAmount, collateralDecimals, collateralUsdFeed);
        debt = _assetToBase(debtInTokenAmount, debtDecimals, debtUsdFeed);
    }
}
