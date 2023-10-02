// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Script.sol";
import "../src/SushiXSwapV2.sol";
import "../src/adapters/StargateAdapter.sol";

import "../src/interfaces/IRouteProcessor.sol";

contract DeploySushiXSwapV2 is Script {
  address _owner = vm.envAddress("OWNER_ADDRESS");
  //address _operator = vm.envAddress("OPERATOR_ADDRESS");

  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    // deploy sushiXswapv2
    address routeProcesser = vm.envAddress("ROUTE_PROCESSOR_ADDRESS");
    address weth = vm.envAddress("WETH_ADDRESS");

    SushiXSwapV2 sushiXSwap = new SushiXSwapV2(IRouteProcessor(routeProcesser), weth);
    
    // deploy stargate adapter
    address stargateComposer = vm.envAddress("STARGATE_COMPOSER_ADDRESS");
    address stargateWidget = vm.envAddress("STARGATE_WIDGET_ADDRESS");
    address sgETH = vm.envAddress("SG_ETH_ADDRESS");
    StargateAdapter stargateAdapter = new StargateAdapter(stargateComposer, stargateWidget, sgETH, routeProcesser, weth);

    // attach stargate & squid adapter
    sushiXSwap.updateAdapterStatus(address(stargateAdapter), true);

    // transfer ownership to owner
    // set operators
    sushiXSwap.transferOwnership(_owner);
    //sushiXSwap.setOperator(_operator);
  }
}