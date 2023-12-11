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

contract SquidBridgeTest is BaseTest {
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

    function test_RevertWhen_SendingMessage() public {
        vm.startPrank(user);
        vm.expectRevert();
        sushiXswap.sendMessage(address(squidAdapter), "");
    }

    function test_BridgeERC20() public {
        uint32 amount = 1000000; // 1 usdc
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(usdc), user, amount);
        vm.deal(user, gasNeeded);

        // basic usdc bridge, mint axlUSDC on otherside
        vm.startPrank(user);
        usdc.safeIncreaseAllowance(address(sushiXswap), amount);

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
            amount,
            "arbitrum",
            address(squidRouter).toString(),
            dstPayload,
            user,
            false
        );

        sushiXswap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(squidAdapter),
                tokenIn: address(usdc),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    address(usdc), // token
                    squidRouterCallData
                    )
            }),
            user, // _refundAddress
            "", // swap payload
            "" // payload data
        );

        assertEq(usdc.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
    }

    function test_BridgeUSDT() public {
        uint32 amount = 1000000; // 1 usdt
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(usdt), user, amount);
        vm.deal(user, gasNeeded);

        // basic usdt bridge, mint axlUSDT on otherside
        vm.startPrank(user);
        usdt.safeIncreaseAllowance(address(sushiXswap), amount);

        ISquidMulticall.Call[] memory dstCalls = new ISquidMulticall.Call[](1);
        dstCalls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.Default,
            target: constants.getAddress("arbitrum.axlUSDT"),
            value: 0,
            callData: abi.encodeWithSelector(usdt.transferFrom.selector, address(squidRouter), address(user), amount),
            payload: ""
        });

        bytes memory dstPayload = abi.encode(dstCalls, user);

        bytes memory squidRouterCallData = abi.encodeWithSelector(
            squidRouter.bridgeCall.selector,
            "USDT",
            amount,
            "arbitrum",
            address(squidRouter).toString(),
            dstPayload,
            user,
            false
        );

        sushiXswap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(squidAdapter),
                tokenIn: address(usdt),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    address(usdt), // token
                    squidRouterCallData
                    )
            }),
            user, // _refundAddress
            "", // swap payload
            "" // payload data
        );

        assertEq(usdt.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdt");
        assertEq(usdt.balanceOf(user), 0, "user should have 0 usdt");
    }

    function test_BridgeNative() public {
        uint64 amount = 1 ether; // 1 eth
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        uint256 valueToSend = amount + gasNeeded;
        vm.deal(user, valueToSend);

        // basic eth bridge, mint axlETH
        vm.startPrank(user);

        ISquidMulticall.Call[] memory srcCalls = new ISquidMulticall.Call[](2);
        srcCalls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.Default,
            target: address(weth),
            value: amount,
            callData: abi.encodeWithSelector(weth.deposit.selector),
            payload: ""
        });
        srcCalls[1] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.Default,
            target: address(weth),
            value: 0,
            callData: abi.encodeWithSelector(weth.transfer.selector, address(squidRouter), amount),
            payload: ""
        });

        ISquidMulticall.Call[] memory dstCalls = new ISquidMulticall.Call[](1);
        dstCalls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.Default,
            target: constants.getAddress("arbitrum.axlETH"),
            value: 0,
            callData: abi.encodeWithSelector(usdt.transferFrom.selector, address(squidRouter), address(user), amount),
            payload: ""
        });

        bytes memory dstPayload = abi.encode(dstCalls, user);

        bytes memory squidRouterCallData = abi.encodeWithSelector(
            squidRouter.callBridgeCall.selector,
            NATIVE_ADDRESS,
            amount,
            srcCalls,
            "WETH",
            "arbitrum",
            address(squidRouter).toString(),
            dstPayload,
            user,
            false
        );

        sushiXswap.bridge{value: valueToSend}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(squidAdapter),
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    address(weth), // token
                    squidRouterCallData
                    )
            }),
            user, // _refundAddress
            "", // swap payload data
            "" // payload data
        );

        assertEq(address(squidAdapter).balance, 0, "squidAdapter should have 0 eth");
        assertEq(user.balance, 0, "user should have 0 eth");
    }

    function test_RevertWhen_BridgeUnsupportedERC20() public {
        uint32 amount = 1000000; // 1 usdc
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(sushi), user, amount);
        vm.deal(user, gasNeeded);

        // basic sushi bridge, unsupported on axelar gateway so should revert
        vm.startPrank(user);
        sushi.safeIncreaseAllowance(address(sushiXswap), amount);

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
            "SUSHI",
            amount,
            "arbitrum",
            address(squidRouter).toString(),
            dstPayload,
            user,
            false
        );

        vm.expectRevert(bytes4(keccak256("TokenTransferFailed()")));
        sushiXswap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(squidAdapter),
                tokenIn: address(sushi),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    address(sushi), // token
                    squidRouterCallData
                    )
            }),
            user, // _refundAddress
            "", // swap payload
            "" // payload data
        );
    }

    function test_BridgeERC20WithSwapData() public {
        uint32 amount = 1000000; // 1 usdc
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(usdc), user, amount);
        vm.deal(user, gasNeeded);

        bytes memory dstRoute = routeProcessorHelper.computeRoute(false, false, address(usdc), address(weth), 500, user);

        ISquidMulticall.Call[] memory calls = new ISquidMulticall.Call[](3);
        calls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.CollectTokenBalance,
            target: address(0),
            value: 0,
            callData: "",
            payload: abi.encode(constants.getAddress("arbitrum.axlUSDC"))
        });
        calls[1] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: constants.getAddress("arbitrum.axlUSDC"),
            value: 0,
            callData: abi.encodeWithSelector(usdc.approve.selector, address(routeProcessor), 0),
            payload: abi.encode(constants.getAddress("arbitrum.axlUSDC"), 1)
        });
        calls[2] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(squidRouter),
            value: 0,
            callData: abi.encodeWithSelector(
                routeProcessor.processRoute.selector,
                constants.getAddress("arbitrum.axlUSDC"), // tokenIn
                0, // amountIn
                address(weth), // tokenOut
                0, // amountOutMin
                dstRoute
            ),
            payload: abi.encode(constants.getAddress("arbitrum.axlUSDC"), 1)
        });

        bytes memory dstPayload = abi.encode(calls, address(user));

        // basic usdc bridge, mint axlUSDC on otherside, swap for WETH
        vm.startPrank(user);
        usdc.safeIncreaseAllowance(address(sushiXswap), amount);

        bytes memory squidRouterCallData = abi.encodeWithSelector(
            squidRouter.bridgeCall.selector,
            "USDC",
            amount,
            "arbitrum",
            address(squidRouter).toString(),
            dstPayload,
            user,
            false
        );

        sushiXswap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(squidAdapter),
                tokenIn: address(usdc),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    address(usdc), // token
                    squidRouterCallData
                    )
            }),
            user, // _refundAddress
            "", // swap payload
            "" // payload data
        );

        assertEq(usdc.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
    }

    function test_BridgeNativeWithSwapData() public {
        uint64 amount = 1 ether; // 1 eth
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        uint256 valueToSend = amount + gasNeeded;
        vm.deal(user, valueToSend);

        // basic eth bridge, mint axlETH on otherside, swap for USDT
        vm.startPrank(user);

        ISquidMulticall.Call[] memory srcCalls = new ISquidMulticall.Call[](2);
        srcCalls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.Default,
            target: address(weth),
            value: amount,
            callData: abi.encodeWithSelector(weth.deposit.selector),
            payload: ""
        });
        srcCalls[1] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.Default,
            target: address(weth),
            value: 0,
            callData: abi.encodeWithSelector(weth.transfer.selector, address(squidRouter), amount),
            payload: ""
        });

        // TODO: this should use arbitrum addresses
        bytes memory dstRoute = routeProcessorHelper.computeRoute(
            false,
            false,
            address(weth), // constants.getAddress("arbitrum.axlETH")
            address(usdt), // constants.getAddress("arbitrum.usdt")
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory dstSwapData = IRouteProcessor.RouteProcessorData({
            tokenIn: constants.getAddress("arbitrum.axlETH"),
            amountIn: 0, // amountIn doesn't matter on dst since we use amount bridged
            tokenOut: constants.getAddress("arbitrum.usdt"),
            amountOutMin: 0,
            to: user,
            route: dstRoute
        });

        ISquidMulticall.Call[] memory dstCalls = new ISquidMulticall.Call[](3);
        dstCalls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.CollectTokenBalance,
            target: address(0),
            value: 0,
            callData: "",
            payload: abi.encode(constants.getAddress("arbitrum.axlETH"))
        });
        dstCalls[1] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: constants.getAddress("arbitrum.axlETH"),
            value: 0,
            callData: abi.encodeWithSelector(usdc.approve.selector, address(routeProcessor), 0),
            payload: abi.encode(constants.getAddress("arbitrum.axlETH"), 1)
        });
        dstCalls[2] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(squidRouter),
            value: 0,
            callData: abi.encodeWithSelector(
                routeProcessor.processRoute.selector,
                constants.getAddress("arbitrum.axlUSDC"), // tokenIn
                0, // amountIn
                address(weth), // tokenOut
                0, // amountOutMin
                dstRoute
            ),
            payload: abi.encode(constants.getAddress("arbitrum.axlUSDC"), 1)
        });

        bytes memory dstPayload = abi.encode(dstCalls, user);

        bytes memory squidRouterCallData = abi.encodeWithSelector(
            squidRouter.callBridgeCall.selector,
            NATIVE_ADDRESS,
            amount,
            srcCalls,
            "WETH",
            "arbitrum",
            address(squidRouter).toString(),
            dstPayload,
            user,
            false
        );

        sushiXswap.bridge{value: valueToSend}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(squidAdapter),
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    address(weth), // token
                    squidRouterCallData
                    )
            }),
            user, // _refundAddress
            "", // swap payload data
            "" // payload data
        );

        assertEq(address(squidAdapter).balance, 0, "squidAdapter should have 0 eth");
        assertEq(user.balance, 0, "user should have 0 eth");
    }
}
