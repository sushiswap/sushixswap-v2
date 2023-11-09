// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {ConnextAdapter} from "../../src/adapters/ConnextAdapter.sol";
import {AirdropPayloadExecutor} from "../../src/payload-executors/AirdropPayloadExecutor.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {ISushiXSwapV2Adapter} from "../../src/interfaces/ISushiXSwapV2Adapter.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

contract ConnextAdapterXReceiveTest is BaseTest {
    using SafeERC20 for IERC20;

    SushiXSwapV2 public sushiXswap;
    ConnextAdapter public connextAdapter;
    AirdropPayloadExecutor public airdropExecutor;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;

    address public connext;

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

        connext = constants.getAddress("mainnet.connext");

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

        // deploy payload executors
        airdropExecutor = new AirdropPayloadExecutor();

        vm.stopPrank();
    }

    function test_RevertWhen_ReceivedCallFromNonStargateComposer() public {
        vm.prank(owner);
        vm.expectRevert();
        connextAdapter.xReceive(
            bytes32(""),
            0,
            address(0),
            address(0),
            uint32(0),
            bytes("")
        );
    }

    function testFuzz_ReceiveERC20SwapToERC20(uint32 amount) public {
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(connextAdapter), amount); // amount adapter receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        // auto sends enough gas, so no need to calculate gasNeeded & send here
        connextAdapter.xReceive(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
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
        assertGt(weth.balanceOf(user), 0, "user should have > 0 weth");
    }

    function test_ReceiveWethUnwrapIntoNativeWithRP() public {}

    function test_ReceiveExtraERC20SwapToERC20UserReceivesExtra() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(connextAdapter), amount + 1); // amount adapter receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        // auto sends enough gas, so no need to calculate gasNeeded & send here
        connextAdapter.xReceive(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 1, "user should have extra usdc");
        assertEq(
            weth.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 weth"
        );
        assertGt(weth.balanceOf(user), 0, "user should have > 0 weth");
    }

    function test_ReceiveUSDTSwapToERC20() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdt), address(connextAdapter), amount); // amount adapter receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdt),
            address(usdc),
            100,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdt),
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        // auto sends enough gas, so no need to calculate gasNeeded & send here
        connextAdapter.xReceive(
            bytes32("000303"),
            amount,
            address(usdt),
            address(connextAdapter),
            opDestinationDomain,
            payload
        );

        assertEq(
            usdt.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdt"
        );
        assertEq(usdt.balanceOf(user), 0, "user should have 0 usdt");
        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertGt(usdc.balanceOf(user), 0, "user should have > 0 usdc");
    }

    function test_ReceiveERC20AndNativeSwapToERC20ReturnDust() public {
        uint32 amount = 1000000; // 1 USDC
        uint64 nativeAmount = 0.001 ether;

        deal(address(usdc), address(connextAdapter), amount); // amount adapter receives
        vm.deal(address(connextAdapter), nativeAmount);

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        // auto sends enough gas, so no need to calculate gasNeeded & send here
        connextAdapter.xReceive(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
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
        assertGt(weth.balanceOf(user), 0, "user should have > 0 weth");
        assertEq(
            address(connextAdapter).balance,
            0,
            "adapter should have 0 eth"
        );
        assertEq(user.balance, nativeAmount, "user should have all dust eth");
    }

    function test_ReceiveERC20SwapToNative() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(connextAdapter), amount); // amount adapter receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRouteNativeOut(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: NATIVE_ADDRESS,
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        // auto sends enough gas, so no need to calculate gasNeeded & send here
        connextAdapter.xReceive(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            address(connextAdapter).balance,
            0,
            "connextAdapter should have 0 eth"
        );
        assertGt(user.balance, 0, "user should have > 0 eth");
    }

    function test_ReceiveERC20NotEnoughGasForSwap() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(connextAdapter), amount); // amount adapter receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        connextAdapter.xReceive{gas: 90000}(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveUSDTNotEnoughGasForSwap() public {
        uint32 amount = 1000000; // 1 USDT

        deal(address(usdt), address(connextAdapter), amount); // amount adapter receives

        // receive 1 usdt and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdt),
            address(usdc),
            100,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdt),
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        connextAdapter.xReceive{gas: 90000}(
            bytes32("000303"),
            amount,
            address(usdt),
            address(connextAdapter),
            opDestinationDomain,
            payload
        );

        assertEq(
            usdt.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdt"
        );
        assertEq(usdt.balanceOf(user), amount, "user should have all usdt");
        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
    }

    function test_ReceiveERC20AndNativeNotEnoughGasForSwapConnext() public {
        uint32 amount = 1000000; // 1 USDC
        uint64 nativeAmount = 0.001 ether; //

        deal(address(usdc), address(connextAdapter), amount); // amount adapter receives
        vm.deal(address(connextAdapter), nativeAmount);

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        connextAdapter.xReceive{gas: 90000}(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertEq(
            address(connextAdapter).balance,
            0,
            "adapter should have 0 eth"
        );
        assertEq(user.balance, nativeAmount, "user should have all dust eth");
    }

    function test_ReceiveERC20EnoughForGasNoSwapOrPayloadData() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(connextAdapter), amount); // amount adapter receives

        bytes memory payload = abi.encode(
            user, // to
            "", // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        // auto sends enough gas, so no need to calculate gasNeeded & send here
        connextAdapter.xReceive(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveERC20FailedSwap() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(connextAdapter), amount); // amount adapter receives

        // switched tokenIn to weth, and tokenOut to usdc - should fail on swap
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(weth),
            address(usdc),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(weth),
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        // auto sends enough gas, so no need to calculate gasNeeded & send here
        connextAdapter.xReceive(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveUSDCAndNativeFailedSwapMinimumGasSent() public {
        uint32 amount = 1000000; // 1 USDC
        uint64 dustAmount = 0.2 ether;

        deal(address(usdc), address(connextAdapter), amount); // amount adapter receives
        vm.deal(address(connextAdapter), dustAmount);

        // switched tokenIn to weth, and tokenOut to usdc - should fail now on swap
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(weth),
            address(usdc),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(weth),
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        connextAdapter.xReceive{gas: 103384}(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(
            address(connextAdapter).balance,
            0,
            "adapter should have 0 native"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(user.balance, dustAmount, "user should have all the dust");
        assertEq(
            weth.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveERC20FailedSwapFromOutOfGas() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(connextAdapter), amount); // amount adapter receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        connextAdapter.xReceive{gas: 120000}(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveERC20FailedSwapSlippageCheck() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(connextAdapter), amount); // amount adapter receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: type(uint256).max,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        connextAdapter.xReceive(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveERC20SwapToERC20AirdropERC20FromPayload() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(connextAdapter), amount); // amount adapter receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            address(airdropExecutor)
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: address(airdropExecutor),
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        // airdrop payload data
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        bytes memory payloadData = abi.encode(
            ISushiXSwapV2Adapter.PayloadData({
                target: address(airdropExecutor),
                gasLimit: 200000,
                targetData: abi.encode(
                    AirdropPayloadExecutor.AirdropPayloadParams({
                        token: address(weth),
                        recipients: recipients
                    })
                )
            })
        );

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            payloadData // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        connextAdapter.xReceive(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
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
        assertGt(weth.balanceOf(user1), 0, "user1 should have > 0 weth");
        assertGt(weth.balanceOf(user2), 0, "user2 should have > 0 weth");
    }

    function test_ReceiveERC20SwapToERC20FailedAirdropFromPayload() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(connextAdapter), amount); // amount adapter receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            address(airdropExecutor)
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: address(airdropExecutor),
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        // airdrop payload data
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        bytes memory payloadData = abi.encode(
            ISushiXSwapV2Adapter.PayloadData({
                target: address(airdropExecutor),
                gasLimit: 200000,
                targetData: abi.encode(
                    AirdropPayloadExecutor.AirdropPayloadParams({
                        token: address(user), // using user for token so it fails
                        recipients: recipients
                    })
                )
            })
        );

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            payloadData // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        connextAdapter.xReceive(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertEq(weth.balanceOf(user1), 0, "user1 should have 0 weth");
        assertEq(weth.balanceOf(user2), 0, "user2 should have 0 weth");
    }

    function test_ReceiveERC20AirdropFromPayload() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(connextAdapter), amount); // amount adapter receives

        // airdrop payload data
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        bytes memory payloadData = abi.encode(
            ISushiXSwapV2Adapter.PayloadData({
                target: address(airdropExecutor),
                gasLimit: 200000,
                targetData: abi.encode(
                    AirdropPayloadExecutor.AirdropPayloadParams({
                        token: address(usdc),
                        recipients: recipients
                    })
                )
            })
        );

        bytes memory payload = abi.encode(
            user, // to
            "", // _swapData
            payloadData // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        connextAdapter.xReceive(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertGt(usdc.balanceOf(user1), 0, "user1 should have > 0 usdc");
        assertGt(usdc.balanceOf(user2), 0, "user2 should have > 0 usdc");
    }

    function test_ReceiveERC20FailedAirdropFromPayload() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(connextAdapter), amount); // amount adapter receives

        // airdrop payload data
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        bytes memory payloadData = abi.encode(
            ISushiXSwapV2Adapter.PayloadData({
                target: address(airdropExecutor),
                gasLimit: 200000,
                targetData: abi.encode(
                    AirdropPayloadExecutor.AirdropPayloadParams({
                        token: address(weth), // using weth for token to airdrop so it fail
                        recipients: recipients
                    })
                )
            })
        );

        bytes memory payload = abi.encode(
            user, // to
            "", // _swapData
            payloadData // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        connextAdapter.xReceive(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(usdc.balanceOf(user1), 0, "user1 should have 0 usdc");
        assertEq(usdc.balanceOf(user2), 0, "user2 should have 0 usdc");
    }

    function test_ReceiveERC20FailedAirdropPayloadFromOutOfGas() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(connextAdapter), amount); // amount adapter receives

        // airdrop payload data
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        bytes memory payloadData = abi.encode(
            ISushiXSwapV2Adapter.PayloadData({
                target: address(airdropExecutor),
                gasLimit: 200000,
                targetData: abi.encode(
                    AirdropPayloadExecutor.AirdropPayloadParams({
                        token: address(usdc),
                        recipients: recipients
                    })
                )
            })
        );

        bytes memory payload = abi.encode(
            user, // to
            "", // _swapData
            payloadData // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.connext"));
        connextAdapter.xReceive{gas: 120000}(
            bytes32("000303"),
            amount,
            address(usdc),
            address(connextAdapter),
            opDestinationDomain,
            payload
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(usdc.balanceOf(user1), 0, "user1 should have 0 usdc");
        assertEq(usdc.balanceOf(user2), 0, "user2 should have 0 usdc");
    }
}
