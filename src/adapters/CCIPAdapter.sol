// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "../interfaces/ISushiXSwapV2Adapter.sol";
import "../interfaces/IRouteProcessor.sol";
import "../interfaces/IWETH.sol";

import "ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract CCIPAdapter is ISushiXSwapV2Adapter, CCIPReceiver {
    using SafeERC20 for IERC20;

    IRouteProcessor public immutable rp;
    IRouterClient router;
    IWETH public immutable weth;
    // link address for payWithLink

    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct CCIPBridgeParams {
        uint64 destinationChain;
        address receiver;
        bytes32 text;
        address token;
        uint256 amount;
    }

    error RpSentNativeIn();

    constructor(
        address _router, // link messaging router
        address _link, // LINK address
        address _rp,
        address _weth
    ) CCIPReceiver(_router) {
        // link = _link
        rp = IRouteProcessor(_rp);
        weth = IWETH(_weth);
        router = IRouterClient(_router);
    }

    /// @inheritdoc ISushiXSwapV2Adapter
    function swap(
        uint256 _amountBridged,
        bytes calldata _swapData,
        address _token,
        bytes calldata _payloadData
    ) external payable override {
        IRouteProcessor.RouteProcessorData memory rpd = abi.decode(
            _swapData,
            (IRouteProcessor.RouteProcessorData)
        );

        // send tokens to RP
        IERC20(rpd.tokenIn).safeTransfer(address(rp), _amountBridged);

        rp.processRoute(
            rpd.tokenIn,
            _amountBridged,
            rpd.tokenOut,
            rpd.amountOutMin,
            rpd.to,
            rpd.route
        );

        // tokens should be sent via rp
        if (_payloadData.length > 0) {
            PayloadData memory pd = abi.decode(_payloadData, (PayloadData));
            try
                IPayloadExecutor(pd.target).onPayloadReceive{gas: pd.gasLimit}(
                    pd.targetData
                )
            {} catch (bytes memory) {
                revert();
            }
        }
    }

    /// @inheritdoc ISushiXSwapV2Adapter
    function executePayload(
        uint256 _amountBridged,
        bytes calldata _payloadData,
        address _token
    ) external payable override {
        PayloadData memory pd = abi.decode(_payloadData, (PayloadData));
        IERC20(_token).safeTransfer(pd.target, _amountBridged);
        IPayloadExecutor(pd.target).onPayloadReceive{gas: pd.gasLimit}(
            pd.targetData
        );
    }

    //getFee function -> router.getFee

    /// @inheritdoc ISushiXSwapV2Adapter
    function adapterBridge(
        bytes calldata _adapterData,
        address _refundAddress,
        bytes calldata _swapData,
        bytes calldata _payloadData
    ) external payable override {
        CCIPBridgeParams memory params = abi.decode(
          _adapterData,
          (CCIPBridgeParams)
        );

        if (params.token == NATIVE_ADDRESS) {
            // RP should not send native in, since we won't know the exact amount to bridge
            if (params.amount == 0) revert RpSentNativeIn();
            weth.deposit{value: params.amount}();
            params.token = address(weth);
        }

        if (params.amount == 0)
            params.amount = IERC20(params.token).balanceOf(address(this));

        // build ccip message

        // getFees
        
        // aprove router to spend tokens

        // send message thru router


    }

    // message receiver - ccipReceive
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        // check msg.sender is the router address

        // read any2EvmMessage.data in

        // any2EvmMessage.destTokenAmounts[0].token;
        // any2EvmMessage.destTokenAmounts[0].amount;

    }

    /// @inheritdoc ISushiXSwapV2Adapter
    function sendMessage(bytes calldata _adapterData) external override {
        (_adapterData);
        revert();
    }

    receive() external payable {}
}
