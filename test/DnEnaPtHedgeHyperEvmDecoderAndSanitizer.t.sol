// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {
    DnEnaPtHedgeHyperEvmDecoderAndSanitizer
} from "src/base/DecodersAndSanitizers/DnEnaPtHedgeHyperEvmDecoderAndSanitizer.sol";

import "forge-std/Test.sol";

contract DnEnaPtHedgeHyperEvmDecoderAndSanitizerTest is Test {
    DnEnaPtHedgeHyperEvmDecoderAndSanitizer internal decoder;

    function setUp() external {
        decoder = new DnEnaPtHedgeHyperEvmDecoderAndSanitizer();
    }

    function testSendRawActionLimitOrderReturnsActionAndAsset() external view {
        bytes memory action = bytes.concat(
            hex"01000001", abi.encode(uint32(122), true, uint64(1), uint64(1), false, uint8(0), uint128(0))
        );

        bytes memory addressesFound = decoder.sendRawAction(action);

        assertEq(
            addressesFound,
            abi.encodePacked(
                address(0x0000000000000000000000000000000000000001),
                address(0x000000000000000000000000000000000000007a)
            )
        );
    }

    function testSendRawActionUsdClassTransferReturnsAction() external view {
        bytes memory action = bytes.concat(hex"01000007", abi.encode(uint64(1), true));

        bytes memory addressesFound = decoder.sendRawAction(action);

        assertEq(addressesFound, abi.encodePacked(address(0x0000000000000000000000000000000000000007)));
    }

    function testSendRawActionSendAssetReturnsActionDestinationSubaccountAndToken() external view {
        bytes memory action = bytes.concat(
            hex"0100000d",
            abi.encode(
                address(0x2000000000000000000000000000000000000000),
                address(0),
                uint32(0),
                uint32(0),
                uint64(0),
                uint64(1)
            )
        );

        bytes memory addressesFound = decoder.sendRawAction(action);

        assertEq(
            addressesFound,
            abi.encodePacked(
                address(0x000000000000000000000000000000000000000d),
                address(0x2000000000000000000000000000000000000000),
                address(0),
                address(0)
            )
        );
    }
}
