// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../interfaces/IRouteProcessor.sol";
import "../interfaces/IWeth.sol";
import "axelar-gmp-sdk-solidity/executable/AxelarExecutable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ISushiXSwapV2Adapter.sol";
import "axelar-gmp-sdk-solidity/interfaces/IAxelarGasService.sol";
import "axelar-gmp-sdk-solidity/interfaces/IAxelarGateway.sol";

import { AddressToString } from "../utils/AddressString.sol";
import { Bytes32ToString } from "../utils/Bytes32String.sol";

import {console2} from "forge-std/console2.sol";

contract AxelarAdapter is ISushiXSwapV2Adapter, AxelarExecutable {
  using SafeERC20 for IERC20;

  IAxelarGasService public immutable axelarGasService;
  IRouteProcessor public immutable rp;
  IWETH public immutable weth;

  // todo: add sibling map by network
  // can swap out destinationAddress stuff if we add siblings

  address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  struct AxelarBridgeParams {
    address token;
    bytes32 destinationChain;
    address destinationAddress;
    bytes32 symbol;
    uint256 amount;
    address refundAddress;
    // express gas bool
    // uint256 gas (we don't need for axelar call, but maybe good habit to make sure caller is accounting for gas)  
  }

  error InsufficientGas();
  error NotAxelarSibiling();
  error RpSentNativeIn();

  constructor(
    address _axelarGateway,
    address _gasService,
    address _rp,
    address _weth
  ) AxelarExecutable(_axelarGateway) {
    axelarGasService = IAxelarGasService(_gasService);
    rp = IRouteProcessor(_rp);
    weth = IWETH(_weth);
  }

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
      // increase token approval to RP
      IERC20(rpd.tokenIn).safeIncreaseAllowance(address(rp), _amountBridged);

      rp.processRoute(
        rpd.tokenIn,
        _amountBridged != 0 ? _amountBridged: rpd.amountIn,
        rpd.tokenOut,
        rpd.amountOutMin,
        rpd.to,
        rpd.route
      );

      // tokens should be sent via rp
      if (_payloadData.length > 0) {
        PayloadData memory pd = abi.decode(_payloadData, (PayloadData));
        try
          IPayloadExecutor(pd.target).onPayloadReceive(pd.targetData)
        {} catch (bytes memory) {
          revert();
        }
      }
  }

  /*function getFee() external view override returns (uint256) {
    return 0;
  }*/

  function adapterBridge(
    bytes calldata _adapterData,
    bytes calldata _swapData,
    bytes calldata _payloadData
  ) external payable override {
      AxelarBridgeParams memory params = abi.decode(
        _adapterData,
        (AxelarBridgeParams)
      );

      // convert native to weth if necessary
      // prob should check if rp sent native in and revert
      // think you can only transfer erc20 (preferablly needs to be usdc)
      if (params.token == NATIVE_ADDRESS) {
        // RP should not send native in, since we won't know the amount from gas passed
        if (params.amount == 0) revert RpSentNativeIn();
        weth.deposit{value: params.amount}();
        params.token = address(weth);
      }

      if (params.amount == 0)
        params.amount = IERC20(params.token).balanceOf(address(this));

      // approve token to gateway
      IERC20(params.token).safeApprove(
        address(gateway),
        params.amount
      );

      // build payload from _swapData and _payloadData
      bytes memory payload = bytes("");
      if (_swapData.length > 0 || _payloadData.length > 0) {
        payload = abi.encode(params.refundAddress, _swapData, _payloadData);
      }

      // pay native gas to gasService (do we want to implement gas express?)
      // do check for 100k min gas first
      //if (params.gas < 100000) revert InsufficientGas();
      axelarGasService.payNativeGasForContractCallWithToken{value: address(this).balance}(
        address(this),
        Bytes32ToString.toTrimmedString(params.destinationChain), 
        AddressToString.toString(params.destinationAddress), 
        payload,
        Bytes32ToString.toTrimmedString(params.symbol),
        params.amount,
        params.refundAddress
      );

      // sendToken and message w/ payload to the gateway contract
      gateway.callContractWithToken(
        Bytes32ToString.toTrimmedString(params.destinationChain),
        AddressToString.toString(params.destinationAddress),
        payload, 
        Bytes32ToString.toTrimmedString(params.symbol),
        params.amount
      );
  }

  // receive for axelar
  function _executeWithToken(
    string memory sourceChain,
    string memory sourceAddress,
    bytes calldata payload,
    string memory tokenSymbol,
    uint256 amount
  ) internal override {      
      (address refundAddress, bytes memory _swapData, bytes memory _payloadData) = abi
        .decode(payload, (address, bytes, bytes));
      address _token = gateway.tokenAddresses(tokenSymbol);

      uint256 reserveGas = 100000;

      if (gasleft() < reserveGas || _swapData.length == 0) {
        IERC20(_token).safeTransfer(refundAddress, amount);

        /// @dev transfer any natvie token
        if (address(this).balance > 0)
          refundAddress.call{value: (address(this).balance)}("");
        
        return;
      }

      // 100000 -> exit gas
      uint256 limit = gasleft() - reserveGas;

      // todo: what if no swapData but there is payload data?
      if (_swapData.length > 0) {
        try
          ISushiXSwapV2Adapter(address(this)).swap{gas: limit}(
            amount,
            _swapData,
            _token,
            _payloadData
          )
        {} catch (bytes memory) {
          IERC20(_token).safeTransfer(refundAddress, amount);
        }
      }

      /// @dev transfer any native token received as dust to the to address
      if (address(this).balance > 0)
        refundAddress.call{value: (address(this).balance)}("");

  }

  function sendMessage(bytes calldata _adapterData) external override {
    (_adapterData);
    revert();
  }

  receive() external payable {}
}