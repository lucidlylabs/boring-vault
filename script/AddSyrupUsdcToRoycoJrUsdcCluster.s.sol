// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

import "forge-std/Script.sol";

// source .env && forge script script/AddSyrupUsdcToRoycoJrUsdcCluster.s.sol:AddSyrupUsdcToRoycoJrUsdcClusterScript \
//   --rpc-url $MAINNET_RPC_URL --broadcast --slow

contract AddSyrupUsdcToRoycoJrUsdcClusterScript is Script {
    AccountantWithRateProviders public constant accountant =
        AccountantWithRateProviders(0x0142d7E0787498c523c5E21c5BeCe9afDD82C6a3);
    TellerWithMultiAssetSupport public constant teller =
        TellerWithMultiAssetSupport(0x8C87d801B6CA569a73D9428351415afAeC293E28);

    ERC20 public constant SYRUP_USDC = ERC20(0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b);
    address public constant SYRUP_USDC_RATE_PROVIDER = 0xe5a39E4E636B874006087f50cAF2E1c4D5823fb3;

    function run() external {
        require(SYRUP_USDC_RATE_PROVIDER != address(0), "rate provider not set");

        uint256 pk = vm.envUint("DEPLOYER01");
        vm.startBroadcast(pk);

        accountant.setRateProviderData({
            asset: SYRUP_USDC, isPeggedToBase: false, rateProvider: SYRUP_USDC_RATE_PROVIDER
        });

        teller.updateAssetData({asset: SYRUP_USDC, allowDeposits: true, allowWithdraws: false, sharePremium: 0});

        vm.stopBroadcast();
    }
}
