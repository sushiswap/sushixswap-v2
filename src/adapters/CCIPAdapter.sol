// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "../interfaces/ISushiXSwapV2Adapter.sol";
import "../interfaces/IRouteProcessor.sol";
import "../interfaces/IWETH.sol";

import "ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {console2} from "forge-std/console2.sol";

contract CCIPAdapter is ISushiXSwapV2Adapter, CCIPReceiver {
    using SafeERC20 for IERC20;

    IRouteProcessor public immutable rp;
    IRouterClient router;
    IWETH public immutable weth;
    IERC20 public immutable link;

    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct CCIPBridgeParams {
        uint64 destinationChain; // ccip dst chain id
        address receiver; // destination address for ccipReceive
        address to; // address for fallback transfer on ccipReceive
        address token; // token getting bridged
        uint256 amount; // amount to bridge
        uint256 gasLimit; // gaslimit to send in message
        // todo: add payInLink bool
    }

    error RpSentNativeIn();
    error NotCCIPRouter();
    error InsufficientGas();
    error NotEnoughNativeForFees(uint256 currentBalance, uint256 calculateFees);

    constructor(
        address _router,
        address _link,
        address _rp,
        address _weth
    ) CCIPReceiver(_router) {
        link = IERC20(_link);
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

    /// @notice Get the fees to be paid in native token for the bridge/message
    /// @param _adapterData adapter data to construct ccip message for polling fee amount
    /// @param _swapData swap data to construct ccip message for polling fee amount
    /// @param _payloadData payload data to construct ccip message for polling fee amount
    function getFee(
        bytes calldata _adapterData,
        bytes calldata _swapData,
        bytes calldata _payloadData
    ) public view returns (uint256 fees) {
        CCIPBridgeParams memory params = abi.decode(
            _adapterData,
            (CCIPBridgeParams)
        );

        if (params.amount == 0) params.amount = 1000; // set arbitrary amount if 0

        bytes memory payload = bytes("");
        if (_swapData.length > 0 || _payloadData.length > 0) {
            payload = abi.encode(params.to, _swapData, _payloadData);
        }

        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            params.receiver,
            payload,
            params.token,
            params.amount,
            address(0), // native payment token
            params.gasLimit
        );

        fees = router.getFee(params.destinationChain, evm2AnyMessage);
    }

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

        bytes memory payload = bytes("");
        if (_swapData.length > 0 || _payloadData.length > 0) {
            // @dev dst gas should be more than 100k
            if (params.gasLimit < 100000) revert InsufficientGas();
            payload = abi.encode(params.to, _swapData, _payloadData);
        }

        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            params.receiver,
            payload,
            params.token,
            params.amount,
            address(0), // native payment token, todo: add payInLink support
            params.gasLimit
        );

        uint256 fees = router.getFee(params.destinationChain, evm2AnyMessage);

        if (fees > address(this).balance)
            revert NotEnoughNativeForFees(address(this).balance, fees);

        IERC20(params.token).forceApprove(address(router), params.amount);

        router.ccipSend{value: fees}(params.destinationChain, evm2AnyMessage);

        _refundAddress.call{value: (address(this).balance)}("");
    }

    /// @notice Receiver function on destination chain
    /// @param any2EVMMessage ccip message sent by router
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EVMMessage
    ) internal override {
        // CCIPReceiver ccipReceive function has onlyRouter modifier
        uint256 gasLeft = gasleft();

        (address to, bytes memory _swapData, bytes memory _payloadData) = abi
            .decode(any2EVMMessage.data, (address, bytes, bytes));

        address token = any2EVMMessage.destTokenAmounts[0].token;
        uint256 amount = any2EVMMessage.destTokenAmounts[0].amount;

        uint256 reserveGas = 100000;

        if (gasLeft < reserveGas) {
            IERC20(token).safeTransfer(to, amount);

            // @dev transfer any native token
            if (address(this).balance > 0)
                to.call{value: (address(this).balance)}("");

            return;
        }

        // 100000 -> exit gas
        uint256 limit = gasLeft - reserveGas;

        if (_swapData.length > 0) {
            try
                ISushiXSwapV2Adapter(address(this)).swap{gas: limit}(
                    amount,
                    _swapData,
                    token,
                    _payloadData
                )
            {} catch (bytes memory) {}
        } else if (_payloadData.length > 0) {
            try
                ISushiXSwapV2Adapter(address(this)).executePayload{gas: limit}(
                    amount,
                    _payloadData,
                    token
                )
            {} catch (bytes memory) {}
        } else {}

        if (IERC20(token).balanceOf(address(this)) > 0)
            IERC20(token).safeTransfer(
                to,
                IERC20(token).balanceOf(address(this))
            );

        // @dev transfer any native token leftover to the to address
        if (address(this).balance > 0)
            to.call{value: (address(this).balance)}("");
    }

    function _buildCCIPMessage(
        address _receiver,
        bytes memory _payload,
        address _token,
        uint256 _amount,
        address _feeTokenAddress,
        uint256 _gasLimit
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });
        tokenAmounts[0] = tokenAmount;

        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver), // encoded receiver address
            data: _payload, // encoded message
            tokenAmounts: tokenAmounts, // the amount and type of token being transferred
            extraArgs: Client._argsToBytes(
                // additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({gasLimit: _gasLimit, strict: false})
            ),
            feeToken: _feeTokenAddress
        });

        return evm2AnyMessage;
    }

    /// @inheritdoc ISushiXSwapV2Adapter
    function sendMessage(bytes calldata _adapterData) external override {
        (_adapterData);
        revert();
    }

    receive() external payable {}
}
