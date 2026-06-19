// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

/**
 * @title RiseXCollateralManagerDecoderAndSanitizer
 * @notice Decoder/sanitizer for RiseX's `CollateralManager` on RISE Chain (chainId 4153).
 *
 *         RiseX is a fully on-chain perps orderbook on RISE. Trading (order placement /
 *         cancellation) is performed OFF-CHAIN via EIP-712 messages signed by an API signer
 *         key and submitted through the RiseX API, so it is NOT part of this on-chain decoder
 *         surface. The only thing the BoringVault does on-chain is move collateral in and out
 *         of `CollateralManager`. That is exactly what this mixin authorizes.
 *
 *         Custody safety: every `account` argument is returned so the merkle leaf can pin it to
 *         the BoringVault, preventing collateral from being credited to — or withdrawn on behalf
 *         of — a different RiseX account. `token` is returned so a leaf can pin the collateral
 *         asset (e.g. USDC). Amounts are the trusted strategist's domain and are not constrained.
 *
 *         There are no callbacks in any of these entrypoints, so there is nothing to block.
 */
abstract contract RiseXCollateralManagerDecoderAndSanitizer is BaseDecoderAndSanitizer {
    /**
     * @notice CollateralManager.deposit — pulls `amount` of `token` from the caller and credits
     *         `account` on the exchange. Pin `account` to the vault and `token` to USDC.
     */
    function deposit(
        address account,
        address token,
        uint256 /*amount*/
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(account, token);
    }

    /**
     * @notice CollateralManager.withdraw — requests a withdrawal of `amount` of `token` for
     *         `account` (two-step: settled later via `releasePendingWithdrawal`). Pin `account`
     *         to the vault and `token` to USDC.
     */
    function withdraw(
        address account,
        address token,
        uint256 /*amount*/
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(account, token);
    }

    /**
     * @notice CollateralManager.releasePendingWithdrawal — settles a previously requested
     *         withdrawal of `token` for `account`. Pin `account` to the vault and `token` to USDC.
     */
    function releasePendingWithdrawal(
        address account,
        address token
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(account, token);
    }

    /**
     * @notice RISExAuthorization.registerSenderSigner — authorizes `signer` (the strategist's API
     *         signer key) to place orders on behalf of the caller's RiseX account. The account is
     *         `msg.sender`, so when the BoringVault calls this it authorizes a signer for ITS OWN
     *         account with no off-chain signature (no EIP-1271 needed). Pin `signer` so only the
     *         intended key can be authorized. Trading then happens off-chain via the RiseX API
     *         signed by that key; it has no decoder surface. Authorizations expire (~7 days) and are
     *         refreshed by re-calling with the same `signer` — the pinned leaf is reused, no re-root.
     *
     *         NOTE: a signer can only trade; it cannot move funds out of the vault (withdrawals are
     *         separately merkle-gated with the recipient pinned to the vault), so this does not widen
     *         custody. Account *creation* (`AccountRegistry.getOrRegister`) is operator-gated and
     *         off-chain (verified on-chain: neither deposit nor this call self-registers), so it has
     *         no decoder selector or leaf — the vault must be onboarded by RiseX before either.
     */
    function registerSenderSigner(
        address signer,
        uint48 /*nonceAnchor*/,
        uint8 /*nonceBitmap*/,
        uint32 /*expiration*/
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(signer);
    }
}
