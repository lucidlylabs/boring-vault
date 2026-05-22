// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

/// @notice Standard interface for strategy-level TVL adapters.
/// @dev    The existing TvlAdapters (Erc20TvlAdapter, MorphoBlueTvlAdapter,
///         Univ3TvlAdapter, …) already match this signature — adopting this
///         interface lets the TvlRegistry treat all of them uniformly.
interface ITvlAdapter {
    /// @notice Returns the value of `user`'s position, denominated in the
    ///         adapter's base asset, in the base asset's decimals.
    function getUserTvl(address user) external view returns (uint256 tvl);
}
