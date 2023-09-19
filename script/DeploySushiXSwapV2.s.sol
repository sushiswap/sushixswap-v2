// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-deploy/DeployScript.sol";
import {DeployerFunctions, DeployOptions} from "generated/deployer/DeployerFunctions.g.sol";

import "../src/SushiXSwapV2.sol";
import "../src/adapters/StargateAdapter.sol";
import "../src/interfaces/IRouteProcessor.sol";

contract DeploySushiXSwapV2 is DeployScript {
  using DeployerFunctions for Deployer;

  address _owner = vm.envAddress("OWNER_ADDRESS");
  //address _operator = vm.envAddress("OPERATOR_ADDRESS");

  function deploy() external returns (SushiXSwapV2) {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    // deploy sushiXswapv2
    address routeProcesser = vm.envAddress("ROUTE_PROCESSOR_ADDRESS");
    address weth = vm.envAddress("WETH_ADDRESS");
    SushiXSwapV2 sushiXSwap = deployer.deploy_SushiXSwapV2("SushiXSwapV2", IRouteProcessor(routeProcesser), weth);
    
    // deploy stargate adapter
    address stargateRouter = vm.envAddress("STARGATE_ROUTER_ADDRESS");
    address stargateWidget = vm.envAddress("STARGATE_WIDGET_ADDRESS");
    address sgETH = vm.envAddress("SG_ETH_ADDRESS");
    StargateAdapter stargateAdapter = deployer.deploy_StargateAdapter("StargateAdapter", stargateRouter, stargateWidget, sgETH, routeProcesser, weth);

    vm.startBroadcast(deployerPrivateKey);

    // attach stargate & squid adapter
    sushiXSwap.updateAdapterStatus(address(stargateAdapter), true);

    // transfer ownership to owner
    sushiXSwap.transferOwnership(_owner);

    // set operators
    //sushiXSwap.setOperator(_operator);
  }
}