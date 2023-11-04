// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "../interfaces/ISushiXSwapV2Adapter.sol";
import "../interfaces/IRouteProcessor.sol";
import "../interfaces/IWETH.sol";



import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";



contract ConnextAdapter is ISushiXSwapV2Adapter, IXReceiver {
  using SafeERC20 for IERC20;


}