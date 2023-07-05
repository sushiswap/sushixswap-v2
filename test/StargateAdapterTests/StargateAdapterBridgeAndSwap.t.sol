// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {StargateAdapter} from "../../src/adapters/StargateAdapter.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

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

     //todo: we can prob get better than this with LZEndpointMock
    //      and then switch chains to test the receive
    // https://github.com/LayerZero-Labs/solidity-examples/blob/8e62ebc886407aafc89dbd2a778e61b7c0a25ca0/contracts/mocks/LZEndpointMock.sol
    function testSimpleReceiveAndSwap() public {
      // receive 1 usdc and swap to weth
      vm.prank(operator);
      usdc.transfer(address(stargateAdapter), 1000000);

      bytes memory computedRoute = routeProcessorHelper.computeRoute(
        false,
        false,
        address(usdc),
        address(weth),
        500,
        address(operator)
      );

      IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
          tokenIn: address(usdc),
          amountIn: 1000000,
          tokenOut: address(weth),
          amountOutMin: 0,
          to: address(operator),
          route: computedRoute
      });

      bytes memory rpd_encoded = abi.encode(rpd);

      bytes memory payload = abi.encode(
        address(operator),  // to
        rpd_encoded,        // _swapData
        ""                  // _payloadData 
      );
      
      vm.prank(constants.getAddress("mainnet.stargateRouter"));
      stargateAdapter.sgReceive(
        0, "", 0,
        address(usdc),
        1000000,
        payload
      );
      
    }

    function testNativeBridgeReceiveAndSwap() public {
      // bridge 1 eth - swap weth to usdc
      vm.startPrank(operator);

      bytes memory computedRoute_dst = routeProcessorHelper.computeRoute(
        false,
        false,
        address(weth),
        address(usdc),
        500,
        address(operator)
      );

      IRouteProcessor.RouteProcessorData memory rpd_dst = IRouteProcessor.RouteProcessorData({
          tokenIn: address(weth),
          amountIn: 0,  // amountIn doesn't matter on dst since we use amount bridged
          tokenOut: address(usdc),
          amountOutMin: 0,
          to: address(operator),
          route: computedRoute_dst
      });

      bytes memory rpd_encoded_dst = abi.encode(rpd_dst);

      bytes memory mockPayload = abi.encode(
        address(operator),  // to
        rpd_encoded_dst,    // _swapData
        ""                  // _payloadData 
      );

      uint256 gasForSwap = 500000;

      (uint256 gasNeeded, ) = stargateAdapter.getFee(
        111, // dstChainId
        1, // functionType
        address(operator), // receiver
        gasForSwap, // gas
        0, // dustAmount
        mockPayload // payload
      );

      // todo: need to figure out how to get EqFee or mock it
      // assumption that 0.1 eth will be taken for fee so amountIn is 0.9eth
      uint256 valueToSend = gasNeeded + 1 ether;
      sushiXswap.bridge{value: valueToSend}(
        ISushiXSwapV2.BridgeParams({
          adapter: address(stargateAdapter),
          tokenIn: NATIVE_ADDRESS,
          amountIn: 1 ether,
          to: address(0x0),
          adapterData: abi.encode(
            111, // dstChainId - op
            NATIVE_ADDRESS, // token
            13, // srcPoolId
            13, // dstPoolId
            900000000000000000, // amount
            0, // amountMin,
            0, // dustAmount
            address(stargateAdapter), // receiver
            address(operator), // to
            500000 // gas
          )
        }),
        "", // _swapPayload
        mockPayload // _payloadData
      );

      // mock the sgReceive
      // using 1 eth for the receive (in prod env it will be less due to eqFee)
      address(stargateAdapter).call{value: 1 ether}("");
      vm.stopPrank();

      vm.startPrank(constants.getAddress("mainnet.stargateRouter"));
      stargateAdapter.sgReceive{gas: gasForSwap}(
        0, "", 0,
        constants.getAddress("mainnet.sgeth"),
        1 ether,
        mockPayload
      );
    }

    function testSwapAndBridgeReceiveAndSwap() public {
      // swap weth to usdc - bridge usdc - swap usdc to weth
      vm.startPrank(operator);
      ERC20(address(weth)).approve(address(sushiXswap), 1 ether);

      // routes for first swap on src
      bytes memory computedRoute_src = routeProcessorHelper.computeRoute(
        false,             // rpHasToken
        false,              // isV2
        address(weth),     // tokenIn
        address(usdc),     // tokenOut
        500,               // fee
        address(stargateAdapter)  // to
      );

      IRouteProcessor.RouteProcessorData memory rpd_src = IRouteProcessor.RouteProcessorData({
          tokenIn: address(weth),
          amountIn: 1 ether,
          tokenOut: address(usdc),
          amountOutMin: 0,
          to: address(stargateAdapter),
          route: computedRoute_src
      });

      bytes memory computedRoute_dst = routeProcessorHelper.computeRoute(
        false,             // rpHasToken
        false,              // isV2
        address(usdc),     // tokenIn
        address(weth),     // tokenOut
        500,               // fee
        address(operator)  // to
      );

      IRouteProcessor.RouteProcessorData memory rpd_dst = IRouteProcessor.RouteProcessorData({
          tokenIn: address(usdc),
          amountIn: 0,  // amountIn doesn't matter on dst since we use amount bridged
          tokenOut: address(weth),
          amountOutMin: 0,
          to: address(operator),
          route: computedRoute_dst
      });

      bytes memory rpd_encoded_src = abi.encode(rpd_src);
      bytes memory rpd_encoded_dst = abi.encode(rpd_dst);

      bytes memory mockPayload = abi.encode(
        address(operator),  // to
        rpd_encoded_dst,    // _swapData
        ""                  // _payloadData 
      );

      uint256 gasForSwap = 250000;

      (uint256 gasNeeded, ) = stargateAdapter.getFee(
        111, // dstChainId
        1, // functionType
        address(operator), // receiver
        gasForSwap, // gas
        0, // dustAmount
        mockPayload // payload
      );

      sushiXswap.swapAndBridge{value: gasNeeded}(
        ISushiXSwapV2.BridgeParams({
          adapter: address(stargateAdapter),
          tokenIn: address(weth),
          amountIn: 1 ether,
          to: address(0x0),
          adapterData: abi.encode(
            111, // dstChainId - op
            address(usdc), // token
            1, // srcPoolId
            1, // dstPoolId
            0, // amount
            0, // amountMin,
            0, // dustAmount
            address(stargateAdapter), // receiver
            address(operator), // to
            gasForSwap // gas
          )
        }),
        rpd_encoded_src,
        rpd_encoded_dst, // _swapPayload
        "" // _payloadData
      );

      // mock the sgReceive
      // using random amount of usdc for the receive
      // prob should have event for bridges, and then we can use that in this test
      usdc.transfer(address(stargateAdapter), 1000000);
      vm.prank(constants.getAddress("mainnet.stargateRouter"));
      // todo: need a better way to figure out to calculate & send proper gas
      stargateAdapter.sgReceive{gas: gasForSwap}(
        0, "", 0,
        address(usdc),
        1000000,
        mockPayload
      );

    }

}