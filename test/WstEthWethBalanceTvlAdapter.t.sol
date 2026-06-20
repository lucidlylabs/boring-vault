// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {WstEthWethBalanceTvlAdapter} from "src/adapters/WstEthWethBalanceTvlAdapter.sol";

interface IFeed {
    function latestAnswer() external view returns (int256);
    function decimals() external view returns (uint8);
}

interface IERC20b {
    function balanceOf(address) external view returns (uint256);
}

interface IWstEth {
    function stEthPerToken() external view returns (uint256); // wstETH -> stETH rate, 1e18
}

// minimal feed with a configurable decimals() to test the ctor invariant
contract MockDecimalsFeed {
    uint8 public decimals;

    constructor(uint8 d) {
        decimals = d;
    }

    function latestAnswer() external pure returns (int256) {
        return 1e8;
    }
}

/// Invariant / spec suite for the ETH-carry idle-wstETH NAV adapter.
/// Run: forge test --match-contract WstEthWethBalanceTvlAdapterTest -vv
/// (the growth test forks historical blocks -> needs an archive mainnet RPC).
contract WstEthWethBalanceTvlAdapterTest is Test {
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant WSTETH_USD = 0xe1D97bF61901B075E9626c8A2340a7De385861Ef; // BGD WstETHPriceCapAdapter
    address constant ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // Chainlink ETH/USD
    address constant ETH_CARRY_VAULT = 0x5373690c930553648f0aaA2e53B51f0C59290B7d;
    address constant USER = address(0xBEEF);

    WstEthWethBalanceTvlAdapter adapter;

    function setUp() public {
        vm.createSelectFork("mainnet");
        adapter = new WstEthWethBalanceTvlAdapter(WSTETH, WSTETH_USD, ETH_USD);
    }

    // wstETH/ETH in 18-dec, straight from the two feeds the adapter uses.
    function _ratio18() internal view returns (uint256) {
        return adapter.wstEthUsdPrice() * 1e18 / adapter.wethUsdPrice();
    }

    function _setBalance(uint256 bal) internal {
        vm.mockCall(WSTETH, abi.encodeWithSignature("balanceOf(address)", USER), abi.encode(bal));
    }

    // SPEC: result is WETH-denominated, NOT USDC. getUserTvl(1 wstETH) == wstETH/ETH
    //       ratio (~1.2 WETH), never a USD figure (~4000).
    function test_resultIsWethTerms_notUsdc() public {
        _setBalance(1e18);
        uint256 tvl = adapter.getUserTvl(USER);
        assertEq(tvl, _ratio18(), "1 wstETH tvl must equal the wstETH/ETH ratio");
        assertLt(tvl, 10e18, "must be WETH terms (~1.2), not USD terms (~4000)");
    }

    // SPEC + INVARIANT: wstETH/ETH must sit in a sane band -- never 0.3, never 50.
    //       lower 1.10 (already grown well past 1.0), upper 1.35 (years of ~2.5%/yr
    //       headroom from the current ~1.20).
    function test_ratio_inSaneBand() public view {
        uint256 r = _ratio18();
        assertGe(r, 110e16, "wstETH/ETH must be >= 1.10");
        assertLe(r, 135e16, "wstETH/ETH must be <= 1.35");
    }

    // INVARIANT: wstETH is wrapped staked ETH -> strictly worth > 1 ETH.
    function test_ratio_aboveOne() public view {
        assertGt(_ratio18(), 1e18, "wstETH must be worth > 1 ETH");
    }

    // SPEC: the adapter's value GROWS over time (~2.5%/yr staking yield). The
    //       wstETH/ETH ratio is driven by Lido's wstETH->stETH rate
    //       (stEthPerToken), which is monotone non-decreasing. wstETH (0x7f39..)
    //       exists at every historical block, so reading it at two blocks is
    //       robust (unlike the BGD feed, which Aave periodically redeploys).
    function test_stakingRateGrowsOverTime() public {
        vm.createSelectFork("mainnet", 20_000_000); // ~Jun 2024
        uint256 early = IWstEth(WSTETH).stEthPerToken();

        vm.createSelectFork("mainnet", 22_000_000); // ~Mar 2025
        uint256 late = IWstEth(WSTETH).stEthPerToken();

        assertGt(late, early, "wstETH staking rate must grow over time");
        assertLt(late, early * 110 / 100, "growth must be gradual (<10% over ~9 months)");
    }

    // SPEC: the adapter's wstETH/ETH ratio tracks the live Lido staking rate
    //       (within a tight band for the cap + stETH/ETH peg deviation). Combined
    //       with monotone stEthPerToken above, this is the ~2.5%/yr growth proof,
    //       and is single-fork / deterministic.
    function test_tracksLidoStakingRate() public view {
        uint256 lidoRate = IWstEth(WSTETH).stEthPerToken(); // wstETH/stETH, 1e18
        assertApproxEqRel(_ratio18(), lidoRate, 2e16, "ratio must track Lido stEthPerToken within 2%");
    }

    // INVARIANT: TVL is linear in balance and does not overflow at scale.
    function test_linearInBalance() public {
        _setBalance(1e18);
        uint256 one = adapter.getUserTvl(USER);
        _setBalance(1_000_000e18);
        uint256 million = adapter.getUserTvl(USER);
        assertApproxEqRel(million, one * 1_000_000, 1e9, "must scale linearly");
    }

    // INVARIANT: zero balance -> zero TVL, no revert, no dust.
    function test_zeroBalance() public {
        _setBalance(0);
        assertEq(adapter.getUserTvl(USER), 0);
    }

    // INVARIANT: exact equality with the hand-computed formula (no hidden scaling).
    function test_matchesManualFormula() public {
        _setBalance(3e18);
        uint256 wstUsd = uint256(IFeed(WSTETH_USD).latestAnswer());
        uint256 ethUsd = uint256(IFeed(ETH_USD).latestAnswer());
        uint256 expected = (3e18 * wstUsd / 1e18) * 1e18 / ethUsd;
        assertEq(adapter.getUserTvl(USER), expected);
    }

    // INVARIANT: the decimal-cancellation assumption holds (both feeds share decimals).
    function test_feedDecimalsEqual() public view {
        assertEq(IFeed(WSTETH_USD).decimals(), IFeed(ETH_USD).decimals());
    }

    // INVARIANT: ctor fails closed if the feed decimals ever differ.
    function test_ctorRejectsDecimalsMismatch() public {
        address fake18 = address(new MockDecimalsFeed(18));
        vm.expectRevert(bytes("feed decimals mismatch"));
        new WstEthWethBalanceTvlAdapter(WSTETH, fake18, ETH_USD);
    }

    // INVARIANT: ctor rejects zero addresses.
    function test_ctorRejectsZeroAddress() public {
        vm.expectRevert(bytes("zero address"));
        new WstEthWethBalanceTvlAdapter(address(0), WSTETH_USD, ETH_USD);
    }

    // SPEC: the live vault read never reverts and the implied per-wstETH ratio is sane.
    function test_liveVault_sane() public view {
        uint256 tvl = adapter.getUserTvl(ETH_CARRY_VAULT);
        uint256 bal = IERC20b(WSTETH).balanceOf(ETH_CARRY_VAULT);
        if (bal == 0) {
            assertEq(tvl, 0);
            return;
        }
        uint256 ratio = tvl * 1e18 / bal;
        assertGe(ratio, 110e16);
        assertLe(ratio, 135e16);
    }
}
