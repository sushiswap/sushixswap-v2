// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../interfaces/ISushiXSwapV2Adapter.sol";
import "../interfaces/synapse/ISynapseBridge.sol";
import "../interfaces/IWETH.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract SynapseAdapter is ISushiXSwapV2Adapter {
    using SafeERC20 for IERC20;

    ISynapseBridge public synapseBridge;
    IWETH public weth;

    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct SynapseBridgeParams {
        uint16 chainId;
        address token;
        uint256 amount;
        address to;
    }

    error RpSentNativeIn();

    constructor (address _synapseBridge, address _weth) {
        synapseBridge = ISynapseBridge(_synapseBridge);
        weth = IWETH(_weth);
    }

    function swap(
        uint256 _amountBridged,
        bytes calldata _swapData,
        address _token,
        bytes calldata _payloadData
    ) external payable override {
        revert();
    }

    function adapterBridge(
        bytes calldata _adapterData,
        bytes calldata,
        bytes calldata
    ) external payable override {
        SynapseBridgeParams memory params = abi.decode(
            _adapterData,
            (SynapseBridgeParams)
        );

        // Wrap native token if needed
        if (params.token == NATIVE_ADDRESS) {
            // RP should not send native in, since we won't know the amount from dust
            if (params.amount == 0) revert RpSentNativeIn();
            weth.deposit{value: params.amount}();
            params.token = address(weth);
        }

        IERC20(params.token).safeApprove(
            address(synapseBridge),
            params.amount
        );

        synapseBridge.deposit(params.to, params.chainId, IERC20(params.token), params.amount);
    }

    function sendMessage(bytes calldata _adapterData) external override {
        revert();
    }
}
