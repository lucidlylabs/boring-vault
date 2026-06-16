// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {MorphoFlashLoanAdapter} from "src/base/Roles/MorphoFlashLoan/MorphoFlashLoanAdapter.sol";

import "forge-std/Script.sol";

// The MorphoFlashLoanAdapter binds vault + manager as immutables and enforces msg.sender == vault, so it is
// not shareable across vaults (each cluster has its own). Direct `new` with the owner key, matching how this
// cluster's decoder and TVL adapters were deployed.
contract DeployLoopOptimiserClusterFlashLoanAdapter is Script {
    address internal constant MORPHO_BLUE = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address internal constant BORING_VAULT = 0x31aCffb26E80A319018cbd049CeA3389635dFc41;
    address internal constant MANAGER = 0x7141A06771fc62f9F5aa714CeD79EA7dc8Bce64F;

    function run() external {
        vm.createSelectFork("mainnet");
        vm.startBroadcast(vm.envUint("LOOP_OPTIMISER_OWNER"));

        MorphoFlashLoanAdapter adapter = new MorphoFlashLoanAdapter(MORPHO_BLUE, BORING_VAULT, MANAGER);

        vm.stopBroadcast();

        console.log("MorphoFlashLoanAdapter (loop cluster):", address(adapter));
        console.log("  vault  :", address(adapter.vault()));
        console.log("  manager:", address(adapter.manager()));
    }
}
