// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../interfaces/ISushiXSwapV2Adapter.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract SynapseAdapter is ISushiXSwapV2Adapter {
    using SafeERC20 for IERC20;

    address public immutable synapseRouter;

    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor(address _synapseRouter) {
        synapseRouter = _synapseRouter;
    }

    function swap(
        bytes calldata _swapData,
        address _token,
        bytes calldata _payloadData
    ) external override {
        revert();
    }

    function adapterBridge(
        bytes calldata _adapterData,
        bytes calldata,
        bytes calldata
    ) external payable override {
        (address token, bytes memory synapseRouterData) = abi.decode(
            _adapterData,
            (address, bytes)
        );

        if (token != NATIVE_ADDRESS) {
            IERC20(token).safeApprove(
                synapseRouter,
                IERC20(token).balanceOf(address(this))
            );
        }

        synapseRouter.call{value: address(this).balance}(synapseRouterData);
    }

    function sendMessage(bytes calldata _adapterData) external override {
        revert();
    }
}
