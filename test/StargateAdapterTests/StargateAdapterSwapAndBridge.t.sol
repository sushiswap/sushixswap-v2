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

    function testSwapFromERC20ToERC20AndBridge() public {
        // basic swap 1 weth to usdc and bridge
        vm.startPrank(operator);
        ERC20(address(weth)).approve(address(sushiXswap), 1 ether);

        (uint256 gasNeeded, ) = stargateAdapter.getFee(
            111, // dstChainId
            1, // functionType
            address(operator), // receiver
            0, // gas
            0, // dustAmount
            "" // payload
        );

        bytes memory computedRoute = routeProcessorHelper.computeRoute(
          false,             // rpHasToken
          false,              // isV2
          address(weth),     // tokenIn
          address(usdc),     // tokenOut
          500,               // fee
          address(stargateAdapter)  // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
            tokenIn: address(weth),
            amountIn: 1 ether,
            tokenOut: address(usdc),
            amountOutMin: 0,
            to: address(stargateAdapter),
            route: computedRoute
        });

       bytes memory rpd_encoded = abi.encode(rpd);

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
                    address(operator), // receiver
                    address(0x00), // to
                    0 // gas
                )
            }),
            rpd_encoded,
            "", // _swapPayload
            "" // _payloadData
        );
    }

    function testSwapFromNativeToERC20AndBridge() public {
        // swap 1 eth to usdc and bridge
        vm.startPrank(operator);
        
        (uint256 gasNeeded , ) = stargateAdapter.getFee(
          111, // dstChainId
          1, // functionType
          address(operator), // receiver
          0, // gas
          0, // dustAmount
          "" // payload
        );

        bytes memory computeRoute = routeProcessorHelper.computeRoute(
          false, // rpHasToken
          false, // isV2
          address(weth), // tokenIn
          address(usdc), // tokenOut
          500, // fee
          address(stargateAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
          tokenIn: NATIVE_ADDRESS,
          amountIn: 1 ether,
          tokenOut: address(usdc),
          amountOutMin: 0,
          to: address(stargateAdapter),
          route: computeRoute
        });

        bytes memory rpd_encoded = abi.encode(rpd);

        uint256 valueNeeded = gasNeeded + 1 ether;
        sushiXswap.swapAndBridge{value: valueNeeded}(
          ISushiXSwapV2.BridgeParams({
            adapter: address(stargateAdapter),
            tokenIn: address(weth), // doesn't matter what you put for bridge params when swapping first
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
              address(operator), // receiver
              address(0x00), // to
              0 // gas
            )
          }),
          rpd_encoded,
          "", // _swapPayload
          "" // _payloadData
        );
    }

    function testSwapFromERC20ToWethAndBridge() public {
      // swap 1 usdc to eth and bridge
      vm.startPrank(operator);
      ERC20(address(usdc)).approve(address(sushiXswap), 1000000);

      (uint256 gasNeeded, ) = stargateAdapter.getFee(
        111, // dstChainId
        1, // functionType
        address(operator), // receiver
        0, // gas
        0, // dustAmount
        "" // payload
      );

      bytes memory computeRoute = routeProcessorHelper.computeRoute(
        false, // rpHasToken
        false, // isV2
        address(usdc), // tokenIn
        address(weth), // tokenOut
        500, // fee
        address(stargateAdapter) // to
      );

      IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
        tokenIn: address(usdc),
        amountIn: 1000000,
        tokenOut: address(weth),
        amountOutMin: 0,
        to: address(stargateAdapter),
        route: computeRoute
      });

      bytes memory rpd_encoded = abi.encode(rpd);


      sushiXswap.swapAndBridge{value: gasNeeded}(
        ISushiXSwapV2.BridgeParams({
          adapter: address(stargateAdapter),
          tokenIn: address(weth), // doesn't matter for bridge params with swapAndBridge
          amountIn: 1 ether,
          to: address(0x0),
          adapterData: abi.encode(
            111, // dstChainId - op
            address(weth), // token
            13, // srcPoolId
            13, // dstPoolId
            0, // amount
            0, // amountMin,
            0, // dustAmount
            address(operator), // receiver
            address(0x00), // to
            0 // gas
          )
        }),
        rpd_encoded,
        "", // _swapPayload
        ""  // _payloadData
      );
    }

    function test_RevertWhen_SwapToNativeAndBridge() public {
      // swap 1 usdc to eth and bridge
      vm.startPrank(operator);
      ERC20(address(usdc)).approve(address(sushiXswap), 1000000);

      (uint256 gasNeeded, ) = stargateAdapter.getFee(
        111, // dstChainId
        1, // functionType
        address(operator), // receiver
        0, // gas
        0, // dustAmount
        "" // payload
      );

      bytes memory computeRoute = routeProcessorHelper.computeRouteNativeOut(
        false, // rpHasToken
        false, // isV2
        address(usdc), // tokenIn
        address(weth), // tokenOut
        500, // fee
        address(stargateAdapter) // to
      );

      IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
        tokenIn: address(usdc),
        amountIn: 1000000,
        tokenOut: NATIVE_ADDRESS,
        amountOutMin: 0,
        to: address(stargateAdapter),
        route: computeRoute
      });

      bytes memory rpd_encoded = abi.encode(rpd);

      //vm.expectRevert(stargateAdapter.RpSentNativeIn.selector);
      vm.expectRevert(bytes4(keccak256("RpSentNativeIn()")));
      sushiXswap.swapAndBridge{value: gasNeeded}(
        ISushiXSwapV2.BridgeParams({
          adapter: address(stargateAdapter),
          tokenIn: address(weth), // doesn't matter for bridge params with swapAndBridge
          amountIn: 1 ether,
          to: address(0x0),
          adapterData: abi.encode(
            111, // dstChainId - op
            NATIVE_ADDRESS, // token
            13, // srcPoolId
            13, // dstPoolId
            0, // amount
            0, // amountMin,
            0, // dustAmount
            address(operator), // receiver
            address(0x00), // to
            0 // gas
          )
        }),
        rpd_encoded,
        "", // _swapPayload
        ""  // _payloadData
      );
    }

}