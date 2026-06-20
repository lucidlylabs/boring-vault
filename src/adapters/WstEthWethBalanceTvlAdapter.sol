// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

interface IPriceFeedLatestAnswer {
    function latestAnswer() external view returns (int256);
    function decimals() external view returns (uint8);
}

/// @title WstEthWethBalanceTvlAdapter
/// @notice Values a vault's IDLE (un-supplied) wstETH balance in WETH (18 dec).
/// @dev Mirrors WethUsdcMorphoBalanceAdapter._getMorphoCollateral exactly (same
///      wstETH/USD + ETH/USD `latestAnswer` Chainlink-compatible feeds, same
///      WETH-18 math) so the un-supplied dust is priced IDENTICALLY to the
///      Morpho-marked collateral. It reads `balanceOf(vault)` only — the
///      Morpho-supplied wstETH is already counted by the main carry adapter —
///      so summing both AUM rows on the vault does NOT double-count, and a sweep
///      that moves dust into Morpho just shifts value from this adapter to the
///      main one with no discontinuity.
///
///      INVARIANT: value = balanceOf * (wstETH/USD) / (ETH/USD). The two feed
///      decimal factors cancel ONLY when the feeds share `decimals()` — enforced
///      in the constructor — leaving a clean wstETH/ETH ratio (~1.2, monotone
///      growing with Lido staking ~2.5%/yr) scaling the 18-dec wstETH balance.
///
///      LIMITATION: the BGD wstETH/USD price-cap adapter exposes only
///      `latestAnswer()` (no `latestRoundData`/`updatedAt`), so this adapter
///      cannot detect a stale feed — same as the production main carry adapter.
contract WstEthWethBalanceTvlAdapter {
    error StaticCallFailed(string label);

    address public immutable WSTETH;
    address public immutable WSTETH_USD_CHAINLINK_FEED;
    address public immutable WETH_USD_CHAINLINK_FEED;

    constructor(address wsteth_, address wstethUsdFeed_, address wethUsdFeed_) {
        require(
            wsteth_ != address(0) && wstethUsdFeed_ != address(0) && wethUsdFeed_ != address(0),
            "zero address"
        );
        // The wstETH/USD and ETH/USD feeds MUST share decimals: getUserTvl divides
        // one by the other, and the decimal scales only cancel to a dimensionless
        // wstETH/ETH ratio when they are equal. Fail at deploy otherwise.
        require(
            IPriceFeedLatestAnswer(wstethUsdFeed_).decimals()
                == IPriceFeedLatestAnswer(wethUsdFeed_).decimals(),
            "feed decimals mismatch"
        );
        WSTETH = wsteth_;
        WSTETH_USD_CHAINLINK_FEED = wstethUsdFeed_;
        WETH_USD_CHAINLINK_FEED = wethUsdFeed_;
    }

    function _latestAnswer(address feed, string memory label) internal view returns (uint256) {
        (bool success, bytes memory data) = feed.staticcall(abi.encodeWithSignature("latestAnswer()"));
        if (!success) revert StaticCallFailed(label);
        int256 answer = abi.decode(data, (int256));
        // strictly positive: a non-positive price is a broken feed -> fail closed
        // (also guards the wethUsdPrice() denominator against div-by-zero).
        require(answer > 0, "non-positive price");
        return uint256(answer);
    }

    function wstEthUsdPrice() public view returns (uint256) {
        return _latestAnswer(WSTETH_USD_CHAINLINK_FEED, "wstethusd/latestAnswer");
    }

    function wethUsdPrice() public view returns (uint256) {
        return _latestAnswer(WETH_USD_CHAINLINK_FEED, "wethusd/latestAnswer");
    }

    /// @notice Idle (un-supplied) wstETH balance of `user`, valued in WETH (18 dec).
    function getUserTvl(address user) external view returns (uint256) {
        (bool success, bytes memory data) =
            WSTETH.staticcall(abi.encodeWithSignature("balanceOf(address)", user));
        if (!success) revert StaticCallFailed("wsteth/balanceOf");
        uint256 wstEthBalance = abi.decode(data, (uint256)); // [18 dec]

        uint256 balanceInUsd = (wstEthBalance * wstEthUsdPrice()) / 1e18; // [feed dec]
        return (balanceInUsd * 1e18) / wethUsdPrice(); // [18 dec WETH]
    }
}
