// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Deployer} from "src/helper/Deployer.sol";
import {GenericRateProviderWithDecimalScaling} from "src/helper/GenericRateProviderWithDecimalScaling.sol";
import {Script, console} from "forge-std/Script.sol";

// Wraps the LucidlyChainlinkOracleV1_1 syrupUSDC/USDC feed as an IRateProvider
// (calls `latestAnswer()` and returns the int256 as a uint256, no decimal scaling
// since the oracle and the accountant both work in 6 decimals).
//
//   source .env && forge script script/DeploySyrupUsdcUsdcRateProvider.s.sol:DeploySyrupUsdcUsdcRateProviderScript \
//     --rpc-url $MAINNET_RPC_URL --broadcast --verify --etherscan-api-key $ETHERSCAN_KEY

contract DeploySyrupUsdcUsdcRateProviderScript is Script {
    Deployer constant DEPLOYER = Deployer(0x771263e3Bc6aCDa5aE388A3F8A0c2dd7A17275FC);

    address constant ORACLE = 0xF4B8A20c2a94976837AE727e9e9567C01C061426;
    bytes4 constant LATEST_ANSWER_SELECTOR = 0x50d25bcd;

    string constant DEPLOYMENT_NAME = "syrupUSDC/USDC GenericRateProvider V0.1";

    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER01"));

        bytes memory creationCode = type(GenericRateProviderWithDecimalScaling).creationCode;
        bytes memory constructorArgs = abi.encode(
            GenericRateProviderWithDecimalScaling.ConstructorArgs({
                target: ORACLE,
                selector: LATEST_ANSWER_SELECTOR,
                staticArgument0: bytes32(0),
                staticArgument1: bytes32(0),
                staticArgument2: bytes32(0),
                staticArgument3: bytes32(0),
                staticArgument4: bytes32(0),
                staticArgument5: bytes32(0),
                staticArgument6: bytes32(0),
                staticArgument7: bytes32(0),
                signed: true,
                inputDecimals: 6,
                outputDecimals: 6
            })
        );

        address deployed = DEPLOYER.deployContract(DEPLOYMENT_NAME, creationCode, constructorArgs, 0);
        console.log("Deployed:", DEPLOYMENT_NAME, deployed);

        vm.stopBroadcast();
    }
}
