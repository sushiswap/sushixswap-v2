// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Script.sol";
import "../src/SushiXSwapV2.sol";
import "../src/adapters/StargateAdapter.sol";
import "../src/adapters/SquidAdapter.sol";

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
    address stargateRouter = vm.envAddress("STARGATE_ROUTER_ADDRESS");
    address stargateWidget = vm.envAddress("STARGATE_WIDGET_ADDRESS");
    address sgETH = vm.envAddress("SG_ETH_ADDRESS");
    StargateAdapter stargateAdapter = new StargateAdapter(stargateRouter, stargateWidget, sgETH, routeProcesser, weth);

    // deploy squid adapter
    address squidRouter = vm.envAddress("SQUID_ROUTER_ADDRESS");
    SquidAdapter squidAdapter = new SquidAdapter(squidRouter);

    // attach stargate & squid adapter
    sushiXSwap.updateAdapterStatus(address(stargateAdapter), true);
    sushiXSwap.updateAdapterStatus(address(squidAdapter), true);

    // transfer ownership to owner
    // set operators
    sushiXSwap.transferOwnership(_owner);
    //sushiXSwap.setOperator(_operator);
  }
}