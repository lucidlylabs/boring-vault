// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

import {Test} from "@forge-std/Test.sol";

contract RoycoJrUsdcSyrupUsdcDepositTest is Test {
    address constant BORING_VAULT = 0x71861827Aa95cA48148bdA0b40BC740d1c421070;
    AccountantWithRateProviders constant ACCOUNTANT =
        AccountantWithRateProviders(0x0142d7E0787498c523c5E21c5BeCe9afDD82C6a3);
    TellerWithMultiAssetSupport constant TELLER =
        TellerWithMultiAssetSupport(0x8C87d801B6CA569a73D9428351415afAeC293E28);
    ERC20 constant SYRUP_USDC = ERC20(0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b);
    address constant SYRUP_USDC_RATE_PROVIDER = 0xe5a39E4E636B874006087f50cAF2E1c4D5823fb3;
    address constant SYRUP_USDC_HOLDER = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }

    function test_accountantRateProviderWired() external view {
        (bool isPegged, IRateProvider rp) = ACCOUNTANT.rateProviderData(SYRUP_USDC);
        assertEq(isPegged, false, "syrupUSDC should not be pegged to base");
        assertEq(address(rp), SYRUP_USDC_RATE_PROVIDER, "rate provider mismatch");
    }

    function test_tellerAssetDataAllowsDeposit() external view {
        (bool allowDeposits, bool allowWithdraws, uint16 sharePremium) = TELLER.assetData(SYRUP_USDC);
        assertEq(allowDeposits, true, "deposits should be enabled");
        assertEq(allowWithdraws, false, "withdraws should be disabled");
        assertEq(sharePremium, 0, "no share premium expected");
    }

    function test_rateProviderReturnsSensiblePrice() external view {
        uint256 rate = IRateProvider(SYRUP_USDC_RATE_PROVIDER).getRate();
        // syrupUSDC is a yield-bearing wrapper over USDC, so 1 syrupUSDC >= 1 USDC.
        // 2x is a sanity ceiling; the price would have to do something pathological to exceed it.
        assertGt(rate, 1e6, "rate must be > 1 USDC per syrupUSDC");
        assertLt(rate, 2e6, "rate sanity ceiling");
    }

    function test_depositSyrupUsdcMintsShares() external {
        uint256 depositAmount = 100 * 1e6;

        uint256 expectedRate = IRateProvider(SYRUP_USDC_RATE_PROVIDER).getRate();
        // shares = depositAmount * ONE_SHARE / rateInQuote = depositAmount * 1e6 / (1e6 * exchangeRate / rate)
        // exchangeRate at startup = 1e6, so shares ≈ depositAmount * rate / 1e6
        uint256 expectedShares = depositAmount * expectedRate / 1e6;

        uint256 vaultBalanceBefore = SYRUP_USDC.balanceOf(BORING_VAULT);

        vm.startPrank(SYRUP_USDC_HOLDER);
        SYRUP_USDC.approve(address(BORING_VAULT), depositAmount);
        uint256 shares = TELLER.deposit(SYRUP_USDC, depositAmount, 0);
        vm.stopPrank();

        // 1% tolerance to absorb any exchangeRate drift since deployment.
        assertApproxEqRel(shares, expectedShares, 0.01e18, "shares minted off expected");
        assertEq(ERC20(BORING_VAULT).balanceOf(SYRUP_USDC_HOLDER), shares, "depositor share balance wrong");
        assertEq(
            SYRUP_USDC.balanceOf(BORING_VAULT) - vaultBalanceBefore, depositAmount, "vault did not receive syrupUSDC"
        );
    }
}
