// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../interfaces/IRouteProcessor.sol";
import "../interfaces/IWeth.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ISushiXSwapV2Adapter.sol";
import "../interfaces/AxelarExecutable.sol";
import "../interfaces/IAxelarGasService.sol";
import "../interfaces/IAxelarGateway.sol";

contract AxelarAdapter is ISushiXSwapV2Adapter, IAxelarExecutable {
  using SafeERC20 for IERC20;


  IRouteProcessor public immutable rp;
  IWETH public immutable weth;

  address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  struct AxelarBridgeParams {

  }

  error InsufficientGas();
  error NotAxelarSibiling();
  error RpSentNativeIn();

  constructor(
    address _rp,
    address _weth
  ) {
    rp = IRouteProcessor(_rp);
    weth = IWETH(_weth);
  }

  function swap(
    uint256 _amountBridged,
    bytes calldata _swapData,
    address _token,
    bytes calldata _payloadData
  ) external payable override {
    
  }

  function getFee() external view override returns (uint256) {
    return 0;
  }

  function adapterBridge(
    bytes calldata _adapterData,
    bytes calldata _swapData,
    bytes calldata _payloadData
  ) external payable override {

  }

  // receive for axelar
  function executeWithToken(

  ) external {

  }

  function sendMessage(bytes calldata _adapterData) external override {
    revert();
  }
}