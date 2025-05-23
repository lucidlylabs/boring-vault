// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";


abstract contract Permit2DecoderAndSanitizer is BaseDecoderAndSanitizer {

    // ========================================= ERRORS ==================================
    
    error Permit2DecoderAndSanitizer__LengthGtOne();  
     
    
    function approve(address token, address spender, uint160 /*amount*/, uint48 /*expiraton*/) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(token, spender);
    }

    function lockdown(DecoderCustomTypes.TokenSpenderPair[] memory approvals) external pure returns (bytes memory addressesFound) {
        if (approvals.length > 1) revert Permit2DecoderAndSanitizer__LengthGtOne(); 
        addressesFound = abi.encodePacked(approvals[0].token, approvals[0].spender); 
    }
}
