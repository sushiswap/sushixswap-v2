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
    // todo: link address for payWithLink

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
    function getFee(
        bytes calldata _adapterData,
        bytes calldata _swapData,
        bytes calldata _payloadData
    ) public view returns (uint256 fees) {
        CCIPBridgeParams memory params = abi.decode(
            _adapterData,
            (CCIPBridgeParams)
        );

        if (params.amount == 0) params.amount = 1000;

        // build swapData and payloadData for CCIPMessage
        bytes memory payload = bytes("");
        if (_swapData.length > 0 || _payloadData.length > 0) {
            payload = abi.encode(params.to, _swapData, _payloadData);
        }

        // build ccip message
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

    /*function buildEVM2AnyMessage(
        bytes calldata _adapterData,
        bytes calldata _swapData,
        bytes calldata _payloadData
    ) public pure returns (Client.EVM2AnyMessage memory evm2AnyMessage) {
        CCIPBridgeParams memory params = abi.decode(
            _adapterData,
            (CCIPBridgeParams)
        );

        if (params.amount == 0) params.amount = 1000;

        // build swapData and payloadData for CCIPMessage
        bytes memory payload = bytes("");
        if (_swapData.length > 0 || _payloadData.length > 0) {
            payload = abi.encode(params.to, _swapData, _payloadData);
        }

        // build ccip message
        evm2AnyMessage = _buildCCIPMessage(
            params.receiver,
            payload,
            params.token,
            params.amount,
            address(0), // native payment token
            params.gasLimit
        );
    }*/

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

        // build swapData and payloadData for CCIPMessage
        bytes memory payload = bytes("");
        if (_swapData.length > 0 || _payloadData.length > 0) {
            // @dev dst gas should be more than 100k
            if (params.gasLimit < 100000) revert InsufficientGas();
            payload = abi.encode(params.to, _swapData, _payloadData);
        }

        // build ccip message
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            params.receiver,
            payload,
            params.token,
            params.amount,
            address(0), // native payment token
            params.gasLimit
        );

        // getFees
        uint256 fees = router.getFee(params.destinationChain, evm2AnyMessage);

        if (fees > address(this).balance)
            revert NotEnoughNativeForFees(address(this).balance, fees);

        // aprove router to spend tokens
        IERC20(params.token).safeApprove(address(router), params.amount);

        // send message thru router
        router.ccipSend{value: fees}(params.destinationChain, evm2AnyMessage);

        // return extra native to sender
        _refundAddress.call{value: (address(this).balance)}("");

        // reset approval
        IERC20(params.token).safeApprove(address(router), 0);
    }

    // message receiver - ccipReceive
    function _ccipReceive(
        Client.Any2EVMMessage memory evm2AnyMessage
    ) internal override {
        // check msg.sender is the router address
        //if (msg.sender != address(router)) revert NotCCIPRouter();
        // don't think above is needed since CCIPReceiver ccipReceive function has onlyRouter modifier

        // decode evm2AnyMessage.data into to, swapData, and payloadData
        (address to, bytes memory _swapData, bytes memory _payloadData) = abi
            .decode(evm2AnyMessage.data, (address, bytes, bytes));

        // evm2AnyMessage.destTokenAmounts[0].token;
        // evm2AnyMessage.destTokenAmounts[0].amount;
        address token = evm2AnyMessage.destTokenAmounts[0].token;
        uint256 amount = evm2AnyMessage.destTokenAmounts[0].amount;

        // set reserve Gas
        uint256 reserveGas = 100000;

        // if gasLeft() < reserveGas
        if (gasleft() < reserveGas) {
            IERC20(token).safeTransfer(to, amount);

            // @dev transfer any native token
            if (address(this).balance > 0)
                to.call{value: (address(this).balance)}("");

            return;
        }

        // 100000 -> exit gas
        uint256 limit = gasleft() - reserveGas;

        // if swapData.length > 0 try swap
        // else if payloadData.length > 0 try payloadExecutor
        // else {}
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
        }

        // if IERC20 balance transfer to to
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
        // set token amounts
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });
        tokenAmounts[0] = tokenAmount;

        // create an EVM2AnyMesszge struct in memory w/ necessary information for sending message
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
