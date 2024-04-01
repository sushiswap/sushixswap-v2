// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

/// @title Handles ERC20 deposits and deposit executions.
/// @author Router Protocol.
/// @notice This contract is intended to be used with the Bridge contract.
interface INitroMessageHandler {
    /// @notice Function to handle the message/payload received along with token on destination chain.
    /// @dev This should only be received from the NitroAssetForwarder contract.
    /// @param tokenSent Address of the token received.
    /// @param amount Amount of the token received.
    /// @param message Message/Payload received.
    function handleMessage(
        address tokenSent,
        uint256 amount,
        bytes memory message
    ) external;
}