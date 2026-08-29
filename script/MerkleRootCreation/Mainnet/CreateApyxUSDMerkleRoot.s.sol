// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

import "forge-std/Script.sol";

contract CreateApyxUSDMerkleRoot is Script, MerkleTreeHelper {
    
    address public constant APY_USD = 0x38EEb52F0771140d10c4E9A9a72349A329Fe8a6A;
    address public constant APX_USD = 0x98A878b1Cd98131B271883B390f68D2c90674665;
    address public constant CURVE_APXUSD_USDC_POOL = 0xE1B96555BbecA40E583BbB41a11C68Ca4706A414;
    address public constant CURVE_APXUSD_USDC_GAUGE = address(0); // no gauge for this factory pool
    address public constant PENDLE_APXUSD_MARKET = 0x50DCE085af29CABa28f7308beA57C4043757b491;
    bytes32 public constant MORPHO_APYUSD_USDC_MARKET_ID =
        0x9c28c8fa039a8df548a7f27adf062d751b0f2e9b9131931810535543adb23291;

    // ----- Deployed apyxUSD architecture (from deployments/addresses/Mainnet/ApyxUSD.json). ----
    address public constant APYX_USD_BORING_VAULT = 0x2505008ECe764719064E35AF7db5250cE2b0ff72;
    address public constant APYX_USD_MANAGER = 0xd5d867C86CaDdf1D3Bbfd04ae59F497a265Fd9D7;
    address public constant APYX_USD_ACCOUNTANT = 0x86474454f19957F286c59cf1ec7970EE9eA44F66;
    address public constant APYX_USD_DECODER_AND_SANITIZER = 0x0A0962164D43C564d9d53a63a836D6B027B183ac;

    function setUp() external {
        vm.createSelectFork("mainnet");
        setSourceChainName("mainnet");

        // Register the apyxUSD architecture addresses.
        setAddress(true, mainnet, "boringVault", APYX_USD_BORING_VAULT);
        setAddress(true, mainnet, "managerAddress", APYX_USD_MANAGER);
        setAddress(true, mainnet, "accountantAddress", APYX_USD_ACCOUNTANT);
        setAddress(true, mainnet, "rawDataDecoderAndSanitizer", APYX_USD_DECODER_AND_SANITIZER);

        // Register Apyx ecosystem addresses that are not in ChainValues.sol.
        setAddress(true, mainnet, "apyUSD", APY_USD);
        setAddress(true, mainnet, "apxUSD", APX_USD);
        setAddress(true, mainnet, "curve_apxUSD_USDC_pool", CURVE_APXUSD_USDC_POOL);
        setAddress(true, mainnet, "pendle_apxUSD_market", PENDLE_APXUSD_MARKET);
        setValue(true, mainnet, "morpho_apyUSD_USDC_marketId", MORPHO_APYUSD_USDC_MARKET_ID);
    }

    function run() external {
        require(APY_USD != address(0), "APY_USD not set");
        require(APX_USD != address(0), "APX_USD not set");
        require(CURVE_APXUSD_USDC_POOL != address(0), "Curve pool not set");
        require(PENDLE_APXUSD_MARKET != address(0), "Pendle market not set");
        require(MORPHO_APYUSD_USDC_MARKET_ID != bytes32(0), "Morpho marketId not set");
        require(APYX_USD_BORING_VAULT != address(0), "BoringVault not set");
        require(APYX_USD_DECODER_AND_SANITIZER != address(0), "Decoder not set");

        ManageLeaf[] memory leafs = new ManageLeaf[](256);
        _addLeafs(leafs);

        bytes32[][] memory tree = _generateMerkleTree(leafs);
        string memory filePath = "./leafs/Mainnet/ApyxUSDStrategistLeafs.json";
        _generateLeafs(filePath, leafs, tree[tree.length - 1][0], tree);
    }

    function _addLeafs(ManageLeaf[] memory leafs) internal {
        // (0) Accountant fee claiming — updateExchangeRate + claimFees in USDC.
        ERC20[] memory feeAssets = new ERC20[](1);
        feeAssets[0] = getERC20(sourceChain, "USDC");
        _addLeafsForFeeClaiming(leafs, getAddress(sourceChain, "accountantAddress"), feeAssets, false);

        // (1) Mint apyUSD — ERC4626 deposit/withdraw/mint/redeem on the apyUSD wrapper.
        _addERC4626Leafs(leafs, ERC4626(getAddress(sourceChain, "apyUSD")));

        // (2) Pendle LP on the apxUSD market — SY/PT/YT + addLiquidityDualSyAndPt + swaps.
        _addPendleMarketLeafs(leafs, getAddress(sourceChain, "pendle_apxUSD_market"), false);

        // (3) Curve apxUSD/USDC LP — stable-ng factory pool; 2 coins; no gauge unless set.
        _addCurveLeafs(
            leafs,
            getAddress(sourceChain, "curve_apxUSD_USDC_pool"),
            2,
            CURVE_APXUSD_USDC_GAUGE
        );

        // (4) Morpho Blue — supplyCollateral (apyUSD), borrow USDC, repay, withdraw.
        _addMorphoBlueCollateralLeafs(leafs, getBytes32(sourceChain, "morpho_apyUSD_USDC_marketId"));
    }
}
