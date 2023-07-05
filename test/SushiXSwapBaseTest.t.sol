// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../src/SushiXSwapV2.sol";
import {StargateAdapter} from "../src/adapters/StargateAdapter.sol";
import {IRouteProcessor} from "../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../utils/BaseTest.sol";
import "../utils/RouteProcessorHelper.sol";

import {StdUtils} from "forge-std/StdUtils.sol";

contract SushiXSwapBaseTest is BaseTest {
    SushiXSwapV2 public sushiXswap;
    StargateAdapter public stargateAdapter;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;

    IWETH public weth;
    ERC20 public sushi;
    ERC20 public usdc;
    
    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public operator = address(0xbeef);
    address public owner = address(0x420);

    function setUp() public override {
        forkMainnet();
        super.setUp();

        weth = IWETH(constants.getAddress("mainnet.weth"));
        sushi = ERC20(constants.getAddress("mainnet.sushi"));
        usdc = ERC20(constants.getAddress("mainnet.usdc"));

        vm.deal(address(operator), 100 ether);
        deal(address(weth), address(operator), 100 ether);
        deal(address(usdc), address(operator), 1 ether);
        deal(address(sushi), address(operator), 1000 ether);

        routeProcessor = IRouteProcessor(
            constants.getAddress("mainnet.routeProcessor")
        );
        routeProcessorHelper = new RouteProcessorHelper(
            constants.getAddress("mainnet.v2Factory"),
            constants.getAddress("mainnet.v3Factory"),
            address(routeProcessor),
            address(weth)
        );

        vm.startPrank(owner);
        sushiXswap = new SushiXSwapV2(routeProcessor, address(weth));

        // add operator as privileged
        sushiXswap.setPrivileged(operator, true);

        // setup stargate adapter
        stargateAdapter = new StargateAdapter(
            constants.getAddress("mainnet.stargateRouter"),
            constants.getAddress("mainnet.stargateWidget"),
            constants.getAddress("mainnet.sgeth"),
            constants.getAddress("mainnet.routeProcessor"),
            constants.getAddress("mainnet.weth")
        );
        sushiXswap.updateAdapterStatus(address(stargateAdapter), true);

        vm.stopPrank();
    }

    function testPause() public {
        vm.startPrank(owner);
        sushiXswap.pause();

        vm.startPrank(operator);
        sushiXswap.pause();
        // operator, paused, sendMesssage call
        vm.expectRevert();
        sushiXswap.sendMessage(address(stargateAdapter), abi.encode(0x01));

        sushiXswap.resume();

        vm.stopPrank();
    }

    function testRescueTokens() public {
        vm.deal(address(sushiXswap), 1 ether);
        deal(address(sushi), address(sushiXswap), 1 ether);

        // reverts if not owner
        vm.prank(operator);
        vm.expectRevert();
        sushiXswap.rescueTokens(NATIVE_ADDRESS, address(owner));

        vm.startPrank(owner);

        // native rescue
        sushiXswap.rescueTokens(NATIVE_ADDRESS, address(owner));
        assertEq(address(owner).balance, 1 ether);

        // erc20 rescue
        sushiXswap.rescueTokens(address(sushi), address(owner));
        assertEq(sushi.balanceOf(address(owner)), 1 ether);
    }

    function testOwnerGuard() public {
        vm.startPrank(operator);

        vm.expectRevert();
        sushiXswap.setPrivileged(address(0x01), true);

        vm.expectRevert();
        sushiXswap.updateAdapterStatus(address(0x01), true);

        vm.expectRevert();
        sushiXswap.updateRouteProcessor(address(0x01));

        vm.startPrank(owner);
        sushiXswap.setPrivileged(address(0x01), true);
        sushiXswap.updateAdapterStatus(address(0x01), true);
        sushiXswap.updateRouteProcessor(address(0x01));
    }

    function testSendMessageStargate() public {
        // sendMessage not implemented for stargate adapter  
        vm.expectRevert();
        sushiXswap.sendMessage(address(stargateAdapter), "");
    }

    function testSwapERC20ToERC20() public {
        // basic swap 1 weth to usdc
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
          false,             // rpHasToken
          false,              // isV2
          address(weth),     // tokenIn
          address(usdc),     // tokenOut
          500,               // fee
          address(operator)  // to
        );

        vm.startPrank(operator);
        ERC20(address(weth)).approve(address(sushiXswap), 1 ether);

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
            tokenIn: address(weth),
            amountIn: 1 ether,
            tokenOut: address(usdc),
            amountOutMin: 0,
            to: address(operator),
            route: computedRoute
        });

        bytes memory rpd_encoded = abi.encode(rpd);

        sushiXswap.swap(
          rpd_encoded
        );
    }

    function testSwapNativeToERC20() public {
      // swap 1 eth to usdc
      bytes memory computedRoute = routeProcessorHelper.computeRoute(
        false,
        false,
        address(weth),
        address(usdc),
        500, 
        address(operator)
      );

      IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
          tokenIn: NATIVE_ADDRESS,
          amountIn: 1 ether,
          tokenOut: address(usdc),
          amountOutMin: 0,
          to: address(operator),
          route: computedRoute
      });

      bytes memory rpd_encoded = abi.encode(rpd);

      vm.startPrank(operator);
      sushiXswap.swap{value: 1 ether} (
        rpd_encoded
      );
    }
}
