// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {IMidnight, Market} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {AggregatorV3Interface} from "./libraries/ChainlinkDataFeedLib.sol";

/// @notice tvl adapter for a midnight lender position (the vault holds `credit` in one market)
/// @dev Returns the value of the vault's live credit, denominated in the vault's base token.
///
/// note: a midnight lender holds `credit` units, each redeemable for 1 loan token at
/// maturity. `updatePositionView` returns (credit, pendingFee, accruedFee): `credit` already nets
/// realized bad-debt slashing (lossFactor) and the continuous fee accrued *so far*, while `pendingFee`
/// is the still-owed remainder that will be taken before maturity. Per Midnight, face value is
/// `credit - pendingFee`, so this adapter subtracts the remaining pendingFee and marks the result at
/// the loan token's price. Because Midnight is an orderbook with no on-chain spot price, the
/// pre-maturity discount is NOT applied here — pre-maturity this is an upper bound, and any
/// amortization toward face is the responsibility of the off-chain NAV layer. Unrealized bad debt
/// (a borrower underwater but not yet liquidated) is likewise not captured, matching how the
/// Morpho/Aave adapters do not predict liquidation outcomes.
contract MidnightLenderTvlAdapter {
    IMidnight public immutable midnight;
    bytes32 public immutable marketId;

    address public immutable loanToken;
    address public immutable baseToken;

    AggregatorV3Interface public immutable loanUsdFeed;
    AggregatorV3Interface public immutable baseUsdFeed;

    uint8 public immutable loanDecimals;
    uint8 public immutable baseDecimals;

    constructor(address _midnight, bytes32 _marketId, address _loanUsdFeed, address _baseUsdFeed, address _baseToken) {
        midnight = IMidnight(_midnight);
        marketId = _marketId;

        loanToken = IMidnight(_midnight).toMarket(_marketId).loanToken;
        baseToken = _baseToken;

        loanUsdFeed = AggregatorV3Interface(_loanUsdFeed);
        baseUsdFeed = AggregatorV3Interface(_baseUsdFeed);

        loanDecimals = ERC20(loanToken).decimals();
        baseDecimals = ERC20(_baseToken).decimals();
    }

    /// @dev position value in base terms
    function getUserTvl(address _user) external view returns (uint256 tvl) {
        tvl = _assetToBase(_liveCredit(_user), loanDecimals, loanUsdFeed);
    }

    /// @dev decomposed view for monitoring: raw live credit (loan-token units) and its base value
    function getUserPositionValues(address _user)
        external
        view
        returns (uint256 creditUnits, uint256 creditValueInBase)
    {
        creditUnits = _liveCredit(_user);
        creditValueInBase = _assetToBase(creditUnits, loanDecimals, loanUsdFeed);
    }

    function _liveCredit(address _user) internal view returns (uint256) {
        Market memory market = midnight.toMarket(marketId);
        (uint128 credit, uint128 remainingPendingFee,) = midnight.updatePositionView(market, marketId, _user);
        // face value = credit - pendingFee. Saturating subtraction is defensive; credit >= pendingFee always holds
        return credit > remainingPendingFee ? credit - remainingPendingFee : 0;
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
        (, int256 answer,,,) = feed.latestRoundData();
        require(answer > 0, "invalid price");

        uint8 feedDecimals = feed.decimals();
        uint256 price = uint256(answer);

        if (feedDecimals < 18) return price * (10 ** (18 - feedDecimals));
        if (feedDecimals > 18) return price / (10 ** (feedDecimals - 18));
        return price;
    }
}
