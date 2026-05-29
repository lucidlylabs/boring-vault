// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BoringVault} from "src/base/BoringVault.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {MidnightFullDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/MidnightFullDecoderAndSanitizer.sol";
import {MidnightDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/MidnightDecoderAndSanitizer.sol";
import {MidnightLenderTvlAdapter} from "src/adapters/MidnightLenderTvlAdapter.sol";
import {MockERC20} from "src/helper/MockERC20.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {Market, Offer, CollateralParams} from "../../lib/midnight/src/interfaces/IMidnight.sol";

import {Test, console} from "@forge-std/Test.sol";

/// @notice minimal stand-in for midnight
contract MockMidnight {
    mapping(bytes32 => Market) internal markets;
    mapping(bytes32 => mapping(address => uint128)) public credit;
    mapping(bytes32 => mapping(address => uint128)) public pendingFeeOf;

    // price in bps that a taker pays per unit of credit (e.g. 9500 = 5% discount => fixed yield)
    uint256 public immutable priceBps;

    constructor(uint256 _priceBps) {
        priceBps = _priceBps;
    }

    function createMarket(Market calldata m) external returns (bytes32 id) {
        id = toId(m);
        markets[id] = m;
    }

    function toId(Market memory m) public pure returns (bytes32) {
        return keccak256(abi.encode(m));
    }

    function toMarket(bytes32 id) external view returns (Market memory) {
        return markets[id];
    }

    /// @dev simplified: taker buys `units` of credit, paying `units * priceBps / 10000` loan tokens
    function take(
        Offer calldata offer,
        bytes calldata, /* ratifierData */
        uint256 units,
        address taker,
        address, /* receiverIfTakerIsSeller */
        address, /* takerCallback */
        bytes calldata /* takerCallbackData */
    )
        external
        returns (uint256 buyerAssets, uint256 sellerAssets)
    {
        bytes32 id = toId(offer.market);
        buyerAssets = (units * priceBps) / 10_000;
        sellerAssets = buyerAssets;
        credit[id][taker] += uint128(units);
        ERC20(offer.market.loanToken).transferFrom(msg.sender, address(this), buyerAssets);
    }

    function withdraw(Market calldata market, uint256 units, address onBehalf, address receiver) external {
        bytes32 id = toId(market);
        credit[id][onBehalf] -= uint128(units);
        ERC20(market.loanToken).transfer(receiver, units);
    }

    function updatePositionView(
        Market calldata,
        /* market */
        bytes32 id,
        address user
    )
        external
        view
        returns (uint128, uint128, uint128)
    {
        return (credit[id][user], pendingFeeOf[id][user], 0);
    }

    // test helpers (not part of real Midnight) to set position state directly for adapter unit tests
    function setCredit(bytes32 id, address user, uint128 amount) external {
        credit[id][user] = amount;
    }

    function setPendingFee(bytes32 id, address user, uint128 amount) external {
        pendingFeeOf[id][user] = amount;
    }
}

contract MockChainlinkFeed {
    int256 public immutable answer;
    uint8 public immutable dec;

    constructor(int256 _answer, uint8 _dec) {
        answer = _answer;
        dec = _dec;
    }

    function decimals() external view returns (uint8) {
        return dec;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, answer, 0, block.timestamp, 0);
    }
}

contract MidnightIntegrationTest is Test, MerkleTreeHelper {
    ManagerWithMerkleVerification public manager;
    BoringVault public boringVault;
    address public rawDataDecoderAndSanitizer;
    RolesAuthority public rolesAuthority;

    MockMidnight public midnight;
    MockERC20 public usdc; // loan token == base token
    MockChainlinkFeed public feed;
    MidnightLenderTvlAdapter public tvlAdapter;

    bytes32 public marketId;
    address public collateralToken = address(0xC011A7E5A1);
    address public collateralOracle = address(0x06AC1E0000);

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 2;
    uint8 public constant MANGER_INTERNAL_ROLE = 3;
    uint8 public constant ADMIN_ROLE = 4;
    uint8 public constant BORING_VAULT_ROLE = 5;
    uint8 public constant BALANCER_VAULT_ROLE = 6;

    function setUp() external {
        setSourceChainName("mainnet");

        usdc = new MockERC20("USD Coin", "USDC", 6);
        midnight = new MockMidnight(9_500); // 5% discount
        feed = new MockChainlinkFeed(1e8, 8);

        // build a single-collateral market and register it in the mock
        Market memory market = _market();
        marketId = midnight.createMarket(market);

        boringVault = new BoringVault(address(this), "Boring Vault", "BV", 18);
        manager =
            new ManagerWithMerkleVerification(address(this), address(boringVault), getAddress(sourceChain, "vault"));
        rawDataDecoderAndSanitizer = address(new MidnightFullDecoderAndSanitizer());

        tvlAdapter =
            new MidnightLenderTvlAdapter(address(midnight), marketId, address(feed), address(feed), address(usdc));

        setAddress(true, sourceChain, "boringVault", address(boringVault));
        setAddress(true, sourceChain, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizer);
        setAddress(true, sourceChain, "manager", address(manager));
        setAddress(true, sourceChain, "managerAddress", address(manager));
        setAddress(true, sourceChain, "midnight", address(midnight));

        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        boringVault.setAuthority(rolesAuthority);
        manager.setAuthority(rolesAuthority);

        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(boringVault),
            bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)"))),
            true
        );
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(boringVault),
            bytes4(keccak256(abi.encodePacked("manage(address[],bytes[],uint256[])"))),
            true
        );
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(manager),
            ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
            true
        );
        rolesAuthority.setRoleCapability(
            MANGER_INTERNAL_ROLE,
            address(manager),
            ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
            true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(manager), ManagerWithMerkleVerification.setManageRoot.selector, true
        );

        rolesAuthority.setUserRole(address(this), STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(address(manager), MANGER_INTERNAL_ROLE, true);
        rolesAuthority.setUserRole(address(this), ADMIN_ROLE, true);
        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);

        // fund the vault and seed the mock with redemption liquidity
        deal(address(usdc), address(boringVault), 1_000e6);
        deal(address(usdc), address(midnight), 1_000e6);
    }

    function testMidnightLendIntegration() external {
        ManageLeaf[] memory leafs = _buildLeafs();
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);

        // ---- call a: approve + take (lend 100 units of credit) ----
        ManageLeaf[] memory used = new ManageLeaf[](2);
        used[0] = leafs[0]; // approve
        used[1] = leafs[1]; // take
        bytes32[][] memory proofs = _getProofsUsingTree(used, manageTree);

        address[] memory targets = new address[](2);
        targets[0] = address(usdc);
        targets[1] = address(midnight);

        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSignature("approve(address,uint256)", address(midnight), type(uint256).max);
        targetData[1] = abi.encodeWithSelector(
            MockMidnight.take.selector,
            _offer(),
            hex"", // ratifierData
            uint256(100e6), // units
            address(boringVault), // taker
            address(boringVault), // receiverIfTakerIsSeller
            address(0), // takerCallback (must be zero)
            hex"" // takerCallbackData (must be empty)
        );

        address[] memory dms = new address[](2);
        dms[0] = rawDataDecoderAndSanitizer;
        dms[1] = rawDataDecoderAndSanitizer;

        manager.manageVaultWithMerkleVerification(proofs, dms, targets, targetData, new uint256[](2));

        // vault paid 95 USDC for 100 credit units
        assertEq(usdc.balanceOf(address(boringVault)), 1_000e6 - 95e6, "vault paid discounted price");
        assertEq(midnight.credit(marketId, address(boringVault)), 100e6, "vault holds 100 credit units");

        // tvl adapter marks credit at face (100 USDC), per documented upper-bound behavior
        assertEq(tvlAdapter.getUserTvl(address(boringVault)), 100e6, "tvl marks credit at face");

        // ---- call b: withdraw (redeem 40 units) ----
        ManageLeaf[] memory used2 = new ManageLeaf[](1);
        used2[0] = leafs[2]; // withdraw
        bytes32[][] memory proofs2 = _getProofsUsingTree(used2, manageTree);

        address[] memory targets2 = new address[](1);
        targets2[0] = address(midnight);
        bytes[] memory targetData2 = new bytes[](1);
        targetData2[0] = abi.encodeWithSelector(
            MockMidnight.withdraw.selector, _market(), uint256(40e6), address(boringVault), address(boringVault)
        );
        address[] memory dms2 = new address[](1);
        dms2[0] = rawDataDecoderAndSanitizer;

        manager.manageVaultWithMerkleVerification(proofs2, dms2, targets2, targetData2, new uint256[](1));

        assertEq(midnight.credit(marketId, address(boringVault)), 60e6, "credit reduced after withdraw");
        assertEq(usdc.balanceOf(address(boringVault)), 1_000e6 - 95e6 + 40e6, "vault received redeemed units");
        assertEq(tvlAdapter.getUserTvl(address(boringVault)), 60e6, "tvl tracks remaining credit");
    }

    function testMidnightTakerCallbackReverts() external {
        ManageLeaf[] memory leafs = _buildLeafs();
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);

        ManageLeaf[] memory used = new ManageLeaf[](2);
        used[0] = leafs[0];
        used[1] = leafs[1];
        bytes32[][] memory proofs = _getProofsUsingTree(used, manageTree);

        address[] memory targets = new address[](2);
        targets[0] = address(usdc);
        targets[1] = address(midnight);

        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSignature("approve(address,uint256)", address(midnight), type(uint256).max);
        // non-empty taker callback data must be rejected by the decoder
        targetData[1] = abi.encodeWithSelector(
            MockMidnight.take.selector,
            _offer(),
            hex"",
            uint256(100e6),
            address(boringVault),
            address(boringVault),
            address(0),
            hex"DEAD"
        );

        address[] memory dms = new address[](2);
        dms[0] = rawDataDecoderAndSanitizer;
        dms[1] = rawDataDecoderAndSanitizer;

        vm.expectRevert(
            abi.encodeWithSelector(
                MidnightDecoderAndSanitizer.MidnightDecoderAndSanitizer__TakerCallbackNotSupported.selector
            )
        );
        manager.manageVaultWithMerkleVerification(proofs, dms, targets, targetData, new uint256[](2));
    }

    function testMidnightTamperedReceiverReverts() external {
        ManageLeaf[] memory leafs = _buildLeafs();
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);

        ManageLeaf[] memory used = new ManageLeaf[](2);
        used[0] = leafs[0];
        used[1] = leafs[1];
        bytes32[][] memory proofs = _getProofsUsingTree(used, manageTree);

        address[] memory targets = new address[](2);
        targets[0] = address(usdc);
        targets[1] = address(midnight);

        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSignature("approve(address,uint256)", address(midnight), type(uint256).max);
        // point receiverIfTakerIsSeller at an attacker: the decoder returns
        // it, the leaf pins the vault, so the merkle hash no longer matches
        // and verification fails
        targetData[1] = abi.encodeWithSelector(
            MockMidnight.take.selector,
            _offer(),
            hex"",
            uint256(100e6),
            address(boringVault),
            address(0xBAD),
            address(0),
            hex""
        );

        address[] memory dms = new address[](2);
        dms[0] = rawDataDecoderAndSanitizer;
        dms[1] = rawDataDecoderAndSanitizer;

        vm.expectRevert(
            abi.encodeWithSelector(
                ManagerWithMerkleVerification.ManagerWithMerkleVerification__FailedToVerifyManageProof.selector,
                targets[1],
                targetData[1],
                0
            )
        );
        manager.manageVaultWithMerkleVerification(proofs, dms, targets, targetData, new uint256[](2));
    }

    function testMidnightBuyOfferReverts() external {
        ManageLeaf[] memory leafs = _buildLeafs();
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);

        ManageLeaf[] memory used = new ManageLeaf[](2);
        used[0] = leafs[0];
        used[1] = leafs[1];
        bytes32[][] memory proofs = _getProofsUsingTree(used, manageTree);

        address[] memory targets = new address[](2);
        targets[0] = address(usdc);
        targets[1] = address(midnight);

        // flip offer.buy to true: this would make the vault a borrower, the decoder must reject it
        Offer memory buyOffer = _offer();
        buyOffer.buy = true;

        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSignature("approve(address,uint256)", address(midnight), type(uint256).max);
        targetData[1] = abi.encodeWithSelector(
            MockMidnight.take.selector,
            buyOffer,
            hex"",
            uint256(100e6),
            address(boringVault),
            address(boringVault),
            address(0),
            hex""
        );

        address[] memory dms = new address[](2);
        dms[0] = rawDataDecoderAndSanitizer;
        dms[1] = rawDataDecoderAndSanitizer;

        vm.expectRevert(
            abi.encodeWithSelector(MidnightDecoderAndSanitizer.MidnightDecoderAndSanitizer__BorrowNotSupported.selector)
        );
        manager.manageVaultWithMerkleVerification(proofs, dms, targets, targetData, new uint256[](2));
    }

    function testMidnightTvlDeductsPendingFee() external {
        // adapter unit test: face value must be credit - pendingFee
        midnight.setCredit(marketId, address(boringVault), 100e6);
        assertEq(tvlAdapter.getUserTvl(address(boringVault)), 100e6, "no fee => face == credit");

        midnight.setPendingFee(marketId, address(boringVault), 5e6);
        assertEq(tvlAdapter.getUserTvl(address(boringVault)), 95e6, "tvl nets remaining pending fee");
    }

    function testMidnightTvlNonIdentityDecimalsAndPrice() external {
        // base != loan: loan = USDC (6dp, $1), base = WETH (18dp, 2000 USD)
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        MockChainlinkFeed ethFeed = new MockChainlinkFeed(2000e8, 8);
        MidnightLenderTvlAdapter adapter =
            new MidnightLenderTvlAdapter(address(midnight), marketId, address(feed), address(ethFeed), address(weth));

        midnight.setCredit(marketId, address(boringVault), 100e6); // 100 USDC of credit
        // 100 USDC / $2000 = 0.05 WETH
        assertEq(adapter.getUserTvl(address(boringVault)), 0.05e18, "scales across decimals and price");
    }

    function testMidnightMultiCollateralTakeAndOrderingRevert() external {
        // n=2 market exercises the _packMarket loop and leaf ordering,
        // (only N=1 is covered elsewhere)
        address c0Token = collateralToken; // 0xC011A7E5A1
        address c1Token = address(0xC011A7E5A2); // sorted ascending: c1 > c0
        address c0Oracle = collateralOracle;
        address c1Oracle = address(0x06AC1E0001);

        ManageLeaf[] memory leafs = new ManageLeaf[](8);
        address[] memory tokens = new address[](2);
        address[] memory oracles = new address[](2);
        tokens[0] = c0Token;
        tokens[1] = c1Token;
        oracles[0] = c0Oracle;
        oracles[1] = c1Oracle;
        _addMidnightLendLeafs(leafs, address(usdc), tokens, oracles, address(0), address(0));

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);

        ManageLeaf[] memory used = new ManageLeaf[](2);
        used[0] = leafs[0]; // approve
        used[1] = leafs[1]; // take
        bytes32[][] memory proofs = _getProofsUsingTree(used, manageTree);

        address[] memory targets = new address[](2);
        targets[0] = address(usdc);
        targets[1] = address(midnight);
        address[] memory dms = new address[](2);
        dms[0] = rawDataDecoderAndSanitizer;
        dms[1] = rawDataDecoderAndSanitizer;

        // positive: sorted [c0, c1] matches the leaf
        Offer memory offer = _offerWithCollaterals(tokens, oracles);
        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSignature("approve(address,uint256)", address(midnight), type(uint256).max);
        targetData[1] = _encodeTake(offer);
        manager.manageVaultWithMerkleVerification(proofs, dms, targets, targetData, new uint256[](2));
        assertEq(midnight.credit(midnight.toId(offer.market), address(boringVault)), 100e6, "multi-collateral lend ok");

        // negative: swap the two collateral pairs
        // -> decoder packs a different address order -> merkle fail
        address[] memory swT = new address[](2);
        address[] memory swO = new address[](2);
        swT[0] = c1Token;
        swT[1] = c0Token;
        swO[0] = c1Oracle;
        swO[1] = c0Oracle;
        Offer memory swapped = _offerWithCollaterals(swT, swO);
        bytes[] memory badData = new bytes[](2);
        badData[0] = targetData[0];
        badData[1] = _encodeTake(swapped);
        vm.expectRevert(
            abi.encodeWithSelector(
                ManagerWithMerkleVerification.ManagerWithMerkleVerification__FailedToVerifyManageProof.selector,
                targets[1],
                badData[1],
                0
            )
        );
        manager.manageVaultWithMerkleVerification(proofs, dms, targets, badData, new uint256[](2));
    }

    function testMidnightTamperedWithdrawOnBehalfReverts() external {
        ManageLeaf[] memory leafs = _buildLeafs();
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);

        ManageLeaf[] memory used = new ManageLeaf[](1);
        used[0] = leafs[2]; // withdraw
        bytes32[][] memory proofs = _getProofsUsingTree(used, manageTree);

        address[] memory targets = new address[](1);
        targets[0] = address(midnight);
        bytes[] memory targetData = new bytes[](1);
        // onBehalf tampered to an attacker; leaf pins it to the vault,
        // so merkle verification fails
        targetData[0] = abi.encodeWithSelector(
            MockMidnight.withdraw.selector, _market(), uint256(10e6), address(0xBAD), address(boringVault)
        );
        address[] memory dms = new address[](1);
        dms[0] = rawDataDecoderAndSanitizer;

        vm.expectRevert(
            abi.encodeWithSelector(
                ManagerWithMerkleVerification.ManagerWithMerkleVerification__FailedToVerifyManageProof.selector,
                targets[0],
                targetData[0],
                0
            )
        );
        manager.manageVaultWithMerkleVerification(proofs, dms, targets, targetData, new uint256[](1));
    }

    // helpers

    function _buildLeafs() internal returns (ManageLeaf[] memory leafs) {
        leafs = new ManageLeaf[](8);
        address[] memory tokens = new address[](1);
        address[] memory oracles = new address[](1);
        tokens[0] = collateralToken;
        oracles[0] = collateralOracle;
        _addMidnightLendLeafs(leafs, address(usdc), tokens, oracles, address(0), address(0));
    }

    function _market() internal view returns (Market memory market) {
        CollateralParams[] memory cp = new CollateralParams[](1);
        cp[0] = CollateralParams({token: collateralToken, lltv: 0.86e18, maxLif: 1.15e18, oracle: collateralOracle});
        market = Market({
            loanToken: address(usdc),
            collateralParams: cp,
            maturity: block.timestamp + 30 days,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
    }

    function _offer() internal view returns (Offer memory offer) {
        offer = _offerForMarket(_market());
    }

    function _marketWithCollaterals(address[] memory tokens, address[] memory oracles)
        internal
        view
        returns (Market memory market)
    {
        CollateralParams[] memory cp = new CollateralParams[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            cp[i] = CollateralParams({token: tokens[i], lltv: 0.86e18, maxLif: 1.15e18, oracle: oracles[i]});
        }
        market = Market({
            loanToken: address(usdc),
            collateralParams: cp,
            maturity: block.timestamp + 30 days,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
    }

    function _offerWithCollaterals(address[] memory tokens, address[] memory oracles)
        internal
        view
        returns (Offer memory offer)
    {
        offer = _offerForMarket(_marketWithCollaterals(tokens, oracles));
    }

    function _offerForMarket(Market memory market) internal view returns (Offer memory offer) {
        offer = Offer({
            market: market,
            buy: false, // sell offer: vault (taker) is the buyer/lender
            maker: address(0x1234),
            start: 0,
            expiry: block.timestamp + 1 days,
            tick: 0,
            group: bytes32(0),
            callback: address(0),
            callbackData: hex"",
            receiverIfMakerIsSeller: address(0x1234),
            ratifier: address(0),
            reduceOnly: false,
            maxUnits: 100e6,
            maxAssets: 0
        });
    }

    function _encodeTake(Offer memory offer) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            MockMidnight.take.selector,
            offer,
            hex"",
            uint256(100e6),
            address(boringVault),
            address(boringVault),
            address(0),
            hex""
        );
    }
}
