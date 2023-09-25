// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {StargateAdapter} from "../../src/adapters/StargateAdapter.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

import {StdUtils} from "forge-std/StdUtils.sol";

contract StargateAdapterSwapAndBridgeTest is BaseTest {
    using SafeERC20 for IERC20;

    SushiXSwapV2 public sushiXswap;
    StargateAdapter public stargateAdapter;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;

    IWETH public weth;
    IERC20 public sushi;
    IERC20 public usdc;
    IERC20 public usdt;

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
            constants.getAddress("mainnet.stargateComposer"),
            constants.getAddress("mainnet.stargateWidget"),
            constants.getAddress("mainnet.sgeth"),
            constants.getAddress("mainnet.routeProcessor"),
            constants.getAddress("mainnet.weth")
        );
        sushiXswap.updateAdapterStatus(address(stargateAdapter), true);

        vm.stopPrank();
    }

    function test_SwapFromERC20ToERC20AndBridge() public {
        uint64 amount = 1 ether;
        // basic swap 1 weth to usdc and bridge
        deal(address(weth), user, amount);
        vm.deal(user, 0.1 ether);

        (uint256 gasNeeded, ) = stargateAdapter.getFee(
            111, // dstChainId
            1, // functionType
            user, // receiver
            0, // gas
            0, // dustAmount
            "" // payload
        );

        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true, // rpHasToken
            false, // isV2
            address(weth), // tokenIn
            address(usdc), // tokenOut
            500, // fee
            address(stargateAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(weth),
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: address(stargateAdapter),
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        vm.startPrank(user);
        IERC20(address(weth)).safeIncreaseAllowance(address(sushiXswap), amount);

        sushiXswap.swapAndBridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(stargateAdapter),
                tokenIn: address(weth),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    111, // dstChainId - op
                    address(usdc), // token
                    1, // srcPoolId
                    1, // dstPoolId
                    0, // amount
                    0, // amountMin,
                    0, // dustAmount
                    user, // receiver
                    address(0x00), // to
                    0 // gas
                )
            }),
            user, // _refundAddress
            rpd_encoded, // _swapData
            "", // _swapPayload
            "" // _payloadData
        );

        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(usdc.balanceOf(address(sushiXswap)), 0, "xswap should have 0 usdc");
        assertEq(usdc.balanceOf(address(stargateAdapter)), 0, "stargateAdapter should have 0 usdc");
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertEq(weth.balanceOf(address(sushiXswap)), 0, "xSwap should have 0 weth");
        assertEq(weth.balanceOf(address(stargateAdapter)), 0, "stargateAdapter should have 0 weth");
    }

    function test_SwapFromUSDTToERC20AndBridge(uint32 amount) public {
        vm.assume(amount > 1000000); // > 1 usdt
        
        deal(address(usdt), user, amount);
        vm.deal(user, 0.1 ether);

        (uint256 gasNeeded, ) = stargateAdapter.getFee(
            110, // dstChainId
            1, // functionType
            user, // receiver
            0, // gas
            0, // dustAmount
            "" // payload
        );

        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true, // rpHasToken
            false, // isV2
            address(usdt), // tokenIn
            address(usdc), // tokenOut
            100, // fee
            address(stargateAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdt),
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: address(stargateAdapter),
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);
        
        vm.startPrank(user);
        IERC20(address(usdt)).safeIncreaseAllowance(address(sushiXswap), amount);

        sushiXswap.swapAndBridge{value: 0.1 ether}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(stargateAdapter),
                tokenIn: address(usdt),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    110, // dstChainId - op
                    address(usdc), // token
                    1, // srcPoolId
                    1, // dstPoolId
                    0, // amount
                    0, // amountMin,
                    0, // dustAmount
                    user, // receiver
                    address(0x00), // to
                    0 // gas
                )
            }),
            user, // _refundAddress
            rpd_encoded, // _swapData
            "", // _swapPayload
            "" // _payloadData
        );

        assertEq(usdt.balanceOf(user), 0, "user should have 0 usdt");
        assertEq(usdt.balanceOf(address(sushiXswap)), 0, "xswap should have 0 usdt");
        assertEq(usdt.balanceOf(address(stargateAdapter)), 0, "stargateAdapter should have 0 usdt");
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(usdc.balanceOf(address(sushiXswap)), 0, "xSwap should have 0 usdc");
        assertEq(usdc.balanceOf(address(stargateAdapter)), 0, "stargateAdapter should have 0 usdc");
    }

    function test_SwapFromERC20ToUSDTAndBridge(uint32 amount) public {
        vm.assume(amount > 1000000); // > 1 usdc
        
        deal(address(usdc), user, amount);
        vm.deal(user, 0.1 ether);

        (uint256 gasNeeded, ) = stargateAdapter.getFee(
            110, // dstChainId
            1, // functionType
            user, // receiver
            0, // gas
            0, // dustAmount
            "" // payload
        );

        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true, // rpHasToken
            false, // isV2
            address(usdc), // tokenIn
            address(usdt), // tokenOut
            100, // fee
            address(stargateAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(usdt),
                amountOutMin: 0,
                to: address(stargateAdapter),
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);
        
        vm.startPrank(user);
        IERC20(address(usdc)).safeIncreaseAllowance(address(sushiXswap), amount);

        sushiXswap.swapAndBridge{value: 0.1 ether}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(stargateAdapter),
                tokenIn: address(usdc),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    110, // dstChainId - op
                    address(usdt), // token
                    2, // srcPoolId
                    2, // dstPoolId
                    0, // amount
                    0, // amountMin,
                    0, // dustAmount
                    user, // receiver
                    address(0x00), // to
                    0 // gas
                )
            }),
            user, // _refundAddress
            rpd_encoded, // _swapData
            "", // _swapPayload
            "" // _payloadData
        );

        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(usdc.balanceOf(address(sushiXswap)), 0, "xswap should have 0 usdc");
        assertEq(usdc.balanceOf(address(stargateAdapter)), 0, "stargateAdapter should have 0 usdc");
        assertEq(usdt.balanceOf(user), 0, "user should have 0 usdt");
        assertEq(usdt.balanceOf(address(sushiXswap)), 0, "xSwap should have 0 usdt");
        assertEq(usdt.balanceOf(address(stargateAdapter)), 0, "stargateAdapter should have 0 usdt");
    }

    function test_SwapFromNativeToERC20AndBridge() public {
        uint64 amount = 1 ether;
        uint64 gasAmount = 0.1 ether;
        
        uint256 valueToSend = uint256(amount) + gasAmount;
        vm.deal(user, valueToSend);

        (uint256 gasNeeded, ) = stargateAdapter.getFee(
            111, // dstChainId
            1, // functionType
            user, // receiver
            0, // gas
            0, // dustAmount
            "" // payload
        );

        bytes memory computeRoute = routeProcessorHelper.computeRouteNativeIn(
            address(weth), // wrapToken
            false, // isV2
            address(usdc), // tokenOut
            500, // fee
            address(stargateAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: address(stargateAdapter),
                route: computeRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);
        
        vm.startPrank(user);
        sushiXswap.swapAndBridge{value: valueToSend}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(stargateAdapter),
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    111, // dstChainId - op
                    address(usdc), // token
                    1, // srcPoolId
                    1, // dstPoolId
                    0, // amount
                    0, // amountMin,
                    0, // dustAmount
                    user, // receiver
                    address(0x00), // to
                    0 // gas
                )
            }),
            user, // _refundAddress
            rpd_encoded, // _swapData
            "", // _swapPayload
            "" // _payloadData
        );

        assertGt(user.balance, 0, "user should have refund amount of native");
        assertLt(user.balance, gasAmount, "user should not have more than gas sent of native");
        assertEq(address(sushiXswap).balance, 0, "xswap should have 0 native");
        assertEq(address(stargateAdapter).balance, 0, "stargateAdapter should have 0 native");
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(usdc.balanceOf(address(sushiXswap)), 0, "xSwap should have 0 usdc");
        assertEq(usdc.balanceOf(address(stargateAdapter)), 0, "stargateAdapter should have 0 usdc");
    }

    function test_SwapFromERC20ToWethAndBridge() public {
        uint32 amount = 1000000;
        // swap 1 usdc to eth and bridge
        deal(address(usdc), user, amount);
        vm.deal(user, 0.1 ether);

        (uint256 gasNeeded, ) = stargateAdapter.getFee(
            111, // dstChainId
            1, // functionType
            user, // receiver
            0, // gas
            0, // dustAmount
            "" // payload
        );

        bytes memory computeRoute = routeProcessorHelper.computeRoute(
            true, // rpHasToken
            false, // isV2
            address(usdc), // tokenIn
            address(weth), // tokenOut
            500, // fee
            address(stargateAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: address(stargateAdapter),
                route: computeRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        vm.startPrank(user);
        IERC20(address(usdc)).safeIncreaseAllowance(address(sushiXswap), amount);

        sushiXswap.swapAndBridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(stargateAdapter),
                tokenIn: address(usdc),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    111, // dstChainId - op
                    address(weth), // token
                    13, // srcPoolId
                    13, // dstPoolId
                    0, // amount
                    0, // amountMin,
                    0, // dustAmount
                    user, // receiver
                    address(0x00), // to
                    0 // gas
                )
            }),
            user, // _refundAddress
            rpd_encoded, // _swapData
            "", // _swapPayload
            "" // _payloadData
        );

        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(usdc.balanceOf(address(sushiXswap)), 0, "xswap should have 0 usdc");
        assertEq(usdc.balanceOf(address(stargateAdapter)), 0, "stargateAdapter should have 0 usdc");
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertEq(weth.balanceOf(address(sushiXswap)), 0, "xSwap should have 0 weth");
        assertEq(weth.balanceOf(address(stargateAdapter)), 0, "stargateAdapter should have 0 weth");
    }

    function test_RevertWhen_SwapToNativeAndBridge() public {
        // swap 1 usdc to eth and bridge
        uint64 amount = 1 ether;

        deal(address(usdc), user, amount);
        vm.deal(user, 0.1 ether);

        (uint256 gasNeeded, ) = stargateAdapter.getFee(
            111, // dstChainId
            1, // functionType
            user, // receiver
            0, // gas
            0, // dustAmount
            "" // payload
        );

        bytes memory computeRoute = routeProcessorHelper.computeRouteNativeOut(
            true, // rpHasToken
            false, // isV2
            address(usdc), // tokenIn
            address(weth), // tokenOut
            500, // fee
            address(stargateAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: 1000000,
                tokenOut: NATIVE_ADDRESS,
                amountOutMin: 0,
                to: address(stargateAdapter),
                route: computeRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        vm.startPrank(user);
        IERC20(address(usdc)).safeIncreaseAllowance(address(sushiXswap), amount);

        vm.expectRevert(bytes4(keccak256("RpSentNativeIn()")));
        sushiXswap.swapAndBridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(stargateAdapter),
                tokenIn: address(usdc), // doesn't matter for bridge params with swapAndBridge
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    111, // dstChainId - op
                    NATIVE_ADDRESS, // token
                    13, // srcPoolId
                    13, // dstPoolId
                    0, // amount
                    0, // amountMin,
                    0, // dustAmount
                    user, // receiver
                    address(0x00), // to
                    0 // gas
                )
            }),
            user, // _refundAddress
            rpd_encoded, // _swapData
            "", // _swapPayload
            "" // _payloadData
        );
    }
}
