// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {OAppAuth, Origin, MessagingFee, MessagingReceipt} from "@oapp-auth/OAppAuth.sol";
import {TvlRegistry} from "src/registries/TvlRegistry.sol";
import {
    ReadCmdCodecV1,
    EVMCallRequestV1,
    EVMCallComputeV1
} from "../../lib/LayerZero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/libs/ReadCmdCodecV1.sol";

/// @title CrossChainTvlAggregator
/// @notice hub-only contract that composes the hub `TvlRegistry` with cached
/// snapshots of spoke `TvlRegistry`s on other chains, fetched via LayerZero lzRead
contract CrossChainTvlAggregator is OAppAuth {
    /// @notice hub's local TvlRegistry — provides tvl contribution from positions on this chain
    TvlRegistry public immutable HUB_REGISTRY;

    /// @notice hub's boring vault — provides share count on this chain
    address public immutable BORING_VAULT;

    /// @notice base asset used to denominate aggregated tvl
    ERC20 public immutable BASE_ASSET;

    /// @notice layerzero read channel id this aggregator uses to send read commands
    /// @dev set as a peer via `setReadChannel`
    /// @dev lzRead messages arrive with this id in `Origin.srcEid`
    uint32 public immutable READ_CHANNEL;

    /// @notice Block confirmations to wait before resolving the spoke's view call
    uint16 public confirmations;

    // spoke registry

    struct SpokeConfig {
        uint32 eid; // layerzero endpoint id of the spoke chain
        address spokeRegistry; // TvlRegistry address on the spoke chain
        uint64 staleAfter; // seconds before a snapshot is considered stale
    }

    /// @notice spokeChainId → config
    mapping(uint256 chainId => SpokeConfig) public spokes;
    uint256[] public spokeChainIds;
    mapping(uint256 chainId => uint256 indexPlusOne) internal _spokeIdx;

    // snapshots

    struct Snapshot {
        uint256 totalTvl; // base asset terms
        uint256 totalShares; // BoringVault share decimals
        uint64 updatedAt;
        uint64 seq; // matches `currentSeq` at the time of `requestRefresh`
    }

    mapping(uint256 chainId => Snapshot) public snapshots;
    uint64 public currentSeq;

    /// @dev per-in-flight-message tracking so the receiver can map reply GUIDs
    /// back to which spoke and which refresh cycle they belong to
    mapping(bytes32 guid => uint256 chainId) internal _pendingChainId;
    mapping(bytes32 guid => uint64 seq) internal _pendingSeq;

    // events

    event SpokeAdded(uint256 indexed chainId, uint32 eid, address spokeRegistry);
    event SpokeRemoved(uint256 indexed chainId);
    event RefreshRequested(uint256 indexed chainId, uint64 seq, bytes32 guid);
    event SpokeSnapshotUpdated(uint256 indexed chainId, uint256 totalTvl, uint256 totalShares, uint64 seq);
    event ConfirmationsUpdated(uint16 newConfirmations);

    // errors

    error CrossChainTvlAggregator__SpokeAlreadyRegistered(uint256 chainId);
    error CrossChainTvlAggregator__SpokeNotRegistered(uint256 chainId);
    error CrossChainTvlAggregator__NotReadChannel(uint32 srcEid);
    error CrossChainTvlAggregator__UnknownGuid(bytes32 guid);
    error CrossChainTvlAggregator__SpokeStale(uint256 chainId);
    error CrossChainTvlAggregator__InsufficientFee(uint256 sent, uint256 required);

    // constructors

    constructor(
        address _owner,
        Authority _authority,
        address _endpoint,
        address _hubRegistry,
        address _boringVault,
        address _baseAsset,
        uint32 _readChannel,
        uint16 _confirmations
    ) Auth(_owner, _authority) OAppAuth(_endpoint, _owner) {
        HUB_REGISTRY = TvlRegistry(_hubRegistry);
        BORING_VAULT = _boringVault;
        BASE_ASSET = ERC20(_baseAsset);
        READ_CHANNEL = _readChannel;
        confirmations = _confirmations;
    }

    // spoke registry management

    function addSpoke(uint256 chainId, SpokeConfig calldata cfg) external requiresAuth {
        if (_spokeIdx[chainId] != 0) revert CrossChainTvlAggregator__SpokeAlreadyRegistered(chainId);
        require(cfg.eid != 0 && cfg.spokeRegistry != address(0) && cfg.staleAfter != 0, "bad spoke cfg");

        spokeChainIds.push(chainId);
        _spokeIdx[chainId] = spokeChainIds.length;
        spokes[chainId] = cfg;

        emit SpokeAdded(chainId, cfg.eid, cfg.spokeRegistry);
    }

    function removeSpoke(uint256 chainId) external requiresAuth {
        uint256 idxPlusOne = _spokeIdx[chainId];
        if (idxPlusOne == 0) revert CrossChainTvlAggregator__SpokeNotRegistered(chainId);

        uint256 lastIdx = spokeChainIds.length - 1;
        uint256 targetIdx = idxPlusOne - 1;
        if (targetIdx != lastIdx) {
            uint256 lastId = spokeChainIds[lastIdx];
            spokeChainIds[targetIdx] = lastId;
            _spokeIdx[lastId] = idxPlusOne;
        }
        spokeChainIds.pop();
        delete _spokeIdx[chainId];
        delete spokes[chainId];
        delete snapshots[chainId];

        emit SpokeRemoved(chainId);
    }

    function setConfirmations(uint16 _confirmations) external requiresAuth {
        confirmations = _confirmations;
        emit ConfirmationsUpdated(_confirmations);
    }

    // refresh

    /// @notice returns the encoded lzRead command targeting a single spoke's
    ///  `TvlRegistry.getReadSnapshot()`. exposed publicly so the cron
    /// can pass it to `quoteRefresh` before calling `requestRefresh`.
    function buildReadCmd(uint256 chainId) public view returns (bytes memory) {
        SpokeConfig memory cfg = spokes[chainId];
        if (cfg.eid == 0) revert CrossChainTvlAggregator__SpokeNotRegistered(chainId);

        EVMCallRequestV1[] memory reqs = new EVMCallRequestV1[](1);
        reqs[0] = EVMCallRequestV1({
            appRequestLabel: 1,
            targetEid: cfg.eid,
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: confirmations,
            to: cfg.spokeRegistry,
            callData: abi.encodeWithSelector(TvlRegistry.getReadSnapshot.selector)
        });

        EVMCallComputeV1 memory noCompute;
        return ReadCmdCodecV1.encode(1, reqs, noCompute);
    }

    /// @notice quotes the native fee for a single-spoke read
    function quoteRefresh(uint256 chainId, bytes calldata options) external view returns (MessagingFee memory) {
        bytes memory cmd = buildReadCmd(chainId);
        return _quote(READ_CHANNEL, cmd, options, false);
    }

    /// @notice fires an lzRead query at one spoke. caller must supply `msg.value`
    /// covering the native fee.
    function requestRefresh(uint256 chainId, bytes calldata options)
        external
        payable
        requiresAuth
        returns (MessagingReceipt memory receipt)
    {
        bytes memory cmd = buildReadCmd(chainId);
        MessagingFee memory fee = _quote(READ_CHANNEL, cmd, options, false);
        if (msg.value < fee.nativeFee) revert CrossChainTvlAggregator__InsufficientFee(msg.value, fee.nativeFee);

        ++currentSeq;
        uint64 seq = currentSeq;

        receipt = _lzSend(READ_CHANNEL, cmd, options, fee, msg.sender);

        _pendingChainId[receipt.guid] = chainId;
        _pendingSeq[receipt.guid] = seq;

        emit RefreshRequested(chainId, seq, receipt.guid);
    }

    /// @dev OAppAuthReceiver hook — called by `lzReceive` after peer/endpoint validation
    function _lzReceive(Origin calldata _origin, bytes32 _guid, bytes calldata _message, address, bytes calldata)
        internal
        override
    {
        if (_origin.srcEid != READ_CHANNEL) revert CrossChainTvlAggregator__NotReadChannel(_origin.srcEid);

        uint256 chainId = _pendingChainId[_guid];
        if (chainId == 0) revert CrossChainTvlAggregator__UnknownGuid(_guid);
        uint64 seq = _pendingSeq[_guid];

        delete _pendingChainId[_guid];
        delete _pendingSeq[_guid];

        (uint256 tvl, uint256 supply) = abi.decode(_message, (uint256, uint256));

        snapshots[chainId] =
            Snapshot({totalTvl: tvl, totalShares: supply, updatedAt: uint64(block.timestamp), seq: seq});

        emit SpokeSnapshotUpdated(chainId, tvl, supply, seq);
    }

    // reads

    function spokeCount() external view returns (uint256) {
        return spokeChainIds.length;
    }

    function isSpokeFresh(uint256 chainId) public view returns (bool) {
        SpokeConfig memory cfg = spokes[chainId];
        if (cfg.eid == 0) return false;
        Snapshot memory s = snapshots[chainId];
        if (s.updatedAt == 0) return false;
        return block.timestamp - s.updatedAt <= cfg.staleAfter;
    }

    /// @notice true if every registered spoke's latest snapshot matches the most
    /// recent refresh cycle (`currentSeq`)
    function isRefreshComplete() public view returns (bool) {
        uint64 seq = currentSeq;
        uint256 n = spokeChainIds.length;
        for (uint256 i; i < n; ++i) {
            if (snapshots[spokeChainIds[i]].seq != seq) return false;
        }
        return true;
    }

    /// @notice sum of tvl across hub and every registered spoke. Reverts if any
    /// spoke is stale per its configured `staleAfter`.
    function getGlobalTotalTvl() public view returns (uint256 total) {
        total = HUB_REGISTRY.getTotalTvl();
        uint256 n = spokeChainIds.length;
        for (uint256 i; i < n; ++i) {
            uint256 chainId = spokeChainIds[i];
            if (!isSpokeFresh(chainId)) revert CrossChainTvlAggregator__SpokeStale(chainId);
            total += snapshots[chainId].totalTvl;
        }
    }

    /// @notice sum of boringvault share supply across hub and every spoke.
    function getGlobalTotalShares() public view returns (uint256 total) {
        total = ERC20(BORING_VAULT).totalSupply();
        uint256 n = spokeChainIds.length;
        for (uint256 i; i < n; ++i) {
            uint256 chainId = spokeChainIds[i];
            if (!isSpokeFresh(chainId)) revert CrossChainTvlAggregator__SpokeStale(chainId);
            total += snapshots[chainId].totalShares;
        }
    }

    /// @notice global exchange rate in base-asset decimals. Reverts on stale spokes
    /// or empty share supply
    function getExchangeRate() external view returns (uint256) {
        uint256 supply = getGlobalTotalShares();
        require(supply > 0, "CrossChainTvlAggregator: no shares");
        uint8 shareDecimals = ERC20(BORING_VAULT).decimals();
        return getGlobalTotalTvl() * (10 ** shareDecimals) / supply;
    }
}
