// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract InfiniDecoderAndSanitizer is BaseDecoderAndSanitizer {
    //============================== ERC4626 ===============================

    function mint(address _to, uint256) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(_to);
    }

    function mintAndStake(address _to, uint256) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(_to);
    }

    function stake(address _to, uint256) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(_to);
    }

    function unstake(address _to, uint256) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(_to);
    }

    function redeem(address _to, uint256, uint256) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(_to);
    }
}
