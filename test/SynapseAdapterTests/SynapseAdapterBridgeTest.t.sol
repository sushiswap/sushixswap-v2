// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {SynapseAdapter} from "../../src/adapters/SynapseAdapter.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../../utils/BaseTest.sol";

contract SynapseAdapterBridgeTest is BaseTest {
    SushiXSwapV2 public sushiXswap;
    SynapseAdapter public synapseAdapter;
    IRouteProcessor public routeProcessor;

    IWETH public weth;
    ERC20 public sushi;
    ERC20 public usdc;

    address constant NATIVE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public operator = address(0xbeef);
    address public owner = address(0x420);
    address public user = address(0x4201);

    function setUp() public override {
        forkMainnet();
        super.setUp();

        weth = IWETH(constants.getAddress("mainnet.weth"));
        sushi = ERC20(constants.getAddress("mainnet.sushi"));
        usdc = ERC20(constants.getAddress("mainnet.usdc"));

        routeProcessor = IRouteProcessor(
            constants.getAddress("mainnet.routeProcessor")
        );

        vm.startPrank(owner);
        sushiXswap = new SushiXSwapV2(routeProcessor, address(weth));

        // add operator as privileged
        sushiXswap.setPrivileged(operator, true);

        // setup synapse adapter
        synapseAdapter = new SynapseAdapter(
            constants.getAddress("mainnet.synapseBridge"),
            constants.getAddress("mainnet.weth")
        );
        sushiXswap.updateAdapterStatus(address(synapseAdapter), true);

        vm.stopPrank();
    }

    /* test_BridgeERC20 */
    /* test_BridgeNative */
    /* testFailWhen */
    /* test_swapERC20ToNativeBridgeNative */

    function test_BridgeERC20() public {
        uint32 amount = 1000000; // 1 usdc

        deal(address(usdc), user, amount);

        // basic usdc bridge
        vm.startPrank(user);
        usdc.approve(address(sushiXswap), amount);

        sushiXswap.bridge(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(synapseAdapter),
                tokenIn: address(usdc),
                amountIn: amount,
                to: address(0x0),
                adapterData: abi.encode(
                    42161,
                    address(usdc),
                    amount,
                    user           // to
                )
            }),
            "", // swap payload
            ""  // payload data
        );
    }

    function test_BridgeNative() public {
        uint256 amount = 1 ether;

        deal(user, amount);

        vm.startPrank(user);
        sushiXswap.bridge{value: amount}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x000,
                adapter: address(synapseAdapter),
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                to: address(0x0),
                adapterData: abi.encode(
                    42161,
                    NATIVE_ADDRESS,
                    amount,
                    user
                )
            }),
            "", // swap payload
            "" // payload data
        );
    }
}