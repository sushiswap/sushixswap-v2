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
    address _router,  // link messaging router
    address _link,    // LINK address
    address _rp,
    address _weth
  ) CCIPReceiver(_router) {
    // link = _link
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

  }

  /// @inheritdoc ISushiXSwapV2Adapter
  function executePayload(
    uint256 _amountBridged,
    bytes calldata _payloadData,
    address _token
  ) external payable override {

  }

  /// @inheritdoc ISushiXSwapV2Adapter
  function adapterBridge(
    bytes calldata _adapterData,
    address _refundAddress,
    bytes calldata _swapData,
    bytes calldata _payloadData
  ) external payable override {

  }

  // message receiver - ccipReceive
  function _ccipReceive(Client.Any2EVMMessage memory message) internal override {

  }


  /// @inheritdoc ISushiXSwapV2Adapter
  function sendMessage(bytes calldata _adapterData) external override {
    (_adapterData);
    revert();
  }

  receive() external payable {}
}