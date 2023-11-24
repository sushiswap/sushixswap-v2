// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {SquidAdapter} from "../../src/adapters/SquidAdapter.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {ISushiXSwapV2Adapter} from "../../src/interfaces/ISushiXSwapV2Adapter.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {ISquidRouter} from "../../src/interfaces/squid/ISquidRouter.sol";
import {ISquidMulticall} from "../../src/interfaces/squid/ISquidMulticall.sol";
import {AirdropPayloadExecutor} from "../../src/payload-executors/AirdropPayloadExecutor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import "axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";
import "./utils/MockSquidReceiver.sol";

import {StringToBytes32, Bytes32ToString} from "../../src/utils/Bytes32String.sol";
import {StringToAddress, AddressToString} from "../../src/utils/AddressString.sol";

import {console2} from "forge-std/console2.sol";

contract SquidExecutesTest is BaseTest {
    using SafeERC20 for IERC20;
    using AddressToString for address;

    SushiXSwapV2 public sushiXswap;
    SquidAdapter public squidAdapter;
    MockSquidReceiver public squidReceiver;
    ISquidRouter public squidRouter;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;
    AirdropPayloadExecutor public airdropExecutor;

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

        squidReceiver = new MockSquidReceiver(
            constants.getAddress("mainnet.axelarGateway"),
            constants.getAddress("mainnet.squidMulticall")
        );

        vm.startPrank(owner);
        sushiXswap = new SushiXSwapV2(routeProcessor, address(weth));

        // add operator as privileged
        sushiXswap.setPrivileged(operator, true);

        // setup squid adapter
        squidAdapter = new SquidAdapter(
            constants.getAddress("mainnet.squidRouter")
        );

        sushiXswap.updateAdapterStatus(address(squidAdapter), true);

        // deploy payload executors
        airdropExecutor = new AirdropPayloadExecutor();

        vm.stopPrank();
    }

    function test_ReceiveERC20() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(squidReceiver), amount);

        ISquidMulticall.Call[] memory calls = new ISquidMulticall.Call[](1);
        calls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.Default,
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(usdc.transferFrom.selector, address(squidReceiver), address(user), amount),
            payload: ""
        });

        bytes memory payload = abi.encode(calls, user);

        squidReceiver.exposed_executeWithToken("", "", payload, "USDC", 0);

        assertEq(usdc.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 usdc");
        assertEq(usdc.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(user), amount, "user should have some usdc");
    }

    // bridged amount is unknown during payload creation
    function test_ReceiveERC20_UnknownAmount() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(squidReceiver), amount);

        ISquidMulticall.Call[] memory calls = new ISquidMulticall.Call[](2);
        // transfer squid router usdc balance to squid multicall
        calls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.CollectTokenBalance,
            target: address(0),
            value: 0,
            callData: "",
            payload: abi.encode(address(usdc))
        });
        // transfer squid multicall usdc balance to user
        calls[1] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(usdc.transfer.selector, address(user), 0),
            payload: abi.encode(address(usdc), 1)
        });

        bytes memory payload = abi.encode(calls, user);

        squidReceiver.exposed_executeWithToken("", "", payload, "USDC", 0);

        assertEq(usdc.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 usdc");
        assertEq(usdc.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(user), amount, "user should have some usdc");
    }

    function test_ReceiveERC20SwapToERC20() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(squidReceiver), amount);

        // receive 1 USDC and swap to weth
        bytes memory computedRoute =
            routeProcessorHelper.computeRoute(false, false, address(usdc), address(weth), 500, user);

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
            tokenIn: address(usdc),
            amountIn: amount,
            tokenOut: address(weth),
            amountOutMin: 0,
            to: user,
            route: computedRoute
        });

        ISquidMulticall.Call[] memory calls = new ISquidMulticall.Call[](3);
        // Transfer USDC balance to SquidMulticall
        calls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.CollectTokenBalance,
            target: address(0),
            value: 0,
            callData: "",
            payload: abi.encode(address(usdc))
        });
        // Grant approval of USDC to RouteProcessor
        calls[1] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(usdc.approve.selector, address(routeProcessor), 0),
            payload: abi.encode(address(usdc), 1)
        });
        // Invoke RouteProcessor.processRoute
        calls[2] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(routeProcessor),
            value: 0,
            callData: abi.encodeWithSelector(
                routeProcessor.processRoute.selector, rpd.tokenIn, 0, rpd.tokenOut, rpd.amountOutMin, rpd.to, rpd.route
                ),
            payload: abi.encode(address(usdc), 1)
        });

        bytes memory payload = abi.encode(calls, user);

        squidReceiver.exposed_executeWithToken("", "", payload, "USDC", 0);

        assertEq(usdc.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 usdc");
        assertEq(usdc.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");

        assertEq(weth.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 weth");
        assertEq(weth.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 weth");
        assertGt(weth.balanceOf(user), 0, "user should have > 0 weth");
    }

    function test_ReceiveUSDTSwapToERC20() public {
        uint32 amount = 1000000; // 1 USDT

        deal(address(usdt), address(squidReceiver), amount);

        // receive 1 USDT and swap to USDC
        bytes memory computedRoute =
            routeProcessorHelper.computeRoute(false, false, address(usdt), address(usdc), 100, user);

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
            tokenIn: address(usdt),
            amountIn: amount,
            tokenOut: address(usdc),
            amountOutMin: 0,
            to: user,
            route: computedRoute
        });

        ISquidMulticall.Call[] memory calls = new ISquidMulticall.Call[](3);
        calls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.CollectTokenBalance,
            target: address(0),
            value: 0,
            callData: "",
            payload: abi.encode(address(usdt))
        });
        calls[1] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(usdt),
            value: 0,
            callData: abi.encodeWithSelector(usdt.approve.selector, address(routeProcessor), 0),
            payload: abi.encode(address(usdt), 1)
        });
        calls[2] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(routeProcessor),
            value: 0,
            callData: abi.encodeWithSelector(
                routeProcessor.processRoute.selector, rpd.tokenIn, 0, rpd.tokenOut, rpd.amountOutMin, rpd.to, rpd.route
                ),
            payload: abi.encode(address(usdt), 1)
        });

        bytes memory payload = abi.encode(calls, user);

        squidReceiver.exposed_executeWithToken("", "", payload, "USDT", 0);

        assertEq(usdt.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 usdt");
        assertEq(usdt.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdt");
        assertEq(usdt.balanceOf(user), 0, "user should have 0 usdt");

        assertEq(usdc.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 usdc");
        assertEq(usdc.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdc");
        assertGt(usdc.balanceOf(user), 0, "user should have > 0 usdc");
    }

    function test_ReceiveERC20SwapToNative() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(squidReceiver), amount);

        // receive 1 USDC and swap to weth
        bytes memory computedRoute =
            routeProcessorHelper.computeRouteNativeOut(false, false, address(usdc), address(weth), 500, user);

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
            tokenIn: address(usdc),
            amountIn: amount,
            tokenOut: NATIVE_ADDRESS,
            amountOutMin: 0,
            to: user,
            route: computedRoute
        });

        ISquidMulticall.Call[] memory calls = new ISquidMulticall.Call[](3);
        calls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.CollectTokenBalance,
            target: address(0),
            value: 0,
            callData: "",
            payload: abi.encode(address(usdc))
        });
        calls[1] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(usdc.approve.selector, address(routeProcessor), 0),
            payload: abi.encode(address(usdc), 1)
        });
        calls[2] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(routeProcessor),
            value: 0,
            callData: abi.encodeWithSelector(
                routeProcessor.processRoute.selector, rpd.tokenIn, 0, rpd.tokenOut, rpd.amountOutMin, rpd.to, rpd.route
                ),
            payload: abi.encode(address(usdc), 1)
        });

        bytes memory payload = abi.encode(calls, user);

        squidReceiver.exposed_executeWithToken("", "", payload, "USDC", 0);

        assertEq(usdc.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 usdc");
        assertEq(usdc.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");

        assertEq(address(squidReceiver).balance, 0, "squidReceiver should have 0 eth");
        assertEq(address(squidAdapter).balance, 0, "squidAdapter should have 0 eth");
        assertGt(user.balance, 0, "user should have > 0 eth");
    }

    function test_ReceiveERC20FailedSwap() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(squidReceiver), amount);

        // switched tokenIn to weth, and tokenOut to usdc - should fail now on swap
        bytes memory computedRoute =
            routeProcessorHelper.computeRoute(true, false, address(weth), address(usdc), 500, user);

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
            tokenIn: address(weth),
            amountIn: amount,
            tokenOut: address(usdc),
            amountOutMin: 0,
            to: user,
            route: computedRoute
        });

        ISquidMulticall.Call[] memory calls = new ISquidMulticall.Call[](3);
        calls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.CollectTokenBalance,
            target: address(0),
            value: 0,
            callData: "",
            payload: abi.encode(address(usdc))
        });
        calls[1] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(usdc.approve.selector, address(routeProcessor), 0),
            payload: abi.encode(address(usdc), 1)
        });
        calls[2] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(routeProcessor),
            value: 0,
            callData: abi.encodeWithSelector(
                routeProcessor.processRoute.selector, rpd.tokenIn, 0, rpd.tokenOut, rpd.amountOutMin, rpd.to, rpd.route
                ),
            payload: abi.encode(address(usdc), 1)
        });

        bytes memory payload = abi.encode(calls, user);

        squidReceiver.exposed_executeWithToken("", "", payload, "USDC", 0);

        assertEq(usdc.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 usdc");
        assertEq(usdc.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");

        assertEq(weth.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 weth");
        assertEq(weth.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 weth");
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveERC20FailedSwapSlippageCheck() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(squidReceiver), amount);

        // receive 1 USDC and swap to weth
        bytes memory computedRoute =
            routeProcessorHelper.computeRoute(true, false, address(usdc), address(weth), 500, user);

        // attempt to swap usdc to weth with max amountOutMin
        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
            tokenIn: address(usdc),
            amountIn: amount,
            tokenOut: address(weth),
            amountOutMin: type(uint256).max,
            to: user,
            route: computedRoute
        });

        ISquidMulticall.Call[] memory calls = new ISquidMulticall.Call[](3);
        calls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.CollectTokenBalance,
            target: address(0),
            value: 0,
            callData: "",
            payload: abi.encode(address(usdc))
        });
        calls[1] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(usdc.approve.selector, address(routeProcessor), 0),
            payload: abi.encode(address(usdc), 1)
        });
        calls[2] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(routeProcessor),
            value: 0,
            callData: abi.encodeWithSelector(
                routeProcessor.processRoute.selector, rpd.tokenIn, 0, rpd.tokenOut, rpd.amountOutMin, rpd.to, rpd.route
                ),
            payload: abi.encode(address(usdc), 1)
        });

        bytes memory payload = abi.encode(calls, user);

        squidReceiver.exposed_executeWithToken("", "", payload, "USDC", 0);

        assertEq(usdc.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 usdc");
        assertEq(usdc.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");

        assertEq(weth.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 weth");
        assertEq(weth.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 weth");
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveERC20SwapToERC20AirdropERC20FromPayload() public {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(squidReceiver), amount); // amount adapter receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute =
            routeProcessorHelper.computeRoute(false, false, address(usdc), address(weth), 500, address(airdropExecutor));

        // airdrop all the weth to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
            tokenIn: address(usdc),
            amountIn: amount,
            tokenOut: address(weth),
            amountOutMin: 0,
            to: address(airdropExecutor),
            route: computedRoute
        });

        bytes memory dstPayloadCallData = abi.encodeWithSelector(
            AirdropPayloadExecutor.onPayloadReceive.selector,
            abi.encode(AirdropPayloadExecutor.AirdropPayloadParams({token: address(weth), recipients: recipients}))
        );

        ISquidMulticall.Call[] memory calls = new ISquidMulticall.Call[](4);
        calls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.CollectTokenBalance,
            target: address(0),
            value: 0,
            callData: "",
            payload: abi.encode(address(usdc))
        });
        calls[1] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(usdc.approve.selector, address(routeProcessor), 0),
            payload: abi.encode(address(usdc), 1)
        });
        calls[2] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(routeProcessor),
            value: 0,
            callData: abi.encodeWithSelector(
                routeProcessor.processRoute.selector, rpd.tokenIn, 0, rpd.tokenOut, rpd.amountOutMin, rpd.to, rpd.route
                ),
            payload: abi.encode(address(usdc), 1)
        });
        calls[3] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.Default,
            target: address(airdropExecutor),
            value: 0,
            callData: dstPayloadCallData,
            payload: ""
        });

        bytes memory payload = abi.encode(calls, user);

        squidReceiver.exposed_executeWithToken("", "", payload, "USDC", 0);

        assertEq(usdc.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 usdc");
        assertEq(usdc.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(weth.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 weth");
        assertEq(weth.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 weth");
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertGt(weth.balanceOf(user1), 0, "user1 should have > 0 weth from airdrop");
        assertGt(weth.balanceOf(user2), 0, "user2 should have > 0 weth from airdrop");
    }

    function test_ReceiveERC20SwapToERC20FailedAirdropFromPayload() public {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(squidReceiver), amount); // amount adapter receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute =
            routeProcessorHelper.computeRoute(false, false, address(usdc), address(weth), 500, address(airdropExecutor));

        // airdrop all the weth to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
            tokenIn: address(usdc),
            amountIn: amount,
            tokenOut: address(weth),
            amountOutMin: 0,
            to: address(airdropExecutor),
            route: computedRoute
        });

        bytes memory dstPayloadCallData = abi.encodeWithSelector(
            AirdropPayloadExecutor.onPayloadReceive.selector,
            abi.encode(
                AirdropPayloadExecutor.AirdropPayloadParams({
                    token: address(user), // using user for token to airdrop so it fails
                    recipients: recipients
                })
            )
        );

        ISquidMulticall.Call[] memory calls = new ISquidMulticall.Call[](4);
        calls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.CollectTokenBalance,
            target: address(0),
            value: 0,
            callData: "",
            payload: abi.encode(address(usdc))
        });
        calls[1] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(usdc.approve.selector, address(routeProcessor), 0),
            payload: abi.encode(address(usdc), 1)
        });
        calls[2] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(routeProcessor),
            value: 0,
            callData: abi.encodeWithSelector(
                routeProcessor.processRoute.selector, rpd.tokenIn, 0, rpd.tokenOut, rpd.amountOutMin, rpd.to, rpd.route
                ),
            payload: abi.encode(address(usdc), 1)
        });
        calls[3] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.Default,
            target: address(airdropExecutor),
            value: 0,
            callData: dstPayloadCallData,
            payload: ""
        });

        bytes memory payload = abi.encode(calls, user);

        squidReceiver.exposed_executeWithToken("", "", payload, "USDC", 0);

        assertEq(usdc.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 usdc");
        assertEq(usdc.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(user), amount, "user should all usdc");
        assertEq(weth.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 weth");
        assertEq(weth.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 weth");
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertEq(usdc.balanceOf(user1), 0, "user1 should have 0 usdc from airdrop");
        assertEq(usdc.balanceOf(user2), 0, "user2 should have 0 usdc from airdrop");
    }

    function test_ReceiveERC20AirdropFromPayload() public {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(squidReceiver), amount); // amount adapter receives

        // airdrop all the usdc to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        bytes memory dstPayloadCallData = abi.encodeWithSelector(
            AirdropPayloadExecutor.onPayloadReceive.selector,
            abi.encode(AirdropPayloadExecutor.AirdropPayloadParams({token: address(usdc), recipients: recipients}))
        );

        ISquidMulticall.Call[] memory calls = new ISquidMulticall.Call[](3);
        calls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.CollectTokenBalance,
            target: address(0),
            value: 0,
            callData: "",
            payload: abi.encode(address(usdc))
        });
        calls[1] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(usdc.transfer.selector, address(airdropExecutor), 0),
            payload: abi.encode(address(usdc), 1)
        });
        calls[2] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.Default,
            target: address(airdropExecutor),
            value: 0,
            callData: dstPayloadCallData,
            payload: ""
        });

        bytes memory payload = abi.encode(calls, user);

        squidReceiver.exposed_executeWithToken("", "", payload, "USDC", 0);

        assertEq(usdc.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 usdc");
        assertEq(usdc.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertGt(usdc.balanceOf(user1), 0, "user1 should have > 0 usdc from airdrop");
        assertGt(usdc.balanceOf(user2), 0, "user2 should have > 0 usdc from airdrop");
    }

    function test_ReceiveERC20FailedAirdropFromPayload() public {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(squidReceiver), amount); // amount adapter receives

        // airdrop all the weth to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        bytes memory dstPayloadCallData = abi.encodeWithSelector(
            AirdropPayloadExecutor.onPayloadReceive.selector,
            abi.encode(
                AirdropPayloadExecutor.AirdropPayloadParams({
                    token: address(user), // using weth for token to airdrop so it fails
                    recipients: recipients
                })
            )
        );

        ISquidMulticall.Call[] memory calls = new ISquidMulticall.Call[](3);
        calls[0] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.CollectTokenBalance,
            target: address(0),
            value: 0,
            callData: "",
            payload: abi.encode(address(usdc))
        });
        calls[1] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.FullTokenBalance,
            target: address(usdc),
            value: 0,
            callData: abi.encodeWithSelector(usdc.transfer.selector, address(squidAdapter), 0),
            payload: abi.encode(address(usdc), 1)
        });
        calls[2] = ISquidMulticall.Call({
            callType: ISquidMulticall.CallType.Default,
            target: address(airdropExecutor),
            value: 0,
            callData: dstPayloadCallData,
            payload: ""
        });

        bytes memory payload = abi.encode(calls, user);

        squidReceiver.exposed_executeWithToken("", "", payload, "USDC", 0);

        assertEq(usdc.balanceOf(address(squidReceiver)), 0, "squidReceiver should have 0 usdc");
        assertEq(usdc.balanceOf(address(squidAdapter)), 0, "squidAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(user), amount, "user should all usdc");
        assertEq(usdc.balanceOf(user1), 0, "user1 should have 0 usdc from airdrop");
        assertEq(usdc.balanceOf(user2), 0, "user2 should have 0 usdc from airdrop");
    }
}
