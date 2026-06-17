// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

contract RoycoJrStcusdBalanceAdapter {
    address immutable jr_tranche_address;
    address immutable stcusd_address;
    address immutable cusd_address;
    address immutable usdc_address;

    constructor(
        address _jr_tranche_address,
        address _stcusd_address,
        address _cusd_address,
        address _usdc_address
    ) {
        jr_tranche_address = _jr_tranche_address;
        stcusd_address = _stcusd_address;
        cusd_address = _cusd_address;
        usdc_address = _usdc_address;
    }

    /// @dev Junior tranche shares -> stcUSD -> cUSD -> USDC. All preview-based, no oracles.
    /// JT.previewRedeem returns AssetClaims { stAssets, jtAssets, nav }: only jtAssets is the
    /// claimable underlying asset (stcUSD) for a junior holder. stcUSD is an ERC4626 over cUSD,
    /// then cUSD.getBurnAmount converts to USDC (6-dec).
    function getUserTvl(address _user) external view returns (uint256 tvl) {
        bytes memory payload = abi.encodeWithSignature("balanceOf(address)", _user);
        (bool success, bytes memory returnData) = jr_tranche_address.staticcall(payload);
        require(success, "JT balance staticcall failed");
        uint256 jtShares = abi.decode(returnData, (uint256));
        if (jtShares == 0) return 0;

        payload = abi.encodeWithSignature("previewRedeem(uint256)", jtShares);
        (success, returnData) = jr_tranche_address.staticcall(payload);
        require(success, "JT previewRedeem staticcall failed");
        (, uint256 stcusdAmt,) = abi.decode(returnData, (uint256, uint256, uint256));
        if (stcusdAmt == 0) return 0;

        payload = abi.encodeWithSignature("previewRedeem(uint256)", stcusdAmt);
        (success, returnData) = stcusd_address.staticcall(payload);
        require(success, "stcUSD previewRedeem staticcall failed");
        uint256 cusdAmt = abi.decode(returnData, (uint256));
        if (cusdAmt == 0) return 0;

        payload = abi.encodeWithSignature(
            "getBurnAmount(address,address,uint256)", _user, usdc_address, cusdAmt
        );
        (success, returnData) = cusd_address.staticcall(payload);
        require(success, "cUSD getBurnAmount staticcall failed");
        (uint256 usdcOut, ) = abi.decode(returnData, (uint256, uint256));
        tvl = usdcOut;
    }
}
