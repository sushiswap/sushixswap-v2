// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../interfaces/IRouteProcessor.sol";
import "axelar-gmp-sdk-solidity/executable/AxelarExecutable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/ISushiXSwapV2Adapter.sol";
import "axelar-gmp-sdk-solidity/interfaces/IAxelarGasService.sol";
import "axelar-gmp-sdk-solidity/interfaces/IAxelarGateway.sol";

import {ITokenMessenger} from "../interfaces/cctp/ITokenMessenger.sol";

import { AddressToString } from "../utils/AddressString.sol";
import { Bytes32ToString } from "../utils/Bytes32String.sol";

import {console2} from "forge-std/console2.sol";

contract CCTPAdapter is ISushiXSwapV2Adapter, AxelarExecutable {
  using SafeERC20 for IERC20;

  IAxelarGasService public immutable axelarGasService;
  ITokenMessenger public immutable tokenMessenger;
  IRouteProcessor public immutable rp;
  IERC20 public immutable nativeUSDC;

  // todo: add sibling map by network
  // can swap out destinationAddress stuff if we do siblings
  
  mapping(string => uint32) public circleDestinationDomains;

  struct CCTPBridgeParams {
    bytes32 destinationChain;
    address destinationAddress;
    uint256 amount;
    address refundAddress;
    // express gas bool
    // uint256 gas
  }

  error InsufficientGas();
  error NoUSDCToBridge();

  constructor(
    address _axelarGateway,
    address _gasService,
    address _tokenMessenger,
    address _rp,
    address _nativeUSDC
  ) AxelarExecutable(_axelarGateway) {
    axelarGasService = IAxelarGasService(_gasService);
    tokenMessenger = ITokenMessenger(_tokenMessenger);
    rp = IRouteProcessor(_rp);
    nativeUSDC = IERC20(_nativeUSDC);
    
    // not an ownable contract, and adapters are swapable
    // so we hardcode the circle supported chains
    circleDestinationDomains["ethereum"] = 0;
    circleDestinationDomains["avalanche"] = 1;
    circleDestinationDomains["arbitrum"] = 3;
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


  function adapterBridge(
    bytes calldata _adapterData,
    bytes calldata _swapData,
    bytes calldata _payloadData
  ) external payable override {
      CCTPBridgeParams memory params = abi.decode(
        _adapterData,
        (CCTPBridgeParams)
      );

      if (nativeUSDC.balanceOf(address(this)) <= 0) 
        revert NoUSDCToBridge();

      if (params.amount == 0)
        params.amount = nativeUSDC.balanceOf(address(this));
      
      // burn params.amount of USDC tokens
      nativeUSDC.safeApprove(address(tokenMessenger), params.amount);

      tokenMessenger.depositForBurn(
        params.amount,
        this.circleDestinationDomains(Bytes32ToString.toTrimmedString(params.destinationChain)),
        bytes32(uint256(uint160(params.destinationAddress))),
        address(nativeUSDC)
      );

      // build payload from _swapData and _payloadData
      bytes memory payload = abi.encode(params.refundAddress, params.amount, _swapData, _payloadData);

      // pay native gas to gasService
      axelarGasService.payNativeGasForContractCall{value: address(this).balance}(
        address(this),
        Bytes32ToString.toTrimmedString(params.destinationChain),
        AddressToString.toString(params.destinationAddress),
        payload,
        params.refundAddress
      );

      // send message w/ paylod to the gateway contract
      gateway.callContract(
        Bytes32ToString.toTrimmedString(params.destinationChain),
        AddressToString.toString(params.destinationAddress),
        payload
      );
  }

  // receive for axelar
  function _execute(
    string memory /*sourceChain*/,
    string memory /*sourceAddress*/,
    bytes calldata payload
  ) internal override {
      (address refundAddress, uint256 amount, bytes memory _swapData, bytes memory _payloadData) = abi.decode(
        payload,
        (address, uint256, bytes, bytes)
      );

      uint256 reserveGas = 100000;

      if (gasleft() < reserveGas || _swapData.length == 0) {
        nativeUSDC.safeTransfer(refundAddress, amount);

        /// @dev transfer any native token
        // shouldn't actually have native in here but we return if it does come in
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
            address(nativeUSDC),
            _payloadData
          )
        {} catch (bytes memory) {
          nativeUSDC.safeTransfer(refundAddress, amount);
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



