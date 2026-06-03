// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {IMorpho, MarketParams, Id, Position} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {SharesMathLib} from "../../lib/morpho-blue/src/libraries/SharesMathLib.sol";

contract WethUsdcMorphoBalanceAdapter {
    using MorphoBalancesLib for IMorpho;
    using SharesMathLib for uint256;

    error StaticCallFailed(string label);

    Id public immutable MORPHO_MARKET_ID;
    address public immutable WSTETH_USD_CHAINLINK_FEED;
    address public immutable WETH_USD_CHAINLINK_FEED;
    address public immutable USDC_USD_CHAINLINK_FEED;
    address public immutable SYUSD_VAULT;
    address public immutable SYUSD_ACCOUNTANT;

    address public constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    constructor(
        bytes32 morphoMarketId,
        address wstethUsdFeed_,
        address wethUsdFeed_,
        address usdcUsdFeed_,
        address syusdVault,
        address syusdAccountant
    ) {
        MORPHO_MARKET_ID = Id.wrap(morphoMarketId);
        WSTETH_USD_CHAINLINK_FEED = wstethUsdFeed_;
        WETH_USD_CHAINLINK_FEED = wethUsdFeed_;
        USDC_USD_CHAINLINK_FEED = usdcUsdFeed_;
        SYUSD_VAULT = syusdVault;
        SYUSD_ACCOUNTANT = syusdAccountant;
    }

    function wstEthUsdPrice() public view returns (uint256) {
        (bool success, bytes memory data) =
            WSTETH_USD_CHAINLINK_FEED.staticcall(abi.encodeWithSignature("latestAnswer()"));
        if (!success) revert StaticCallFailed("wstethusd/latestAnswer");
        int256 answer = abi.decode(data, (int256));
        require(answer >= 0, "negative answer");
        return uint256(answer);
    }

    function wethUsdPrice() public view returns (uint256) {
        (bool success, bytes memory data) =
            WETH_USD_CHAINLINK_FEED.staticcall(abi.encodeWithSignature("latestAnswer()"));
        if (!success) revert StaticCallFailed("wethusd/latestAnswer");
        int256 answer = abi.decode(data, (int256));
        require(answer >= 0, "negative answer");
        return uint256(answer);
    }

    function usdcUsdPrice() public view returns (uint256) {
        (bool success, bytes memory data) =
            USDC_USD_CHAINLINK_FEED.staticcall(abi.encodeWithSignature("latestAnswer()"));
        if (!success) revert StaticCallFailed("usdcusd/latestAnswer");
        int256 answer = abi.decode(data, (int256));
        require(answer >= 0, "negative answer");
        return uint256(answer);
    }

    /// @notice Returns net TVL of a user denominated in WETH (18 decimals).
    function getUserTvl(address user) external view returns (uint256) {
        (uint256 collateral, uint256 debt, uint256 credit) = getUserPosition(user);
        return collateral - debt + credit;
    }

    /// @notice Returns the full position breakdown for a user, all in WETH (18 decimals).
    function getUserPosition(address user)
        public
        view
        returns (uint256 totalCollateralInWeth, uint256 totalDebtInWeth, uint256 totalCreditInWeth)
    {
        uint256 wstEthPrice = wstEthUsdPrice(); // [8 dec]
        uint256 wethPrice = wethUsdPrice(); // [8 dec]
        uint256 usdcPrice = usdcUsdPrice(); // [8 dec]

        totalCollateralInWeth = _getMorphoCollateral(user, wethPrice, wstEthPrice);
        totalDebtInWeth = _getMorphoDebt(user, usdcPrice, wethPrice);
        totalCreditInWeth = _getSyUsdCredit(user, usdcPrice, wethPrice);
    }

    /// @dev Morpho `collateral` is in the market collateral token units (wstETH wei, 18 decimals for wstETH/USDC).
    ///      Converts wstETH notional to WETH using Chainlink wstETH/USD and ETH/USD feeds.
    function _getMorphoCollateral(address user, uint256 wethPrice, uint256 wstEthPrice)
        internal
        view
        returns (uint256)
    {
        Position memory userPosition = IMorpho(MORPHO).position(MORPHO_MARKET_ID, user);
        uint256 wstEthCollateral = uint256(userPosition.collateral); // [18 dec]
        uint256 collateralInUsd = (wstEthCollateral * wstEthPrice) / 1e18; // [8 dec]
        return (collateralInUsd * 1e18) / wethPrice; // [18 dec] WETH
    }

    /// @dev Returns user's USDC debt converted to WETH [18 dec].
    ///      usdcDebtBalance [6] * usdcPrice [8] / 1e6 → debtInUsd [8]
    ///      debtInUsd [8] * 1e18 / wethPrice [8]      → debtInWeth [18]
    function _getMorphoDebt(address user, uint256 usdcPrice, uint256 wethPrice) internal view returns (uint256) {
        IMorpho morpho = IMorpho(MORPHO);
        MarketParams memory marketParams = morpho.idToMarketParams(MORPHO_MARKET_ID);
        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = morpho.expectedMarketBalances(marketParams);

        Position memory userPosition = morpho.position(MORPHO_MARKET_ID, user);
        uint256 usdcDebtBalance = uint256(userPosition.borrowShares).toAssetsUp(totalBorrowAssets, totalBorrowShares); // [6 dec]

        uint256 debtInUsd = (usdcDebtBalance * usdcPrice) / 1e6;
        return (debtInUsd * 1e18) / wethPrice;
    }

    /// @dev Returns user's syUSD vault balance converted to WETH [18 dec].
    ///      syUsdBalance [6] * syUsdRate [6] / 1e6   → creditInUsdc [6]
    ///      creditInUsdc [6] * usdcPrice [8] / 1e6   → creditInUsd  [8]
    ///      creditInUsd  [8] * 1e18 / wethPrice [8]  → creditInWeth [18]
    function _getSyUsdCredit(address user, uint256 usdcPrice, uint256 wethPrice) internal view returns (uint256) {
        (bool balSuccess, bytes memory balData) =
            SYUSD_VAULT.staticcall(abi.encodeWithSignature("balanceOf(address)", user));
        if (!balSuccess) revert StaticCallFailed("syusd/balanceOf");
        uint256 syUsdBalance = abi.decode(balData, (uint256)); // [6 dec]

        (bool rateSuccess, bytes memory rateData) = SYUSD_ACCOUNTANT.staticcall(abi.encodeWithSignature("getRate()"));
        if (!rateSuccess) revert StaticCallFailed("syusd/getRate");
        uint256 syUsdRate = abi.decode(rateData, (uint256)); // [6 dec]

        uint256 creditInUsdc = (syUsdBalance * syUsdRate) / 1e6;
        uint256 creditInUsd = (creditInUsdc * usdcPrice) / 1e6;
        return (creditInUsd * 1e18) / wethPrice;
    }
}
