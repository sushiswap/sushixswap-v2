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

  address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  struct AxelarBridgeParams {
    address sender;
    address token;
    bytes32 destinationChain;
    address destinationAddress;
    bytes32 symbol;
    uint256 amount;
    address refundAddress;  
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
    
  }

  /*function getFee() external view override returns (uint256) {
    return 0;
  }*/

  function adapterBridge(
    bytes calldata _adapterData,
    bytes calldata _swapData,
    bytes calldata _payloadData
  ) external payable override {
    console2.log("getting in adapter");


      AxelarBridgeParams memory params = abi.decode(
        _adapterData,
        (AxelarBridgeParams)
      );

      console2.log("getting past 2nd decode");

      console2.log(params.sender);
      console2.log(params.token);
      console2.log(Bytes32ToString.toTrimmedString(params.destinationChain));
      console2.log(params.destinationAddress);
      console2.log(Bytes32ToString.toTrimmedString(params.symbol));
      console2.log(params.amount);
      console2.log(params.refundAddress);

      IERC20(params.token).safeApprove(
        address(gateway),
        params.amount != 0
          ? params.amount
          : IERC20(params.token).balanceOf(address(this))
      );

      if (_swapData.length == 0 && _payloadData.length == 0) {
        // send token
        gateway.sendToken(
          Bytes32ToString.toTrimmedString(params.destinationChain),
          AddressToString.toString(params.destinationAddress),
          Bytes32ToString.toTrimmedString(params.symbol),
          params.amount
        );
      }

  }

  // receive for axelar
  function executeWithToken(

  ) external {
    
  }

  function sendMessage(bytes calldata _adapterData) external override {
    revert();
  }
}