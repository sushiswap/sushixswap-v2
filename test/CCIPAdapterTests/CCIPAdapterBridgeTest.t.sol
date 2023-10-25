// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {CCIPAdapter} from "../../src/adapters/CCIPAdapter.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

import {IOwnerAndAllowListManager} from "./interfaces/IOwnerAndAllowListManager.sol";

contract CCIPAdapterBridgeTest is BaseTest {
    using SafeERC20 for IERC20;

    SushiXSwapV2 public sushiXswap;
    CCIPAdapter public ccipAdapter;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;

    IWETH public weth;
    IERC20 public sushi;
    IERC20 public usdc;
    IERC20 public usdt;
    IERC20 public betsToken;

    uint64 op_chainId = 3734403246176062136; // OP
    uint64 base_chainId = 15971525489660198786; // base
    uint64 polygon_chainId = 4051577828743386545; // polygon

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
        betsToken = IERC20(constants.getAddress("mainnet.betsToken"));

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
        ccipAdapter = new CCIPAdapter(
            constants.getAddress("mainnet.ccipRouter"),
            constants.getAddress("mainnet.link"),
            constants.getAddress("mainnet.routeProcessor"),
            constants.getAddress("mainnet.weth")
        );
        sushiXswap.updateAdapterStatus(address(ccipAdapter), true);

        vm.stopPrank();

        // turn off allowlist on Evm2EvmOnRamp
        IOwnerAndAllowListManager onRamp = IOwnerAndAllowListManager(
            constants.getAddress("mainnet.evm2evmOnRamp")
        );
        IOwnerAndAllowListManager burnMintPool = IOwnerAndAllowListManager(
            constants.getAddress("mainnet.burnMintTokenPool")
        );
        vm.prank(onRamp.owner());
        onRamp.setAllowListEnabled(false);
        vm.prank(burnMintPool.owner());
        address[] memory removeList = new address[](1);
        removeList[0] = address(0x0);
        address[] memory addList = new address[](1);
        addList[0] = address(ccipAdapter);
        burnMintPool.applyAllowListUpdates(removeList, addList);
    }

    function test_RevertWhen_SendingMessage() public {
        vm.startPrank(user);
        vm.expectRevert();
        sushiXswap.sendMessage(address(ccipAdapter), "");
    }

    function test_getFee() public {
        bytes memory adapterData = abi.encode(
            polygon_chainId, // chainId
            user, // receiver
            address(ccipAdapter), // to
            address(betsToken), // token
            0.1 ether, // amount
            150000 // gasLimit
        );

        uint256 fees = ccipAdapter.getFee(adapterData, "", "");

        assertGt(fees, 0, "fees should be greater than 0");
    }

    function testFuzz_BridgeERC20(uint64 amount) public {
        vm.assume(amount > 0.1 ether);

        bytes memory adapterData = abi.encode(
            polygon_chainId, // chainId
            user, // receiver
            address(ccipAdapter), // to
            address(betsToken), // token
            amount, // amount
            150000 // gasLimit
        );
        uint256 gasNeeded = ccipAdapter.getFee(adapterData, "", "");

        deal(address(betsToken), user, amount);
        vm.deal(user, gasNeeded);

        // basic betsToken bridge, mint betsToken on otherside
        vm.startPrank(user);
        betsToken.safeIncreaseAllowance(address(sushiXswap), amount);

        sushiXswap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(ccipAdapter),
                tokenIn: address(betsToken),
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // _refundAddress
            "", // swap payload
            "" // payload data
        );

        assertEq(
            betsToken.balanceOf(address(ccipAdapter)),
            0,
            "ccipAdapter should have 0 betsToken"
        );
        assertEq(betsToken.balanceOf(user), 0, "user should have 0 betsToken");
    }

    function test_RevertWhen_BridgeERC20WithNotEnoughNativeForFees() public {
        uint64 amount = 0.1 ether;

        bytes memory adapterData = abi.encode(
            polygon_chainId, // chainId
            user, // receiver
            address(ccipAdapter), // to
            address(betsToken), // token
            amount, // amount
            150000 // gasLimit
        );
        uint256 gasNeeded = ccipAdapter.getFee(adapterData, "", "");

        deal(address(betsToken), user, amount);
        vm.deal(user, gasNeeded);

        // basic betsToken bridge, mint betsToken on otherside
        vm.startPrank(user);
        betsToken.safeIncreaseAllowance(address(sushiXswap), amount);

        bytes4 selector = bytes4(keccak256("NotEnoughNativeForFees(uint256,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector, 100, gasNeeded));
        sushiXswap.bridge{value: 100}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(ccipAdapter),
                tokenIn: address(betsToken),
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // _refundAddress
            "", // swap payload
            "" // payload data
        );
    }

    // todo: revert when gas limit not enough
    function test_RevertWhen_BridgeERC20WithInsufficentGas() public {
        uint64 amount = 0.1 ether;

        bytes memory adapterData = abi.encode(
            polygon_chainId, // chainId
            user, // receiver
            address(ccipAdapter), // to
            address(betsToken), // token
            amount, // amount
            500 // gasLimit
        );

        bytes memory computedRoute_dst = routeProcessorHelper.computeRoute(
            false,
            false,
            address(betsToken),
            address(usdc),
            3000,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd_dst = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(betsToken),
                amountIn: 0,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: user,
                route: computedRoute_dst
            });

        bytes memory rpd_encoded_dst = abi.encode(rpd_dst);

        uint256 gasNeeded = ccipAdapter.getFee(adapterData, rpd_encoded_dst, "");

        deal(address(betsToken), user, amount);
        vm.deal(user, gasNeeded);

        // basic betsToken bridge, mint betsToken on otherside
        vm.startPrank(user);
        betsToken.safeIncreaseAllowance(address(sushiXswap), amount);

        vm.expectRevert(bytes4(keccak256("InsufficientGas()")));
        sushiXswap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(ccipAdapter),
                tokenIn: address(betsToken),
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // _refundAddress
            rpd_encoded_dst, // swap payload
            "" // payload data
        );
    }

    function test_RevertWhen_BridgeUnsupportedERC20() public {
        uint64 amount = 0.1 ether;
        uint64 gasNeeded = 0.1 ether;

        deal(address(sushi), user, amount);
        vm.deal(user, gasNeeded);

        // try to bridge sushi (unsupported token)
        vm.startPrank(user);
        sushi.safeIncreaseAllowance(address(sushiXswap), amount);

        vm.expectRevert();
        sushiXswap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(ccipAdapter),
                tokenIn: address(sushi),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    polygon_chainId, // chainId
                    user, // receiver
                    user, // to
                    address(sushi), // token
                    amount, // amount
                    150000 // gasLimit
                )
            }),
            user, // _refundAddress
            "", // swap payload
            "" // payload data
        );
    }

    function testFuzz_BridgeERC20WithSwapData(uint64 amount) public {
        vm.assume(amount > 0.1 ether);
        

        bytes memory adapterData = abi.encode(
            polygon_chainId, // chainId
            user, // receiver
            address(ccipAdapter), // to
            address(betsToken), // token
            amount, // amount
            150000 // gasLimit
        );

        bytes memory computedRoute_dst = routeProcessorHelper.computeRoute(
            false,
            false,
            address(betsToken),
            address(usdc),
            3000,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd_dst = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(betsToken),
                amountIn: 0,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: user,
                route: computedRoute_dst
            });

        bytes memory rpd_encoded_dst = abi.encode(rpd_dst);

        uint256 gasNeeded = ccipAdapter.getFee(adapterData, rpd_encoded_dst, "");

        deal(address(betsToken), user, amount);
        vm.deal(user, gasNeeded);

        // basic betsToken bridge, mint betsToken on otherside
        vm.startPrank(user);
        betsToken.safeIncreaseAllowance(address(sushiXswap), amount);

        sushiXswap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(ccipAdapter),
                tokenIn: address(betsToken),
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // _refundAddress
            rpd_encoded_dst, // swap payload
            "" // payload data
        );

        assertEq(
            betsToken.balanceOf(address(ccipAdapter)),
            0,
            "ccipAdapter should have 0 betsToken"
        );
        assertEq(betsToken.balanceOf(user), 0, "user should have 0 betsToken");
    }

    function test_RevertWhen_BridgeERC20WithNoGasPassed() public {
        uint64 amount = 0.1 ether;
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(betsToken), user, amount);
        vm.deal(user, gasNeeded);

        // basic betsToken bridge, mint betsToken on otherside
        vm.startPrank(user);
        betsToken.safeIncreaseAllowance(address(sushiXswap), amount);

        vm.expectRevert();
        sushiXswap.bridge(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(ccipAdapter),
                tokenIn: address(betsToken),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    polygon_chainId, // chainId
                    user, // receiver
                    user, // to
                    address(betsToken), // token
                    amount, // amount
                    150000 // gasLimit
                )
            }),
            user, // _refundAddress
            "", // swap payload
            "" // payload data
        );
    }
}
