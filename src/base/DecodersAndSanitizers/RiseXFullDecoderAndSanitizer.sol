// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {
    RiseXCollateralManagerDecoderAndSanitizer
} from "src/base/DecodersAndSanitizers/Protocols/RiseXCollateralManagerDecoderAndSanitizer.sol";

/**
 * @title RiseXFullDecoderAndSanitizer
 * @notice Deployable decoder/sanitizer for a BoringVault that uses RiseX (RISE Chain, 4153).
 *         Authorizes only collateral deposit/withdraw on `CollateralManager` (+ `getOrRegister`
 *         on `AccountRegistry`) plus the inherited `approve`/`transfer` from the base. Order
 *         placement is off-chain (API/EIP-712) and intentionally has no decoder selector or leaf.
 */
contract RiseXFullDecoderAndSanitizer is RiseXCollateralManagerDecoderAndSanitizer {}
