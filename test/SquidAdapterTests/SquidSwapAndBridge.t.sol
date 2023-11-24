// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {SquidAdapter} from "../../src/adapters/SquidAdapter.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {ISquidRouter} from "../../src/interfaces/squid/ISquidRouter.sol";
import {ISquidMulticall} from "../../src/interfaces/squid/ISquidMulticall.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

import {StringToBytes32, Bytes32ToString} from "../../src/utils/Bytes32String.sol";
import {StringToAddress, AddressToString} from "../../src/utils/AddressString.sol";

import {console2} from "forge-std/console2.sol";

contract SquidSwapAndBridgeTest is BaseTest {
    using SafeERC20 for IERC20;
    using AddressToString for address;

    SushiXSwapV2 public sushiXswap;
    SquidAdapter public squidAdapter;
    ISquidRouter public squidRouter;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;

    IWETH public weth;
    IERC20 public sushi;
    IERC20 public usdc;
    IERC20 public usdt;

    address constant NATIVE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
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

        routeProcessor = IRouteProcessor(constants.getAddress("mainnet.routeProcessor"));

        routeProcessorHelper = new RouteProcessorHelper(
            constants.getAddress("mainnet.v2Factory"),
            constants.getAddress("mainnet.v3Factory"),
            address(routeProcessor),
            address(weth)
        );

        squidRouter = ISquidRouter(constants.getAddress("mainnet.squidRouter"));

        vm.startPrank(owner);
        sushiXswap = new SushiXSwapV2(routeProcessor, address(weth));

        // add operator as privileged
        sushiXswap.setPrivileged(operator, true);

        // setup squid adapter
        squidAdapter = new SquidAdapter(
            constants.getAddress("mainnet.squidRouter")
        );

        sushiXswap.updateAdapterStatus(address(squidAdapter), true);
        vm.stopPrank();
    }

    function test_SwapFromERC20ToERC20AndBridge() public {
        // basic swap 1 weth to usdc and bridge
        uint64 amount = 1 ether; // 1 weth
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(weth), user, amount);
        vm.deal(user, gasNeeded);

        bytes memory srcRoute = routeProcessorHelper.computeRoute(
            true, // rpHasToken
            false, // isV2
            address(weth), // tokenIn
            address(usdc), // tokenOut
            500, // fee
            address(squidRouter) // to
        );

        IRouteProcessor.RouteProcessorData memory srcSwapData = IRouteProcessor.RouteProcessorData({
            tokenIn: address(weth),
            amountIn: amount,
            tokenOut: address(usdc),
            amountOutMin: 0,
            to: address(squidRouter),
            route: srcRoute
        });

        ISquidMulticall.Call[] memory dstCalls = new ISquidMulticall.Call[](1);
        dstCalls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.Default,
            target: constants.getAddress("arbitrum.axlUSDC"),
            value: 0,
            callData: abi.encodeWithSelector(usdc.transferFrom.selector, address(squidRouter), address(user), amount),
            payload: ""
        });

        bytes memory dstPayload = abi.encode(dstCalls, user);

        bytes memory squidRouterCallData = abi.encodeWithSelector(
            squidRouter.bridgeCall.selector,
            "USDC",
            0,
            "arbitrum",
            address(squidRouter).toString(),
            dstPayload,
            user,
            false
        );

        vm.startPrank(user);
        IERC20(address(weth)).safeIncreaseAllowance(address(sushiXswap), amount);

        sushiXswap.swapAndBridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(squidAdapter),
                tokenIn: address(weth),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    address(usdc), // token
                    squidRouterCallData
                    )
            }),
            user, // _refundAddress
            abi.encode(srcSwapData), // swap data
            "", // swap payload data
            "" // payload data
        );

        assertEq(usdc.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(address(squidRouter)), 0, "squidRouter should have 0 usdc");
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(weth.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 weth");
        assertEq(weth.balanceOf(address(squidRouter)), 0, "squidRouter should have 0 weth");
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_SwapFromUSDTToUSDCAndBridge(uint32 amount) public {
        vm.assume(amount > 1000000); // > 1 usdt

        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(usdt), user, amount);
        vm.deal(user, gasNeeded);

        bytes memory srcRoute = routeProcessorHelper.computeRoute(
            true, // rpHasToken
            false, // isV2
            address(usdt), // tokenIn
            address(usdc), // tokenOut
            100, // fee
            address(squidRouter) // to
        );

        IRouteProcessor.RouteProcessorData memory srcSwapData = IRouteProcessor.RouteProcessorData({
            tokenIn: address(usdt),
            amountIn: amount,
            tokenOut: address(usdc),
            amountOutMin: 0,
            to: address(squidRouter),
            route: srcRoute
        });

        ISquidMulticall.Call[] memory dstCalls = new ISquidMulticall.Call[](1);
        dstCalls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.Default,
            target: constants.getAddress("arbitrum.axlUSDC"),
            value: 0,
            callData: abi.encodeWithSelector(usdc.transferFrom.selector, address(squidRouter), address(user), amount),
            payload: ""
        });

        bytes memory dstPayload = abi.encode(dstCalls, user);

        bytes memory squidRouterCallData = abi.encodeWithSelector(
            squidRouter.bridgeCall.selector,
            "USDC",
            0,
            "arbitrum",
            address(squidRouter).toString(),
            dstPayload,
            user,
            false
        );

        vm.startPrank(user);
        IERC20(address(usdt)).safeIncreaseAllowance(address(sushiXswap), amount);

        sushiXswap.swapAndBridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(squidAdapter),
                tokenIn: address(usdt),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    address(usdc), // token
                    squidRouterCallData
                    )
            }),
            user, // _refundAddress
            abi.encode(srcSwapData), // swap data
            "", // swap payload data
            "" // payload data
        );

        assertEq(usdc.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(address(squidRouter)), 0, "squidRouter should have 0 usdc");
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(usdt.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdt");
        assertEq(usdt.balanceOf(address(squidRouter)), 0, "squidRouter should have 0 usdt");
        assertEq(usdt.balanceOf(user), 0, "user should have 0 usdt");
    }

    function test_SwapFromNativeToERC20AndBridge() public {
        // basic swap 1 eth to usdc and bridge
        uint64 amount = 1 ether; // 1 eth
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        uint256 valueToSend = amount + gasNeeded;
        vm.deal(user, valueToSend);

        bytes memory srcRoute = routeProcessorHelper.computeRouteNativeIn(
            address(weth), // wrapToken
            false, // isV2
            address(usdc), // tokenOut
            500, // fee
            address(squidRouter) // to
        );

        IRouteProcessor.RouteProcessorData memory srcSwapData = IRouteProcessor
            .RouteProcessorData({
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: address(squidRouter),
                route: srcRoute
            });

        ISquidMulticall.Call[] memory dstCalls = new ISquidMulticall.Call[](1);
        dstCalls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.Default,
            target: constants.getAddress("arbitrum.axlUSDC"),
            value: 0,
            callData: abi.encodeWithSelector(usdc.transferFrom.selector, address(squidRouter), address(user), amount),
            payload: ""
        });

        bytes memory dstPayload = abi.encode(dstCalls, user);

        bytes memory squidRouterCallData = abi.encodeWithSelector(
            squidRouter.bridgeCall.selector,
            "USDC",
            0,
            "arbitrum",
            address(squidRouter).toString(),
            dstPayload,
            user,
            false
        );

        vm.startPrank(user);

        sushiXswap.swapAndBridge{value: valueToSend}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(squidAdapter),
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    address(usdc), // token
                    squidRouterCallData
                    )
            }),
            user, // _refundAddress
            abi.encode(srcSwapData), // swap data
            "", // swap payload data
            "" // payload data
        );

        assertEq(
            address(squidAdapter).balance,
            0,
            "squidAdapter should have 0 eth"
        );
        assertEq(
            address(squidRouter).balance,
            0,
            "squidRouter should have 0 eth"
        );
        assertEq(user.balance, 0, "user should have 0 eth");
        assertEq(
            usdc.balanceOf(address(squidAdapter)),
            0,
            "squidAdapter should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(squidRouter)),
            0,
            "squidRouter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
    }
}
