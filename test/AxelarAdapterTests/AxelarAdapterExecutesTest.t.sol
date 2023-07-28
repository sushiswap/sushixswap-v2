// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {AxelarAdapter} from "../../src/adapters/AxelarAdapter.sol";
import {AirdropPayloadExecutor} from "../../src/payload-executors/AirdropPayloadExecutor.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {ISushiXSwapV2Adapter} from "../../src/interfaces/ISushiXSwapV2Adapter.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

import {StringToBytes32, Bytes32ToString} from "../../src/utils/Bytes32String.sol";
import {StringToAddress, AddressToString} from "../../src/utils/AddressString.sol";

contract AxelarAdapterHarness is AxelarAdapter {
    constructor(
        address _axelarGateway,
        address _gasService,
        address _rp,
        address _weth
    ) AxelarAdapter(_axelarGateway, _gasService, _rp, _weth) {}

    function exposed_executeWithToken(
        string memory sourceChain,
        string memory sourceAddress,
        bytes calldata payload,
        string memory tokenSymbol,
        uint256 amount
    ) external {
        _executeWithToken(
            sourceChain,
            sourceAddress,
            payload,
            tokenSymbol,
            amount
        );
    }
}

contract AxelarAdapterExecutesTest is BaseTest {
    using SafeERC20 for IERC20;

    SushiXSwapV2 public sushiXswap;
    AxelarAdapter public axelarAdapter;
    AxelarAdapterHarness public axelarAdapterHarness;
    AirdropPayloadExecutor public airdropExecutor;
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

        // setup axelar adapter
        axelarAdapter = new AxelarAdapter(
            constants.getAddress("mainnet.axelarGateway"),
            constants.getAddress("mainnet.axelarGasService"),
            constants.getAddress("mainnet.routeProcessor"),
            constants.getAddress("mainnet.weth")
        );
        axelarAdapterHarness = new AxelarAdapterHarness(
            constants.getAddress("mainnet.axelarGateway"),
            constants.getAddress("mainnet.axelarGasService"),
            constants.getAddress("mainnet.routeProcessor"),
            constants.getAddress("mainnet.weth")
        );
        sushiXswap.updateAdapterStatus(address(axelarAdapter), true);

        // deploy payload executors
        airdropExecutor = new AirdropPayloadExecutor();

        vm.stopPrank();
    }

    function test_ReceiveERC20SwapToERC20() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(axelarAdapterHarness), amount); // axelar adapter receives USDC

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        axelarAdapterHarness.exposed_executeWithToken(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            mockPayload,
            "USDC",
            amount
        );

        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            weth.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 weth"
        );
        assertGt(weth.balanceOf(user), 0, "user should have > 0 weth");
    }


    function test_ReceiveUSDTSwapToERC20() public {
        uint32 amount = 1000000; // 1 usdt

        deal(address(usdt), address(axelarAdapterHarness), amount); // axelar adapter receives USDC

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        axelarAdapterHarness.exposed_executeWithToken(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            mockPayload,
            "USDT",
            amount
        );

        assertEq(
            usdt.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdt"
        );
        assertEq(usdt.balanceOf(user), 0, "user should have 0 usdt");
        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertGt(usdc.balanceOf(user), 0, "user should have > 0 usdc");
    }

    function test_ReceiveERC20AndNativeSwapToERC20ReturnDust() public {
        uint32 amount = 1000000; // 1 USDC
        uint64 nativeAmount = 0.001 ether;

        deal(address(usdc), address(axelarAdapterHarness), amount); // axelar adapter receives USDC
        vm.deal(address(axelarAdapterHarness), nativeAmount);

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        axelarAdapterHarness.exposed_executeWithToken(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            mockPayload,
            "USDC",
            amount
        );

        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            weth.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 weth"
        );
        assertGt(weth.balanceOf(user), 0, "user should have > 0 weth");
        assertEq(
            address(axelarAdapterHarness).balance,
            0,
            "adapter should have 0 eth"
        );
        assertEq(user.balance, nativeAmount, "user should have all dust eth");
    }

    function test_ReceiveERC20SwapToNative() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(axelarAdapterHarness), amount); // axelar adapter receives USDC

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRouteNativeOut(
            false,
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

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        axelarAdapterHarness.exposed_executeWithToken(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            mockPayload,
            "USDC",
            amount
        );
        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            address(axelarAdapterHarness).balance,
            0,
            "axelarAdapter should have 0 eth"
        );
        assertGt(user.balance, 0, "user should have > 0 eth");
    }

    function test_ReceiveERC20NotEnoughGasForSwap() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(axelarAdapterHarness), amount); // axelar adapter receives USDC

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        axelarAdapterHarness.exposed_executeWithToken{gas: 90000}(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            mockPayload,
            "USDC",
            amount
        );

        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveUSDTNotEnoughGasForSwap() public {
        uint32 amount = 1000000; // 1 usdt

        deal(address(usdt), address(axelarAdapterHarness), amount); // axelar adapter receives usdt

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        axelarAdapterHarness.exposed_executeWithToken{gas: 90000}(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            mockPayload,
            "USDT",
            amount
        );

        assertEq(
            usdt.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdt"
        );
        assertEq(usdt.balanceOf(user), amount, "user should have all usdt");
        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
    }

    function test_ReceiveERC20AndNativeNotEnoughGasForSwap() public {
        uint32 amount = 1000000; // 1 USDC
        uint64 nativeAmount = 0.001 ether; //

        deal(address(usdc), address(axelarAdapterHarness), amount); // axelar adapter receives USDC
        vm.deal(address(axelarAdapterHarness), nativeAmount);

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        axelarAdapterHarness.exposed_executeWithToken{gas: 90000}(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            mockPayload,
            "USDC",
            amount
        );

        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertEq(
            address(axelarAdapterHarness).balance,
            0,
            "adapter should have 0 eth"
        );
        assertEq(user.balance, nativeAmount, "user should have all dust eth");
    }

    function test_ReceiveERC20EnoughForGasNoSwapOrPayloadData() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(axelarAdapterHarness), amount); // axelar adapter receives USDC

        bytes memory mockPayload = abi.encode(
            user, // to
            "", // _swapData
            "" // _payloadData
        );

        axelarAdapterHarness.exposed_executeWithToken(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            mockPayload,
            "USDC",
            amount
        );

        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveERC20FailedSwap() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(axelarAdapterHarness), amount); // axelar adapter receives USDC

        // switched tokenIn to weth, and tokenOut to usdc - should fail now on swap
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        axelarAdapterHarness.exposed_executeWithToken(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            mockPayload,
            "USDC",
            amount
        );

        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveERC20FailedSwapFromOutOfGas() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(axelarAdapterHarness), amount); // axelar adapter receives USDC

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        axelarAdapterHarness.exposed_executeWithToken{gas: 120000}(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            mockPayload,
            "USDC",
            amount
        );

        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveERC20FailedSwapSlippageCheck() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(axelarAdapterHarness), amount); // axelar adapter receives USDC

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        // attempt to swap usdc to weth with max amountOutMin
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

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        axelarAdapterHarness.exposed_executeWithToken(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            mockPayload,
            "USDC",
            amount
        );

        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveERC20SwapToERC20AirdropERC20FromPayload()
        public
    {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(axelarAdapterHarness), amount); // amount adapter receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
            false,
            address(usdc),
            address(weth),
            500,
            address(airdropExecutor)
        );

        // airdrop all the weth to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        axelarAdapterHarness.exposed_executeWithToken(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            abi.encode(
                address(user), // to
                abi.encode(
                    IRouteProcessor.RouteProcessorData({
                        tokenIn: address(usdc),
                        amountIn: amount,
                        tokenOut: address(weth),
                        amountOutMin: 0,
                        to: address(airdropExecutor),
                        route: computedRoute
                    })
                ), // swap data
                abi.encode(
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
                ) // payloadData
            ),
            "USDC",
            amount
        );

        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            weth.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertGt(
            weth.balanceOf(user1),
            0,
            "user1 should have > 0 weth from airdrop"
        );
        assertGt(
            weth.balanceOf(user2),
            0,
            "user2 should have > 0 weth from airdrop"
        );
    }

    function test_ReceiveERC20SwapToERC20FailedAirdropFromPayload()
        public
    {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(axelarAdapterHarness), amount); // amount adapter receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
            false,
            address(usdc),
            address(weth),
            500,
            address(airdropExecutor)
        );

        // airdrop all the weth to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        axelarAdapterHarness.exposed_executeWithToken(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            abi.encode(
                address(user), // to
                abi.encode(
                    IRouteProcessor.RouteProcessorData({
                        tokenIn: address(usdc),
                        amountIn: amount,
                        tokenOut: address(weth),
                        amountOutMin: 0,
                        to: address(airdropExecutor),
                        route: computedRoute
                    })
                ), // swap data
                abi.encode(
                    ISushiXSwapV2Adapter.PayloadData({
                        target: address(airdropExecutor),
                        gasLimit: 200000,
                        targetData: abi.encode(
                            AirdropPayloadExecutor.AirdropPayloadParams({
                                token: address(user), // using user for token to airdrop so it fails
                                recipients: recipients
                            })
                        )
                    })
                ) // payloadData
            ),
            "USDC",
            amount
        );

        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should all usdc");
        assertEq(
            weth.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertEq(
            usdc.balanceOf(user1),
            0,
            "user1 should have 0 usdc from airdrop"
        );
        assertEq(
            usdc.balanceOf(user2),
            0,
            "user2 should have 0 usdc from airdrop"
        );
    }

    function test_ReceiveERC20AirdropFromPayload() public {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(axelarAdapterHarness), amount); // amount adapter receives

        // airdrop all the usdc to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        axelarAdapterHarness.exposed_executeWithToken(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            abi.encode(
                address(user), // to
                "", // swap data
                abi.encode(
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
                ) // payloadData
            ),
            "USDC",
            amount
        );

        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertGt(
            usdc.balanceOf(user1),
            0,
            "user1 should have > 0 usdc from airdrop"
        );
        assertGt(
            usdc.balanceOf(user2),
            0,
            "user2 should have > 0 usdc from airdrop"
        );
    }

    function test_ReceiveERC20FailedAirdropFromPayload() public {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(axelarAdapterHarness), amount); // amount adapter receives

        // airdrop all the weth to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        axelarAdapterHarness.exposed_executeWithToken(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            abi.encode(
                address(user), // to
                "", // swap data
                abi.encode(
                    ISushiXSwapV2Adapter.PayloadData({
                        target: address(airdropExecutor),
                        gasLimit: 200000,
                        targetData: abi.encode(
                            AirdropPayloadExecutor.AirdropPayloadParams({
                                token: address(weth), // using weth for token to airdrop so it fails
                                recipients: recipients
                            })
                        )
                    })
                ) // payloadData
            ),
            "USDC",
            amount
        );

        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should all usdc");
        assertEq(
            usdc.balanceOf(user1),
            0,
            "user1 should have 0 usdc from airdrop"
        );
        assertEq(
            usdc.balanceOf(user2),
            0,
            "user2 should have 0 usdc from airdrop"
        );
    }

    function test_ReceiveERC20FailedAirdropPayloadFromOutOfGas() public {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(axelarAdapterHarness), amount); // amount adapter receives

        // airdrop all the weth to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        axelarAdapterHarness.exposed_executeWithToken{gas: 120000}(
            "arbitrum",
            AddressToString.toString(address(axelarAdapter)),
            abi.encode(
                address(user), // to
                "", // swap data
                abi.encode(
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
                ) // payloadData
            ),
            "USDC",
            amount
        );

        assertEq(
            usdc.balanceOf(address(axelarAdapterHarness)),
            0,
            "axelarAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should all usdc");
        assertEq(
            usdc.balanceOf(user1),
            0,
            "user1 should have 0 usdc from airdrop"
        );
        assertEq(
            usdc.balanceOf(user2),
            0,
            "user2 should have 0 usdc from airdrop"
        );
    }
}
