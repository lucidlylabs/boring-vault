// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ITvlAdapter} from "src/interfaces/ITvlAdapter.sol";

/// @title TvlRegistry
/// @notice mutable on-chain registry of tvl adapters for a boring vault on a
/// single chain. aggregates each strategy's value into a single
/// base-asset-denominated number plus the vault's idle base balance.
/// @dev deploy one of these per network that the boringvault lives on. for
/// a single-network strategy this is all you need — offchain accountant service reads
/// `getExchangeRate()` and writes to the accountant. for multi-network
/// strategies, an instance of `CrossChainTvlAggregator` on the hub
/// composes the hub registry with snapshots from spoke registries.
contract TvlRegistry is Auth {
    address public immutable BORING_VAULT;
    ERC20 public immutable BASE_ASSET;

    // state

    /// @notice positionId → adapter. Position ids should follow the
    /// position-ids convention: keccak256("<chain>.<protocol>.<type>.<identifier>").
    mapping(uint256 positionId => ITvlAdapter adapter) public adapters;

    /// @notice Enumerable set of registered position ids.
    uint256[] public positionIds;

    /// @dev 1-indexed position in `positionIds` (0 = not registered).
    mapping(uint256 positionId => uint256 indexPlusOne) internal _idx;

    // events

    event PositionAdded(uint256 indexed positionId, address indexed adapter);
    event PositionRemoved(uint256 indexed positionId, address indexed adapter);

    // errors

    error TvlRegistry__PositionAlreadyRegistered(uint256 positionId);
    error TvlRegistry__PositionNotRegistered(uint256 positionId);
    error TvlRegistry__AdapterRejected(uint256 positionId);

    // constructor

    constructor(address _owner, Authority _authority, address _boringVault, address _baseAsset)
        Auth(_owner, _authority)
    {
        BORING_VAULT = _boringVault;
        BASE_ASSET = ERC20(_baseAsset);
    }

    // admin function

    /// @notice register a new tvl adapter under `positionid`.
    /// @dev performs a self-test by calling `adapter.getusertvl(vault)` —
    /// a misconfigured adapter that reverts on the vault address
    /// fails the add (rather than silently breaking aggregation later).
    function addPosition(uint256 positionId, ITvlAdapter adapter) external requiresAuth {
        if (_idx[positionId] != 0) revert TvlRegistry__PositionAlreadyRegistered(positionId);

        try adapter.getUserTvl(BORING_VAULT) returns (uint256) {}
        catch {
            revert TvlRegistry__AdapterRejected(positionId);
        }

        positionIds.push(positionId);
        _idx[positionId] = positionIds.length;
        adapters[positionId] = adapter;

        emit PositionAdded(positionId, address(adapter));
    }

    /// @notice remove a registered adapter. swap-and-pop on the enumeration array.
    function removePosition(uint256 positionId) external requiresAuth {
        uint256 idxPlusOne = _idx[positionId];
        if (idxPlusOne == 0) revert TvlRegistry__PositionNotRegistered(positionId);

        uint256 lastIdx = positionIds.length - 1;
        uint256 targetIdx = idxPlusOne - 1;

        if (targetIdx != lastIdx) {
            uint256 lastId = positionIds[lastIdx];
            positionIds[targetIdx] = lastId;
            _idx[lastId] = idxPlusOne;
        }

        positionIds.pop();
        ITvlAdapter removed = adapters[positionId];
        delete _idx[positionId];
        delete adapters[positionId];

        emit PositionRemoved(positionId, address(removed));
    }

    // view functions

    /// @notice Number of registered positions.
    function positionCount() external view returns (uint256) {
        return positionIds.length;
    }

    /// @notice tvl of a single registered position in base-asset terms.
    function getPositionTvl(uint256 positionId) public view returns (uint256) {
        ITvlAdapter adapter = adapters[positionId];
        if (address(adapter) == address(0)) revert TvlRegistry__PositionNotRegistered(positionId);
        return adapter.getUserTvl(BORING_VAULT);
    }

    /// @notice base asset sitting idle on the BoringVault (not deployed into a strategy).
    function getIdleBalance() public view returns (uint256) {
        return BASE_ASSET.balanceOf(BORING_VAULT);
    }

    /// @notice sum of every registered position's tvl plus the idle base balance.
    function getTotalTvl() public view returns (uint256 total) {
        uint256 n = positionIds.length;
        for (uint256 i; i < n; ++i) {
            total += adapters[positionIds[i]].getUserTvl(BORING_VAULT);
        }
        total += getIdleBalance();
    }

    /// @notice boringvault total share supply on this chain.
    function totalShares() public view returns (uint256) {
        return ERC20(BORING_VAULT).totalSupply();
    }

    /// @notice single-call helper for cross-chain readers (lzread targets this).
    function getReadSnapshot() external view returns (uint256 totalTvl, uint256 supply) {
        totalTvl = getTotalTvl();
        supply = ERC20(BORING_VAULT).totalSupply();
    }

    /// @notice exchange rate in base-asset decimals.
    /// @dev `rate = totalTvl * 10**shareDecimals / totalShares`.
    /// reverts if the share supply is zero — callers should check `totalShares()` first on a fresh vault.
    function getExchangeRate() external view returns (uint256) {
        uint256 supply = totalShares();
        require(supply > 0, "TvlRegistry: no shares");
        uint8 shareDecimals = ERC20(BORING_VAULT).decimals();
        return getTotalTvl() * (10 ** shareDecimals) / supply;
    }
}
