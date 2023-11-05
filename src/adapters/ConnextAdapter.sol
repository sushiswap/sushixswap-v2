// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "../interfaces/ISushiXSwapV2Adapter.sol";
import "../interfaces/IRouteProcessor.sol";
import "../interfaces/IWETH.sol";

import {IXReceiver} from "connext-interfaces/core/IXReceiver.sol";
import {IConnext} from "connext-interfaces/ICONNEXT.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";



contract ConnextAdapter is ISushiXSwapV2Adapter, IXReceiver {
  using SafeERC20 for IERC20;

  IConnext public immutable;
  IRouteProcessor public immutable rp;
  IWETH public immutable weth;

  address constant NATIVE_ADDRESS =
    0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  struct ConnextBridgeParams {
    uint32 destinationDomain; // connext dst chain id
    address target; // destination address for _execute call
    address to; // address for fallback transfers on _execute call
    address token; // token getting bridged
    uint256 amount; // amount to bridge
    uint256 slippage; // max amount of slippage willing to take in BPS (e.g. 30 = 0.3%)
  }

  error RpSentNativeIn();

  constructor(
    address _connext,
    address _rp,
    address _weth
  ) {
    connext = IConnext(_connext);
    rp = IRouteProcessor(_rp);
    weth = IWETH(_weth);
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

    // todo: getFee - think there is a way to fetch this on-chain


    /// @inheritdoc ISushiXSwapV2Adapter
    function adapterBridge(
      bytes calldata _adapterData,
      address _refundAddress,
      bytes calldata _swapData,
      bytes calldata _payloadData
    ) external payable override {
        ConnextBridgeParams memory params = abi.decode(
            _adapterData,
            (ConnextBridgeParams)
        );

        if (params.token == NATIVE_ADDRESS) {
          // RP should not send native in, since we won't know the exact amount to bridge
          if (params.amount == 0) revert RpSentNativeIn();
          
          weth.deposit{value: params.amount}();
          params.token = address(weth);
        }
        
        if (params.amount == 0)
          params.amount = IERC20(params.token).balanceOf(address(this));
        
        IERC20(params.token).forceApprove(
          address(connext),
          params.amount
        );

        bytes memory payload = bytes("");
        if (_swapData.length > 0 || _payloadData.length > 0) {
            payload = abi.encode(params.to, _swapData, _payloadData);
        }

        connext.xcall{value: address(this).balance} (
          params.destinationDomain,
          params.target,
          params.token,
          _refundAddress,
          params.amount,
          params.slippage,
          payload
        );
    }

    /// @notice receiver function on dst chain
    /// @param _transferId id of the xchain transaction
    /// @param _amount amount of tokeks that were bridged
    /// @param _asset asset that was bridged
    /// @param _originSender address of the sender on the origin chain
    /// @param _origin chain id of the origin chain
    /// @param _calldata data received from source chain
    function xReceive(
      bytes32 _transferId,
      uint256 _amount,
      address _asset,
      address _originSender,
      uint32 _origin,
      bytes memory _callData
    ) external returns (bytes memory) {
        uint256 gasLeft = gasLeft();
        
        // todo: check that msg sender does come from connext contract?

        (address to, bytes memory _swapData, bytes memory _payloadData) = abi
          .decode(payload, (address, bytes, bytes));

        uint256 reserveGas = 100000; 
    }



}