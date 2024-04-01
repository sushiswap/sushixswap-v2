// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {RouterNitroAdapter} from "../../src/adapters/RouterNitroAdapter.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

import {StringToBytes32, Bytes32ToString} from "../../src/utils/Bytes32String.sol";
import {StringToAddress, AddressToString} from "../../src/utils/AddressString.sol";

contract RouterNitroAdapterBridgeTest is BaseTest {
    using SafeERC20 for IERC20;

    SushiXSwapV2 public sushiXswap;
    RouterNitroAdapter public routerNitroAdapter;
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

        // setup routerNitro adapter
        routerNitroAdapter = new RouterNitroAdapter(
            constants.getAddress("mainnet.nitroAssetForwarder"),
            constants.getAddress("mainnet.routeProcessor"),
            constants.getAddress("mainnet.weth")
        );
        sushiXswap.updateAdapterStatus(address(routerNitroAdapter), true);

        vm.stopPrank();
    }

    function _getChainIdBytes(string memory _chainId) internal pure returns (bytes32){
        bytes32 chainIdBytes32;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            chainIdBytes32 := mload(add(_chainId, 32))
        }

        return chainIdBytes32;
    }

    function _toBytes(address a) internal pure returns (bytes memory b) {
        assembly {
            let m := mload(0x40)
            a := and(a, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            mstore(add(m, 20), xor(0x140000000000000000000000000000000000000000, a))
            mstore(0x40, add(m, 52))
            b := m
        }
    }


    function test_RevertWhen_SendingMessage() public {
        vm.startPrank(user);
        vm.expectRevert();
        sushiXswap.sendMessage(address(routerNitroAdapter), "");
    }

    function test_BridgeERC20() public {
        uint32 amount = 1000000; // 1 usdt
        uint32 destAmount = 900000; // 0.9 usdt

        deal(address(usdt), user, amount);

        address arbitrumUsdt = constants.getAddress("arbitrum.usdt");

        vm.startPrank(user);
        usdt.safeIncreaseAllowance(address(sushiXswap), amount);
        usdt.balanceOf(user);

        RouterNitroAdapter.NitroBridgeParams memory nitroBridgeParams = RouterNitroAdapter.NitroBridgeParams({
           destChainIdBytes: _getChainIdBytes("42161"), // dest chain -> arbitrum
           destinationAddress: _toBytes(address(routerNitroAdapter)), // destinationAddress
           srcToken: address(usdt), // src token
           amount: amount, // amount
           destAmount: destAmount, // dest amount
           destToken: _toBytes(arbitrumUsdt), // dest token
           refundRecipient: user, // refund recipient
           to: user // to
        });

        sushiXswap.bridge(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(routerNitroAdapter),
                tokenIn: address(usdt),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(nitroBridgeParams)
            }),
            user, // _refundAddress
            "", // swap payload
            "" // payload data
        );

        assertEq(
            usdt.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdt"
        );
        assertEq(usdt.balanceOf(user), 0, "user should have 0 usdt");
    }

    function test_BridgeNative() public {
        uint64 amount = 1 ether; // 1 eth
        uint64 destAmount = 0.9999 ether; // 0.9999 eth

        vm.deal(user, amount);

        vm.startPrank(user);

        RouterNitroAdapter.NitroBridgeParams memory nitroBridgeParams = RouterNitroAdapter.NitroBridgeParams({
           destChainIdBytes: _getChainIdBytes("42161"), // dest chain -> arbitrum
           destinationAddress: _toBytes(address(routerNitroAdapter)), // destinationAddress
           srcToken: NATIVE_ADDRESS, // src token
           amount: amount, // amount
           destAmount: destAmount, // dest amount
           destToken: _toBytes(NATIVE_ADDRESS), // dest token
           refundRecipient: user, // refund recipient
           to: user // to
        });


        sushiXswap.bridge{value: amount}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(routerNitroAdapter),
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                to: user,
                adapterData: abi.encode(nitroBridgeParams)
            }),
            user, // _refundAddress
            "", // swap payload
            "" // payload data
        );

        assertEq(
            address(routerNitroAdapter).balance,
            0,
            "routerNitroAdapter should have 0 Native tokens"
        );
        assertEq(user.balance, 0, "user should have 0 Native tokens");
    }

    function test_BridgeERC20WithSwapData() public {
        uint32 amount = 1000000; // 1 usdt
        uint32 destAmount = 900000; // 0.9 usdt

        deal(address(usdt), user, amount);
        address arbitrumUsdt = constants.getAddress("arbitrum.usdt");

        bytes memory computedRoute_dst = routeProcessorHelper.computeRoute(
            false,
            false,
            address(usdt),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd_dst = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdt),
                amountIn: 0, // amountIn doesn't matter on dst since we use amount bridged
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute_dst
            });

        bytes memory rpd_encoded_dst = abi.encode(rpd_dst);

        // basic usdt bridge, mint axlusdt on otherside
        vm.startPrank(user);
        usdt.safeIncreaseAllowance(address(sushiXswap), amount);

        RouterNitroAdapter.NitroBridgeParams memory nitroBridgeParams = RouterNitroAdapter.NitroBridgeParams({
           destChainIdBytes: _getChainIdBytes("42161"), // dest chain -> arbitrum
           destinationAddress: _toBytes(address(routerNitroAdapter)), // destinationAddress
           srcToken: address(usdt), // src token
           amount: amount, // amount
           destAmount: destAmount, // dest amount
           destToken: _toBytes(arbitrumUsdt), // dest token
           refundRecipient: user, // refund recipient
           to: user // to
        });

        sushiXswap.bridge(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(routerNitroAdapter),
                tokenIn: address(usdt),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(nitroBridgeParams)
            }),
            user, // _refundAddress
            rpd_encoded_dst, // swap payload
            "" // payload data
        );

        assertEq(
            usdt.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdt"
        );
        assertEq(usdt.balanceOf(user), 0, "user should have 0 usdt");
    }

    function test_BridgeNativeWithSwapData() public {
        uint64 amount = 1 ether; // 1 eth
        uint64 destAmount = 0.9999 ether; // 0.9999 eth

        vm.deal(user, amount);

        bytes memory computedRoute_dst = routeProcessorHelper.computeRoute(
            false,
            false,
            address(usdt),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd_dst = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdt),
                amountIn: 0, // amountIn doesn't matter on dst since we use amount bridged
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute_dst
            });

        bytes memory rpd_encoded_dst = abi.encode(rpd_dst);

        // basic eth bridge, mint axlWETH on otherside
        vm.startPrank(user);

        RouterNitroAdapter.NitroBridgeParams memory nitroBridgeParams = RouterNitroAdapter.NitroBridgeParams({
           destChainIdBytes: _getChainIdBytes("42161"), // dest chain -> arbitrum
           destinationAddress: _toBytes(address(routerNitroAdapter)), // destinationAddress
           srcToken: NATIVE_ADDRESS, // src token
           amount: amount, // amount
           destAmount: destAmount, // dest amount
           destToken: _toBytes(NATIVE_ADDRESS), // dest token
           refundRecipient: user, // refund recipient
           to: user // to
        });

        sushiXswap.bridge{value: amount}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(routerNitroAdapter),
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                to: user,
                adapterData: abi.encode(nitroBridgeParams)
            }),
            user, // _refundAddress
            rpd_encoded_dst, // swap payload
            "" // payload data
        );
        
        assertEq(
            address(routerNitroAdapter).balance,
            0,
            "routerNitroAdapter should have 0 usdt"
        );
        assertEq(user.balance, 0, "user should have 0 usdt");
    }
}
