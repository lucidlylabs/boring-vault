// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract KyberSwapDecoderAndSanitizer is BaseDecoderAndSanitizer {
    /// @dev address of the KyberSwap MetaAggregationRouterV2
    address internal immutable kyberRouter;

    constructor(address _kyberRouter) {
        kyberRouter = _kyberRouter;
    }

    function swap(DecoderCustomTypes.SwapExecutionParams calldata execution)
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound =
            abi.encodePacked(execution.desc.srcToken, execution.desc.dstToken, execution.desc.dstReceiver);
    }
}
