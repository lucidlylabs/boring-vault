// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {MainnetAddresses} from "test/resources/MainnetAddresses.sol";
import {SyUsdDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/SyUsdDecoderAndSanitizer.sol";
import {DecoderCustomTypes} from "src/interfaces/DecoderCustomTypes.sol";
import {BaseTestIntegration} from "test/integrations/BaseTestIntegration.t.sol";

/// @notice Integration tests for Jam Settlement (Bebop Jam) on SyUsd vault.
/// @dev Reference TX: https://etherscan.io/tx/0x9094a719fcbbe1882e0bf852b052983fa692af7532027256e344367e1c3fc5b5
contract SyUsdJamSettlementIntegrationTest is BaseTestIntegration {
    uint256 internal constant REFERENCE_BLOCK = 25_325_442;
    uint256 internal constant REFERENCE_TX_VALUE = 0.0001 ether;

  // Calldata from reference tx (selector + ABI-encoded settle args)
    bytes internal constant REFERENCE_SETTLE_CALLDATA =
        hex"2143d82c00000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000003400000000000000000000000000000000000000000000000000000000000000760000000000000000000000000beb0b0623f66be8ce162ebdfa2ec543a522f4ea600000000000000000000000090760a784953829095969204f87d6dfec29a6ca900000000000000000000000090760a784953829095969204f87d6dfec29a6ca9000000000000000000000000000000000000000000000000000000006a306799000000000000000000000000000000000000000000000000000000006a30679900000000000000000000000000000000ff8e1368244c4ec483a3216f7976ac4a00000000000000000000000090760a784953829095969204f87d6dfec29a6ca90000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000024000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000005af3107a40000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000002c4730000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000ac4c6e212a361c968f1725b4d055b47e63f80b7500000000000000000000000000000000000000000000000000005af3107a4000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000003245f3bd1c8000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000005af3107a4000000000000000000000000000beb0b0623f66be8ce162ebdfa2ec543a522f4ea6000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000002c473000000000000000000000000c10ee9031f2a0b84766a86b55a8d90f357910fb400000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000002046be92b89000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000005af3107a4000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000002c529000000000000000000000000beb0b0623f66be8ce162ebdfa2ec543a522f4ea600000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000cc019ecd134f1300020301ffff0201c10ee9031f2a0b84766a86b55a8d90f357910fb4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc201c02aaa39b223fe8d0a0e5c4f27ead9083c756cc201ffff06000000000004444c5dc75cb358380d2e3de08a90a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000001f400000a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c10ee9031f2a0b84766a86b55a8d90f357910fb4b5e61fb14a02000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    address internal referenceTaker = 0x90760A784953829095969204f87d6DFEc29a6ca9;

    function setUp() public override {
        super.setUp();
        _setupChain("mainnet", REFERENCE_BLOCK);
        _overrideDecoder(
            address(
                new SyUsdDecoderAndSanitizer(
                    getAddress(sourceChain, "uniswapV3NonFungiblePositionManager"),
                    getAddress(sourceChain, "odosRouterV2")
                )
            )
        );
    }

    function test_decoderExtractsReferenceTxAddresses() external view {
        bytes memory packed = _decoderPackedAddresses(REFERENCE_SETTLE_CALLDATA);

        bytes memory expected = abi.encodePacked(
            referenceTaker,
            referenceTaker,
            referenceTaker,
            getAddress(sourceChain, "ETH"),
            getAddress(sourceChain, "USDC"),
            getAddress(sourceChain, "jamSettlement"),
            getAddress(sourceChain, "jamInteractionRouter")
        );

        assertEq(packed, expected, "decoder must match reference tx packed addresses");
    }

    function test_referenceCalldataMatchesSettleLeafArgumentAddresses() external view {
        ManageLeaf memory settleLeaf = _referenceSettleLeaf();
        bytes memory packed = _decoderPackedAddresses(REFERENCE_SETTLE_CALLDATA);

        assertEq(settleLeaf.argumentAddresses.length * 20, packed.length, "packed address byte length");
        for (uint256 i; i < settleLeaf.argumentAddresses.length; ++i) {
            address decoded;
            assembly {
                decoded := shr(96, mload(add(add(packed, 32), mul(i, 20))))
            }
            assertEq(decoded, settleLeaf.argumentAddresses[i], "leaf address mismatch");
        }
    }

    function test_jamSettlementLeafsPassDecoderVerification() external {
        ManageLeaf[] memory leafs = new ManageLeaf[](4);

        address[] memory sellTokens = new address[](1);
        sellTokens[0] = getAddress(sourceChain, "ETH");
        address[] memory buyTokens = new address[](1);
        buyTokens[0] = getAddress(sourceChain, "USDC");

        _addJamSettlementLeafs(
            leafs,
            sellTokens,
            buyTokens,
            getAddress(sourceChain, "dev4Address"),
            getAddress(sourceChain, "jamInteractionRouter")
        );

        // Pad tree to satisfy minimum leaf count used elsewhere in repo
        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            address(0),
            false,
            "",
            new address[](0),
            "padding leaf",
            getAddress(sourceChain, "rawDataDecoderAndSanitizer")
        );

        _verifyDecoderImplementsLeafsFunctionSelectors(leafs);
    }

    function test_exactReferenceTxPassesMerkleThenSettleReverts() external {
        ManageLeaf[] memory leafs = new ManageLeaf[](2);
        leafs[0] = _referenceSettleLeaf();

        unchecked {
            leafIndex = 0;
        }
        leafs[1] = ManageLeaf(
            address(0),
            false,
            "",
            new address[](0),
            "padding leaf",
            getAddress(sourceChain, "rawDataDecoderAndSanitizer")
        );

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);

        ManageLeaf[] memory manageLeafs = new ManageLeaf[](1);
        manageLeafs[0] = leafs[0];

        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        address[] memory targets = new address[](1);
        targets[0] = getAddress(sourceChain, "jamSettlement");

        bytes[] memory targetDataArr = new bytes[](1);
        targetDataArr[0] = REFERENCE_SETTLE_CALLDATA;

        uint256[] memory values = new uint256[](1);
        values[0] = REFERENCE_TX_VALUE;

        address[] memory decoders = new address[](1);
        decoders[0] = rawDataDecoderAndSanitizer;

        vm.deal(address(boringVault), REFERENCE_TX_VALUE);

        // Exact reference calldata: merkle verification passes; settle reverts (expired signature / order).
        vm.expectRevert();
        manager.manageVaultWithMerkleVerification(
            manageProofs, decoders, targets, targetDataArr, values
        );
    }

    function test_merkleVerificationPassesBeforeSettleReverts() external {
        ManageLeaf[] memory leafs = new ManageLeaf[](4);

        address[] memory sellTokens = new address[](1);
        sellTokens[0] = getAddress(sourceChain, "ETH");
        address[] memory buyTokens = new address[](1);
        buyTokens[0] = getAddress(sourceChain, "USDC");

        _addJamSettlementLeafs(
            leafs,
            sellTokens,
            buyTokens,
            getAddress(sourceChain, "dev4Address"),
            getAddress(sourceChain, "jamInteractionRouter")
        );

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            address(0),
            false,
            "",
            new address[](0),
            "padding leaf",
            getAddress(sourceChain, "rawDataDecoderAndSanitizer")
        );

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);

        ManageLeaf[] memory manageLeafs = new ManageLeaf[](1);
        manageLeafs[0] = leafs[0];

        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        bytes memory targetData = _buildVaultSettleCalldata();

        address[] memory targets = new address[](1);
        targets[0] = getAddress(sourceChain, "jamSettlement");

        bytes[] memory targetDataArr = new bytes[](1);
        targetDataArr[0] = targetData;

        uint256[] memory values = new uint256[](1);
        values[0] = REFERENCE_TX_VALUE;

        address[] memory decoders = new address[](1);
        decoders[0] = rawDataDecoderAndSanitizer;

        vm.deal(address(boringVault), REFERENCE_TX_VALUE);

        // Merkle verification should pass; settle reverts without a valid Jam signature.
        vm.expectRevert();
        manager.manageVaultWithMerkleVerification(
            manageProofs, decoders, targets, targetDataArr, values
        );
    }

    function test_revertWhenMultipleInteractions() external view {
        address[] memory sellTokens = new address[](1);
        sellTokens[0] = getAddress(sourceChain, "ETH");
        address[] memory buyTokens = new address[](1);
        buyTokens[0] = getAddress(sourceChain, "USDC");

        uint256[] memory sellAmts = new uint256[](1);
        sellAmts[0] = 1;
        uint256[] memory buyAmts = new uint256[](1);
        buyAmts[0] = 1;

        DecoderCustomTypes.JamOrder memory order = DecoderCustomTypes.JamOrder({
            taker: address(boringVault),
            receiver: address(boringVault),
            expiry: block.timestamp + 1 hours,
            exclusivityDeadline: block.timestamp + 1 hours,
            nonce: 1,
            executor: getAddress(sourceChain, "dev4Address"),
            partnerInfo: 0,
            sellTokens: sellTokens,
            buyTokens: buyTokens,
            sellAmounts: sellAmts,
            buyAmounts: buyAmts,
            usingPermit2: false
        });

        DecoderCustomTypes.JamInteractionData[] memory interactions = new DecoderCustomTypes.JamInteractionData[](2);
        interactions[0] = DecoderCustomTypes.JamInteractionData({
            result: true,
            to: getAddress(sourceChain, "jamInteractionRouter"),
            value: 0,
            data: ""
        });
        interactions[1] = interactions[0];

        bytes memory calldata_ = abi.encodeWithSelector(
            bytes4(0x2143d82c),
            order,
            bytes(""),
            interactions,
            bytes(""),
            getAddress(sourceChain, "jamSettlement")
        );

        (bool ok,) = rawDataDecoderAndSanitizer.staticcall(calldata_);
        assertFalse(ok, "decoder must revert on multiple interactions");
    }

    function _decoderPackedAddresses(bytes memory calldata_) internal view returns (bytes memory packed) {
        (bool success, bytes memory returndata) = rawDataDecoderAndSanitizer.staticcall(calldata_);
        assertTrue(success, "decoder staticcall failed");
        packed = abi.decode(returndata, (bytes));
    }

    function _referenceSettleLeaf() internal view returns (ManageLeaf memory leaf) {
        bytes memory packed = _decoderPackedAddresses(REFERENCE_SETTLE_CALLDATA);
        address[] memory argumentAddresses = new address[](7);
        for (uint256 i; i < 7; ++i) {
            address decoded;
            assembly {
                decoded := shr(96, mload(add(add(packed, 32), mul(i, 20))))
            }
            argumentAddresses[i] = decoded;
        }

        leaf = ManageLeaf(
            getAddress(sourceChain, "jamSettlement"),
            true,
            "settle((address,address,uint256,uint256,uint256,address,uint256,address[],address[],uint256[],uint256[],bool),bytes,(bool,address,uint256,bytes)[],bytes,address)",
            argumentAddresses,
            "Jam settle exact reference tx",
            rawDataDecoderAndSanitizer
        );
    }

    function _buildVaultSettleCalldata() internal view returns (bytes memory) {
        address[] memory sellTokens = new address[](1);
        sellTokens[0] = getAddress(sourceChain, "ETH");
        address[] memory buyTokens = new address[](1);
        buyTokens[0] = getAddress(sourceChain, "USDC");

        uint256[] memory sellAmts = new uint256[](1);
        sellAmts[0] = REFERENCE_TX_VALUE;
        uint256[] memory buyAmts = new uint256[](1);
        buyAmts[0] = 181_363;

        DecoderCustomTypes.JamOrder memory order = DecoderCustomTypes.JamOrder({
            taker: address(boringVault),
            receiver: address(boringVault),
            expiry: block.timestamp + 1 hours,
            exclusivityDeadline: block.timestamp + 1 hours,
            nonce: 1,
            executor: getAddress(sourceChain, "dev4Address"),
            partnerInfo: 0,
            sellTokens: sellTokens,
            buyTokens: buyTokens,
            sellAmounts: sellAmts,
            buyAmounts: buyAmts,
            usingPermit2: false
        });

        DecoderCustomTypes.JamInteractionData[] memory interactions = new DecoderCustomTypes.JamInteractionData[](1);
        interactions[0] = DecoderCustomTypes.JamInteractionData({
            result: true,
            to: getAddress(sourceChain, "jamInteractionRouter"),
            value: REFERENCE_TX_VALUE,
            data: hex"5f3bd1c8"
        });

        return abi.encodeWithSelector(
            bytes4(0x2143d82c),
            order,
            bytes(""),
            interactions,
            bytes(""),
            getAddress(sourceChain, "jamSettlement")
        );
    }
}
