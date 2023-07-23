// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.10;

interface IStargateFeeLibrary {
    // returns -> amount, eqFee, eqReward, lpFee, protocolFee, lkbRemove
    function getFees(uint256 _srcPoolId, uint256 _dstPoolId, uint16 _dstChainId, address _from, uint256 _amountSD)
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256);
}
