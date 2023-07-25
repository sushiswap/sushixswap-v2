// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {CCTPAdapter} from "../../src/adapters/CCTPAdapter.sol";
import {AirdropPayloadExecutor} from "../../src/payload-executors/AirdropPayloadExecutor.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {ISushiXSwapV2Adapter} from "../../src/interfaces/ISushiXSwapV2Adapter.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

import {StringToBytes32, Bytes32ToString} from "../../src/utils/Bytes32String.sol";
import {StringToAddress, AddressToString} from "../../src/utils/AddressString.sol";

contract CCTPAdapterHarness is CCTPAdapter {
    constructor(
        address _axelarGateway,
        address _gasService,
        address _tokenMessenger,
        address _rp,
        address _nativeUSDC
    )
        CCTPAdapter(
            _axelarGateway,
            _gasService,
            _tokenMessenger,
            _rp,
            _nativeUSDC
        )
    {}

    function exposed_execute(
        string memory sourceChain,
        string memory sourceAddress,
        bytes calldata payload
    ) external {
        _execute(sourceChain, sourceAddress, payload);
    }
}

contract CCTPAdapterExecutesTest is BaseTest {
    SushiXSwapV2 public sushiXswap;
    CCTPAdapter public cctpAdapter;
    CCTPAdapterHarness public cctpAdapterHarness;
    AirdropPayloadExecutor public airdropExecutor;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;

    IWETH public weth;
    ERC20 public sushi;
    ERC20 public usdc;
    ERC20 public usdt;

    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public operator = address(0xbeef);
    address public owner = address(0x420);
    address public user = address(0x4201);

    function setUp() public override {
        forkMainnet();
        super.setUp();

        weth = IWETH(constants.getAddress("mainnet.weth"));
        sushi = ERC20(constants.getAddress("mainnet.sushi"));
        usdc = ERC20(constants.getAddress("mainnet.usdc"));
        usdt = ERC20(constants.getAddress("mainnet.usdt"));

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
        cctpAdapter = new CCTPAdapter(
            constants.getAddress("mainnet.axelarGateway"),
            constants.getAddress("mainnet.axelarGasService"),
            constants.getAddress("mainnet.cctpTokenMessenger"),
            constants.getAddress("mainnet.routeProcessor"),
            constants.getAddress("mainnet.usdc")
        );
        cctpAdapterHarness = new CCTPAdapterHarness(
            constants.getAddress("mainnet.axelarGateway"),
            constants.getAddress("mainnet.axelarGasService"),
            constants.getAddress("mainnet.cctpTokenMessenger"),
            constants.getAddress("mainnet.routeProcessor"),
            constants.getAddress("mainnet.usdc")
        );
        sushiXswap.updateAdapterStatus(address(cctpAdapter), true);

        // deploy payload executors
        airdropExecutor = new AirdropPayloadExecutor();

        vm.stopPrank();
    }

    function test_ReceiveUSDCSwapToERC20() public {
        uint32 amount = 1000000; // 1 usdc

        deal(address(usdc), address(cctpAdapterHarness), amount); // cctp adapter receives USDC

        // receives 1 minted USDC and swap to weth
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
            amount, // amount of usdc bridged
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        cctpAdapterHarness.exposed_execute(
            "arbitrum",
            AddressToString.toString(address(cctpAdapter)),
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            weth.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 weth"
        );
        assertGt(weth.balanceOf(user), 0, "user should have > 0 weth");
    }

    function test_ReceiveUSDCAndNativeSwapToERC20() public {
        uint32 amount = 1000000; // 1 usdc
        uint64 nativeAmount = 0.001 ether;

        deal(address(usdc), address(cctpAdapterHarness), amount); // cctp adapter receives USDC
        deal(address(cctpAdapterHarness), nativeAmount);

        // receives 1 minted USDC and swap to weth
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
            amount, // amount of usdc bridged
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        cctpAdapterHarness.exposed_execute(
            "arbitrum",
            AddressToString.toString(address(cctpAdapter)),
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            weth.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 weth"
        );
        assertGt(weth.balanceOf(user), 0, "user should have > 0 weth");
        assertEq(
            address(cctpAdapterHarness).balance,
            0,
            "adapter should have 0 eth"
        );
        assertEq(user.balance, nativeAmount, "user should have all dust eth");
    }

    function test_ReceiveUSDCNotEnoughGasForSwap() public {
        uint32 amount = 1000000; // 1 usdc

        deal(address(usdc), address(cctpAdapterHarness), amount); // cctp adapter receives USDC

        // receives 1 minted USDC and swap to weth
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
            amount, // amount of usdc bridged
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        cctpAdapterHarness.exposed_execute{gas: 90000}(
            "arbitrum",
            AddressToString.toString(address(cctpAdapter)),
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveUSDCAndNativeNotEnoughGasForSwap() public {
        uint32 amount = 1000000; // 1 usdc
        uint64 nativeAmount = 0.001 ether;

        deal(address(usdc), address(cctpAdapterHarness), amount); // cctp adapter receives USDC
        vm.deal(address(cctpAdapterHarness), nativeAmount);

        // receives 1 minted USDC and swap to weth
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
            amount, // amount of usdc bridged
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        cctpAdapterHarness.exposed_execute{gas: 90000}(
            "arbitrum",
            AddressToString.toString(address(cctpAdapter)),
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertEq(
            address(cctpAdapterHarness).balance,
            0,
            "adapter should have 0 eth"
        );
        assertEq(user.balance, nativeAmount, "user should have all dust eth");
    }

    function test_ReceiveUSDCEnoughForGasNoSwapOrPayloadData() public {
        uint32 amount = 1000000; // 1 usdc

        deal(address(usdc), address(cctpAdapterHarness), amount); // cctp adapter receives USDC

        bytes memory mockPayload = abi.encode(
            user, // to
            amount, // amount of usdc bridged
            "", // _swapData
            "" // _payloadData
        );

        cctpAdapterHarness.exposed_execute(
            "arbitrum",
            AddressToString.toString(address(cctpAdapter)),
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveUSDCFailedSwap() public {
        uint32 amount = 1000000; // 1 usdc

        deal(address(usdc), address(cctpAdapterHarness), amount); // cctp adapter receives USDC

        // receives 1 minted USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        // switched tokenIn to weth, and tokenOut to usdc - should fail now on swap
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
            amount, // amount of usdc bridged
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        cctpAdapterHarness.exposed_execute(
            "arbitrum",
            AddressToString.toString(address(cctpAdapter)),
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveUSDCFailedSwapFromOutOfGas() public {
        uint32 amount = 1000000; // 1 usdc

        deal(address(usdc), address(cctpAdapterHarness), amount); // cctp adapter receives USDC

        // receives 1 minted USDC and swap to weth
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
            amount, // amount of usdc bridged
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        cctpAdapterHarness.exposed_execute{gas: 120000}(
            "arbitrum",
            AddressToString.toString(address(cctpAdapter)),
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveUSDCFailedSwapSlippageCheck() public {
        uint32 amount = 1000000; // 1 usdc

        deal(address(usdc), address(cctpAdapterHarness), amount); // cctp adapter receives USDC

        // receives 1 minted USDC and swap to weth
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
            amount, // amount of usdc bridged
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        cctpAdapterHarness.exposed_execute(
            "arbitrum",
            AddressToString.toString(address(cctpAdapter)),
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctp adapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveUSDCSwapToERC20AirdropERC20FromPayload() public {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(cctpAdapterHarness), amount); // amount adapter receives

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

        cctpAdapterHarness.exposed_execute(
            "arbitrum",
            AddressToString.toString(address(cctpAdapter)),
            abi.encode(
                address(user), // to
                amount, // amount
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
            )
        );

        assertEq(
            usdc.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctpAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            weth.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctpAdapter should have 0 weth"
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

    function test_ReceiveUSDCSwapToERC20FailedAirdropFromPayload()
        public
    {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(cctpAdapterHarness), amount); // amount adapter receives

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

        cctpAdapterHarness.exposed_execute(
            "arbitrum",
            AddressToString.toString(address(cctpAdapter)),
            abi.encode(
                address(user), // to
                amount, // amount
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
                                token: address(user), // using user for token to aridrop so it fails
                                recipients: recipients
                            })
                        )
                    })
                ) // payloadData
            )
        );

        assertEq(
            usdc.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctpAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should all usdc");
        assertEq(
            weth.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctpAdapter should have 0 weth"
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

    function test_ReceiveUSDCAirdropFromPayload() public {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(cctpAdapterHarness), amount); // amount adapter receives

        // airdrop all the usdc to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        cctpAdapterHarness.exposed_execute(
            "arbitrum",
            AddressToString.toString(address(cctpAdapter)),
            abi.encode(
                address(user), // to
                amount, // amount
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
            )
        );

        assertEq(
            usdc.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctpAdapter should have 0 usdc"
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

    function test_ReceiveUSDCFailedAirdropFromPayload() public {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(cctpAdapterHarness), amount); // amount adapter receives

        // airdrop all the usdc to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        cctpAdapterHarness.exposed_execute(
            "arbitrum",
            AddressToString.toString(address(cctpAdapter)),
            abi.encode(
                address(user), // to
                amount, // amount
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
            )
        );

        assertEq(
            usdc.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctpAdapter should have 0 usdc"
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

    function test_ReceiveUSDCFailedAirdropPayloadFromOutOfGas() public {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(cctpAdapterHarness), amount); // amount adapter receives

        // airdrop all the usdc to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        cctpAdapterHarness.exposed_execute{gas: 120000}(
            "arbitrum",
            AddressToString.toString(address(cctpAdapter)),
            abi.encode(
                address(user), // to
                amount, // amount
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
            )
        );

        assertEq(
            usdc.balanceOf(address(cctpAdapterHarness)),
            0,
            "cctpAdapter should have 0 usdc"
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
