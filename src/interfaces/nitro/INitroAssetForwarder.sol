// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

/// @title Interface for handler contracts that support deposits and deposit executions.
/// @author Router Protocol.
interface INitroAssetForwarder {
    /// @param partnerId Partner ID of the partner.
    /// @param amount Amount of source token to be bridged.
    /// @param destAmount Minimum amount of destination token to received on the destination chain.
    /// @param srcToken Address of the token to be bridged.
    /// @param refundRecipient Address of refund recipient on src chain if transaction expires on bridge.
    /// @param destChainIdBytes Chain ID identifier for destination chain.
    struct DepositData {
        uint256 partnerId;
        uint256 amount;
        uint256 destAmount;
        address srcToken;
        address refundRecipient;
        bytes32 destChainIdBytes;
    }
    
   
    /// @notice Function to deposit funds along with a payload to be bridged.
    /// @param depositData depositData struct.
    /// @param destToken Address of the destination token on the destination chain.
    /// @param recipient Address of the recipient on the destination chain.
    /// @param message Message/Payload to be passed to the destination chain along with the funds.
function iDepositMessage(
        DepositData memory depositData,
        bytes memory destToken,
        bytes memory recipient,
        bytes memory message
    ) external payable;
}