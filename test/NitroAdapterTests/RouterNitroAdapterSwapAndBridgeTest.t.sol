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

contract RouterNitroAdapterSwapAndBridgeTest is BaseTest {
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

    function test_SwapFromERC20ToERC20AndBridge() public {
        // basic swap 1 weth to usdc and bridge
        uint64 amount = 1 ether; // 1 weth
        address arbitrumUsdt = constants.getAddress("arbitrum.usdt");

        deal(address(weth), user, amount);

        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true, // rpHasToken
            false, // isV2
            address(weth), // tokenIn
            address(usdt), // tokenOut
            500, // fee
            address(routerNitroAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(weth),
                amountIn: amount,
                tokenOut: address(usdt),
                amountOutMin: 0,
                to: address(routerNitroAdapter),
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        vm.startPrank(user);
        IERC20(address(weth)).safeIncreaseAllowance(address(sushiXswap), amount);

        RouterNitroAdapter.NitroBridgeParams memory nitroBridgeParams = RouterNitroAdapter.NitroBridgeParams({
           destChainIdBytes: _getChainIdBytes("42161"), // dest chain -> arbitrum
           destinationAddress: _toBytes(address(routerNitroAdapter)), // destinationAddress
           srcToken: address(usdt), // src token
           amount: 0, // amount
           destAmount: 0, // dest amount
           destToken: _toBytes(arbitrumUsdt), // dest token
           refundRecipient: user, // refund recipient
           to: user // to
        });

        sushiXswap.swapAndBridge(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(routerNitroAdapter),
                tokenIn: address(weth),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(nitroBridgeParams)
            }),
            user, // _refundAddress
            rpd_encoded, // swap data
            "", // swap payload data
            "" // payload data
        );

        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            weth.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_SwapFromERC20ToUSDTAndBridge(uint32 amount) public {
        vm.assume(amount > 1000000); // > 1 usdt
        address arbitrumUsdt = constants.getAddress("arbitrum.usdt");

        deal(address(usdc), user, amount);

        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true, // rpHasToken
            false, // isV2
            address(usdc), // tokenIn
            address(usdt), // tokenOut
            100, // fee
            address(routerNitroAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(usdt),
                amountOutMin: 0,
                to: address(routerNitroAdapter),
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        vm.startPrank(user);
        IERC20(address(usdc)).safeIncreaseAllowance(address(sushiXswap), amount);

        RouterNitroAdapter.NitroBridgeParams memory nitroBridgeParams = RouterNitroAdapter.NitroBridgeParams({
           destChainIdBytes: _getChainIdBytes("42161"), // dest chain -> arbitrum
           destinationAddress: _toBytes(address(routerNitroAdapter)), // destinationAddress
           srcToken: address(usdt), // src token
           amount: 0, // amount
           destAmount: 0, // dest amount
           destToken: _toBytes(arbitrumUsdt), // dest token
           refundRecipient: user, // refund recipient
           to: user // to
        });

        sushiXswap.swapAndBridge(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(routerNitroAdapter),
                tokenIn: address(usdt),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(nitroBridgeParams)
            }),
            user, // _refundAddress
            rpd_encoded, // swap data
            "", // swap payload data
            "" // payload data
        );

        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            usdt.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdt"
        );
        assertEq(usdt.balanceOf(user), 0, "user should have 0 usdt");
    }

    function test_SwapFromNativeToERC20AndBridge() public {
        // basic swap 1 eth to usdc and bridge
        uint64 amount = 1 ether; // 1 eth
        address arbitrumUsdt = constants.getAddress("arbitrum.usdt");

        uint256 valueToSend = amount;
        vm.deal(user, valueToSend);

        bytes memory computeRoute = routeProcessorHelper.computeRouteNativeIn(
            address(weth), // wrapToken
            false, // isV2
            address(usdt), // tokenOut
            500, // fee
            address(routerNitroAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                tokenOut: address(usdt),
                amountOutMin: 0,
                to: address(routerNitroAdapter),
                route: computeRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        vm.startPrank(user);

        RouterNitroAdapter.NitroBridgeParams memory nitroBridgeParams = RouterNitroAdapter.NitroBridgeParams({
           destChainIdBytes: _getChainIdBytes("42161"), // dest chain -> arbitrum
           destinationAddress: _toBytes(address(routerNitroAdapter)), // destinationAddress
           srcToken: address(usdt), // src token
           amount: 0, // amount
           destAmount: 0, // dest amount
           destToken: _toBytes(arbitrumUsdt), // dest token
           refundRecipient: user, // refund recipient
           to: user // to
        });

        sushiXswap.swapAndBridge{value: valueToSend}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(routerNitroAdapter),
                tokenIn: NATIVE_ADDRESS, // doesn't matter what you put for bridge params when swapping first
                amountIn: amount,
                to: user,
                adapterData: abi.encode(nitroBridgeParams)
            }),
            user, // _refundAddress
            rpd_encoded, // swap data
            "", // swap payload data
            "" // payload data
        );

        assertEq(
            address(routerNitroAdapter).balance,
            0,
            "routerNitroAdapter should have 0 eth"
        );
        assertEq(user.balance, 0, "user should have 0 eth");
        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
    }

    function test_SwapFromERC20ToNativeAndBridge() public {
        // basic swap 1 usdc to native and bridge
        uint32 amount = 1000000; // 1 usdc

        deal(address(usdc), user, amount);

        bytes memory computeRoute = routeProcessorHelper.computeRouteNativeOut(
            true, // rpHasToken
            false, // isV2
            address(usdc), // tokenIn
            address(weth), // tokenOut
            500, // fee
            address(routerNitroAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: NATIVE_ADDRESS,
                amountOutMin: 0,
                to: address(routerNitroAdapter),
                route: computeRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        vm.startPrank(user);
        IERC20(address(usdc)).safeIncreaseAllowance(address(sushiXswap), amount);

        RouterNitroAdapter.NitroBridgeParams memory nitroBridgeParams = RouterNitroAdapter.NitroBridgeParams({
           destChainIdBytes: _getChainIdBytes("42161"), // dest chain -> arbitrum
           destinationAddress: _toBytes(address(routerNitroAdapter)), // destinationAddress
           srcToken: NATIVE_ADDRESS, // src token
           amount: 0, // amount
           destAmount: 0, // dest amount
           destToken: _toBytes(NATIVE_ADDRESS), // dest token
           refundRecipient: user, // refund recipient
           to: user // to
        });

        sushiXswap.swapAndBridge(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(routerNitroAdapter),
                tokenIn: address(weth), // doesn't matter what you put for bridge params when swapping first
                amountIn: amount,
                to: user,
                adapterData: abi.encode(nitroBridgeParams)
            }),
            user, // _refundAddress
            rpd_encoded, // swap data
            "", // swap payload data
            "" // payload data
        );

        assertEq(
            address(routerNitroAdapter).balance,
            0,
            "routerNitroAdapter should have 0 eth"
        );
        assertEq(user.balance, 0, "user should have 0 eth");
        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");

    }
}
