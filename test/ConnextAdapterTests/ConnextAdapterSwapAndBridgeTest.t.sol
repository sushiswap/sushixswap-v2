// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {ConnextAdapter} from "../../src/adapters/ConnextAdapter.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

contract ConnextAdapterSwapAndBridgeTest is BaseTest {
    using SafeERC20 for IERC20;

    SushiXSwapV2 public sushiXswap;
    ConnextAdapter public connextAdapter;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;

    IWETH public weth;
    IERC20 public sushi;
    IERC20 public usdc;
    IERC20 public usdt;

    uint32 opDestinationDomain = 1869640809;

    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public operator = address(0xbeef);
    address public owner = address(0x420);
    address public user = address(0x4201);

    function setUp() public override {
        forkMainnet();
        super.setUp();

        weth = IWETH(constants.getAddress("mainnet.weth"));
        sushi = IERC20(constants.getAddress("mainnet.sushi"));
        usdc = IERC20(constants.getAddress("mainnet.usdc"));
        usdt = IERC20(constants.getAddress("mainnet.usdt"));

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

        connextAdapter = new ConnextAdapter(
            constants.getAddress("mainnet.connext"),
            constants.getAddress("mainnet.routeProcessor"),
            constants.getAddress("mainnet.weth")
        );
        sushiXswap.updateAdapterStatus(address(connextAdapter), true);

        vm.stopPrank();
    }

    function test_SwapFromERC20ToERC20AndBridgeConnext() public {
        // basic swap 1 weth to usdc and bridge
        uint64 amount = 1 ether; // 1 weth
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(weth), user, amount);
        vm.deal(user, gasNeeded);

        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true, // rpHasToken
            false, // isV2
            address(weth), // tokenIn
            address(usdc), // tokenOut
            500, // fee
            address(connextAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(weth),
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: address(connextAdapter),
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory adapterData = abi.encode(
            opDestinationDomain, // dst domain
            address(user), // target
            address(user), // address for fallback transfers
            address(usdc), // token to bridge
            0, // amount to bridge - 0 since swap first
            300 // slippage tolerance, 3%
        );

        vm.startPrank(user);
        IERC20(address(weth)).safeIncreaseAllowance(
            address(sushiXswap),
            amount
        );

        sushiXswap.swapAndBridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(connextAdapter),
                tokenIn: address(weth),
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // _refundAddress
            rpd_encoded, // swap data
            "", // swap payload data
            "" // payload data
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            weth.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_SwapFromERC20ToUSDTAndBridge() public {
        uint32 amount = 1000000; // 1 usdt

        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(usdt), user, amount);
        vm.deal(user, gasNeeded);

        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true, // rpHasToken
            false, // isV2
            address(usdt), // tokenIn
            address(usdc), // tokenOut
            100, // fee
            address(connextAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdt),
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: address(connextAdapter),
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory adapterData = abi.encode(
            opDestinationDomain, // dst domain
            address(user), // target
            address(user), // address for fallback transfers
            address(usdc), // token to bridge
            0, // amouint to bridge
            300 // slippage tolerance, 3%
        );

        vm.startPrank(user);
        IERC20(address(usdt)).safeIncreaseAllowance(
            address(sushiXswap),
            amount
        );

        sushiXswap.swapAndBridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(connextAdapter),
                tokenIn: address(usdt),
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // _refundAddress
            rpd_encoded, // swap data
            "", // swap payload data
            "" // payload data
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            usdt.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdt"
        );
    }

    function test_SwapFromNativeToERC20AndBridge() public {
        // basic swap 1 eth to usdc and bridge
        uint64 amount = 1 ether; // 1 eth
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        uint256 valueToSend = amount + gasNeeded;
        vm.deal(user, valueToSend);

        bytes memory computeRoute = routeProcessorHelper.computeRouteNativeIn(
            address(weth), // wrapToken
            false, // isV2
            address(usdc), // tokenOut
            500, // fee
            address(connextAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: address(connextAdapter),
                route: computeRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory adapterData = abi.encode(
            opDestinationDomain, // dst domain
            address(user), // target
            address(user), // address for fallback transfers
            address(usdc), // token to bridge
            0, // amouint to bridge
            300 // slippage tolerance, 3%
        );

        vm.startPrank(user);
        sushiXswap.swapAndBridge{value: valueToSend}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(connextAdapter),
                tokenIn: NATIVE_ADDRESS, // doesn't matter what you put for bridge params when swapping first
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // _refundAddress
            rpd_encoded, // swap data
            "", // swap payload data
            "" // payload data
        );

        assertEq(
            address(connextAdapter).balance,
            0,
            "connextAdapter should have 0 eth"
        );
        assertEq(user.balance, 0, "user should have 0 eth");
        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
    }

    function test_RevertWhen_SwapFromERC20ToNativeAndBridge() public {
        // basic swap 1 usdc to native and bridge
        uint32 amount = 1000000; // 1 usdc
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(usdc), user, amount);
        vm.deal(user, gasNeeded);

        bytes memory computeRoute = routeProcessorHelper.computeRouteNativeOut(
            true, // rpHasToken
            false, // isV2
            address(usdc), // tokenIn
            address(weth), // tokenOut
            500, // fee
            address(connextAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: NATIVE_ADDRESS,
                amountOutMin: 0,
                to: address(connextAdapter),
                route: computeRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory adapterData = abi.encode(
            opDestinationDomain, // dst domain
            address(user), // target
            address(user), // address for fallback transfers
            NATIVE_ADDRESS, // token to bridge
            0, // amouint to bridge
            300 // slippage tolerance, 3%
        );

        vm.startPrank(user);
        IERC20(address(usdc)).safeIncreaseAllowance(
            address(sushiXswap),
            amount
        );

        vm.expectRevert(bytes4(keccak256("RpSentNativeIn()")));
        sushiXswap.swapAndBridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(connextAdapter),
                tokenIn: address(weth), // doesn't matter what you put for bridge params when swapping first
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // _refundAddress
            rpd_encoded, // swap data
            "", // swap payload data
            "" // payload data
        );
    }
}
