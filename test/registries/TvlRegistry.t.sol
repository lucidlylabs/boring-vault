// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test} from "@forge-std/Test.sol";

import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {ITvlAdapter} from "src/interfaces/ITvlAdapter.sol";
import {TvlRegistry} from "src/registries/TvlRegistry.sol";

contract MockTvlAdapter is ITvlAdapter {
    uint256 public tvl;
    bool public shouldRevert;

    function setTvl(uint256 v) external {
        tvl = v;
    }

    function setShouldRevert(bool v) external {
        shouldRevert = v;
    }

    function getUserTvl(address) external view returns (uint256) {
        if (shouldRevert) revert("adapter down");
        return tvl;
    }
}

contract MockBoringVault is MockERC20 {
    constructor() MockERC20("Boring Vault", "BV", 6) {}
}

contract TvlRegistryTest is Test {
    TvlRegistry internal registry;
    MockBoringVault internal vault;
    MockERC20 internal usdc;
    RolesAuthority internal authority;

    address internal owner = address(0xA11CE);
    address internal stranger = address(0xB0B);

    uint256 internal constant POSITION_A = uint256(keccak256("1.1.2.market-a"));
    uint256 internal constant POSITION_B = uint256(keccak256("1.1.2.market-b"));
    uint256 internal constant POSITION_C = uint256(keccak256("1.1.2.market-c"));

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        vault = new MockBoringVault();

        authority = new RolesAuthority(owner, Authority(address(0)));
        registry = new TvlRegistry(owner, authority, address(vault), address(usdc));
    }

    // ============================================================
    //                     REGISTRY MANAGEMENT
    // ============================================================

    function test_addPosition_storesAdapterAndEnumerates() public {
        MockTvlAdapter a = new MockTvlAdapter();
        vm.prank(owner);
        registry.addPosition(POSITION_A, a);

        assertEq(address(registry.adapters(POSITION_A)), address(a));
        assertEq(registry.positionCount(), 1);
        assertEq(registry.positionIds(0), POSITION_A);
    }

    function test_addPosition_revertsOnDuplicate() public {
        MockTvlAdapter a = new MockTvlAdapter();
        vm.prank(owner);
        registry.addPosition(POSITION_A, a);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TvlRegistry.TvlRegistry__PositionAlreadyRegistered.selector, POSITION_A));
        registry.addPosition(POSITION_A, a);
    }

    function test_addPosition_revertsWhenAdapterReverts() public {
        MockTvlAdapter a = new MockTvlAdapter();
        a.setShouldRevert(true);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TvlRegistry.TvlRegistry__AdapterRejected.selector, POSITION_A));
        registry.addPosition(POSITION_A, a);
    }

    function test_addPosition_requiresAuth() public {
        MockTvlAdapter a = new MockTvlAdapter();
        vm.prank(stranger);
        vm.expectRevert("UNAUTHORIZED");
        registry.addPosition(POSITION_A, a);
    }

    function test_removePosition_swapAndPopMaintainsEnumeration() public {
        MockTvlAdapter a = new MockTvlAdapter();
        MockTvlAdapter b = new MockTvlAdapter();
        MockTvlAdapter c = new MockTvlAdapter();

        vm.startPrank(owner);
        registry.addPosition(POSITION_A, a);
        registry.addPosition(POSITION_B, b);
        registry.addPosition(POSITION_C, c);
        registry.removePosition(POSITION_B);
        vm.stopPrank();

        assertEq(registry.positionCount(), 2);
        // B should have been swapped with the tail (C); order is now [A, C].
        assertEq(registry.positionIds(0), POSITION_A);
        assertEq(registry.positionIds(1), POSITION_C);
        assertEq(address(registry.adapters(POSITION_B)), address(0));
    }

    function test_removePosition_revertsOnUnknown() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TvlRegistry.TvlRegistry__PositionNotRegistered.selector, POSITION_A));
        registry.removePosition(POSITION_A);
    }

    // ============================================================
    //                       AGGREGATION
    // ============================================================

    function test_getTotalTvl_sumsPositionsPlusIdleBalance() public {
        MockTvlAdapter a = new MockTvlAdapter();
        MockTvlAdapter b = new MockTvlAdapter();
        a.setTvl(100e6);
        b.setTvl(250e6);

        vm.startPrank(owner);
        registry.addPosition(POSITION_A, a);
        registry.addPosition(POSITION_B, b);
        vm.stopPrank();

        // Idle USDC sitting on the vault.
        usdc.mint(address(vault), 50e6);

        assertEq(registry.getPositionTvl(POSITION_A), 100e6);
        assertEq(registry.getPositionTvl(POSITION_B), 250e6);
        assertEq(registry.getIdleBalance(), 50e6);
        assertEq(registry.getTotalTvl(), 400e6);
    }

    function test_getTotalTvl_revertsIfAdapterReverts() public {
        MockTvlAdapter a = new MockTvlAdapter();
        a.setTvl(100e6);

        vm.prank(owner);
        registry.addPosition(POSITION_A, a);

        a.setShouldRevert(true);

        vm.expectRevert("adapter down");
        registry.getTotalTvl();
    }

    function test_getExchangeRate_matchesExpectedMath() public {
        MockTvlAdapter a = new MockTvlAdapter();
        a.setTvl(1_165_000e6); // 1.165M USDC of TVL

        vm.prank(owner);
        registry.addPosition(POSITION_A, a);

        vault.mint(address(0xDEAD), 1_000_000e6); // 1M shares

        // rate = 1_165_000e6 * 10**6 / 1_000_000e6 = 1_165_000
        assertEq(registry.getExchangeRate(), 1_165_000);
    }

    function test_getExchangeRate_revertsOnZeroSupply() public {
        vm.expectRevert("TvlRegistry: no shares");
        registry.getExchangeRate();
    }

    function test_getReadSnapshot_returnsAggregateAndSupply() public {
        MockTvlAdapter a = new MockTvlAdapter();
        a.setTvl(500e6);

        vm.prank(owner);
        registry.addPosition(POSITION_A, a);
        usdc.mint(address(vault), 25e6);
        vault.mint(address(0xDEAD), 1_000e6);

        (uint256 totalTvl, uint256 supply) = registry.getReadSnapshot();
        assertEq(totalTvl, 525e6);
        assertEq(supply, 1_000e6);
    }
}
