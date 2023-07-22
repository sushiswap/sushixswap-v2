// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../interfaces/IRouteProcessor.sol";
import "../interfaces/IWeth.sol";
import "axelar-gmp-sdk-solidity/executable/AxelarExecutable.sol";
import "axelar-gmp-sdk-solidity/interfaces/IAxelarGasService.sol";
import "axelar-gmp-sdk-solidity/interfaces/IAxelarGateway.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ISushiXSwapV2Adapter.sol";

import {AddressToString} from "../utils/AddressString.sol";
import {Bytes32ToString} from "../utils/Bytes32String.sol";

contract AxelarAdapter is ISushiXSwapV2Adapter, AxelarExecutable {
    using SafeERC20 for IERC20;

    IAxelarGasService public immutable axelarGasService;
    IRouteProcessor public immutable rp;
    IWETH public immutable weth;

    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct AxelarBridgeParams {
        address token; // token getting bridged
        bytes32 destinationChain; // destination chain name
        address destinationAddress; // destination address for _execute call
        bytes32 symbol; // bridged token symbol
        uint256 amount; // amount to bridge
        address to; // address for fallback transfers on _execute call
    }

    error RpSentNativeIn();

    constructor(
        address _axelarGateway,
        address _gasService,
        address _rp,
        address _weth
    ) AxelarExecutable(_axelarGateway) {
        axelarGasService = IAxelarGasService(_gasService);
        rp = IRouteProcessor(_rp);
        weth = IWETH(_weth);
    }

    function swap(
        uint256 _amountBridged,
        bytes calldata _swapData,
        address _token,
        bytes calldata _payloadData
    ) external payable override {
        IRouteProcessor.RouteProcessorData memory rpd = abi.decode(
            _swapData,
            (IRouteProcessor.RouteProcessorData)
        );
        // increase token approval to RP
        IERC20(rpd.tokenIn).safeIncreaseAllowance(address(rp), _amountBridged);

        rp.processRoute(
            rpd.tokenIn,
            _amountBridged != 0 ? _amountBridged : rpd.amountIn,
            rpd.tokenOut,
            rpd.amountOutMin,
            rpd.to,
            rpd.route
        );

        // tokens should be sent via rp
        if (_payloadData.length > 0) {
            PayloadData memory pd = abi.decode(_payloadData, (PayloadData));
            try
                IPayloadExecutor(pd.target).onPayloadReceive(pd.targetData)
            {} catch (bytes memory) {
                revert();
            }
        }
    }

    function executePayload(
        uint256 _amountBridged,
        bytes calldata _payloadData,
        address _token
    ) external payable override {
        PayloadData memory pd = abi.decode(_payloadData, (PayloadData));
        IERC20(_token).safeTransfer(pd.target, _amountBridged);
        IPayloadExecutor(pd.target).onPayloadReceive(pd.targetData);
    }

    function adapterBridge(
        bytes calldata _adapterData,
        bytes calldata _swapData,
        bytes calldata _payloadData
    ) external payable override {
        AxelarBridgeParams memory params = abi.decode(
            _adapterData,
            (AxelarBridgeParams)
        );

        if (params.token == NATIVE_ADDRESS) {
            // RP should not send native in, since we won't know the exact amount to bridge
            if (params.amount == 0) revert RpSentNativeIn();
            weth.deposit{value: params.amount}();
            params.token = address(weth);
        }

        if (params.amount == 0)
            params.amount = IERC20(params.token).balanceOf(address(this));

        // approve token to gateway
        IERC20(params.token).safeApprove(address(gateway), params.amount);

        // build payload from _swapData and _payloadData
        // to will receive bridged funds from fallback if no swap or payload data
        bytes memory payload = abi.encode(params.to, _swapData, _payloadData);

        // pay native gas to gasService
        axelarGasService.payNativeGasForContractCallWithToken{
            value: address(this).balance
        }(
            address(this),
            Bytes32ToString.toTrimmedString(params.destinationChain),
            AddressToString.toString(params.destinationAddress),
            payload,
            Bytes32ToString.toTrimmedString(params.symbol),
            params.amount,
            payable(tx.origin) // refund address
        );

        // sendToken and message w/ payload to the gateway contract
        gateway.callContractWithToken(
            Bytes32ToString.toTrimmedString(params.destinationChain),
            AddressToString.toString(params.destinationAddress),
            payload,
            Bytes32ToString.toTrimmedString(params.symbol),
            params.amount
        );
    }

    /// @notice Receiver function on dst chain
    /// @param sourceChain source chain name
    /// @param sourceAddress source address
    /// @param payload payload data
    /// @param tokenSymbol bridged token symbol
    /// @param amount bridged token amount
    function _executeWithToken(
        string memory sourceChain,
        string memory sourceAddress,
        bytes calldata payload,
        string memory tokenSymbol,
        uint256 amount
    ) internal override {
        (address to, bytes memory _swapData, bytes memory _payloadData) = abi
            .decode(payload, (address, bytes, bytes));
        address _token = gateway.tokenAddresses(tokenSymbol);

        uint256 reserveGas = 100000;

        if (gasleft() < reserveGas) {
            IERC20(_token).safeTransfer(to, amount);

            /// @dev transfer any native token
            if (address(this).balance > 0)
                to.call{value: (address(this).balance)}("");

            return;
        }

        // 100000 -> exit gas
        uint256 limit = gasleft() - reserveGas;
        bool failed;

        if (_swapData.length > 0) {
            try
                ISushiXSwapV2Adapter(address(this)).swap{gas: limit}(
                    amount,
                    _swapData,
                    _token,
                    _payloadData
                )
            {} catch (bytes memory) {
                failed = true;
            }
        } else if (_payloadData.length > 0) {
            try
                ISushiXSwapV2Adapter(address(this)).executePayload{gas: limit}(
                    amount,
                    _payloadData,
                    _token
                )
            {} catch (bytes memory) {
                failed = true;
            }
        } else {
            failed = true;
        }

        if (failed) IERC20(_token).safeTransfer(to, amount);

        /// @dev transfer any native token received as dust to the to address
        if (address(this).balance > 0)
            to.call{value: (address(this).balance)}("");
    }

    function sendMessage(bytes calldata _adapterData) external override {
        (_adapterData);
        revert();
    }

    receive() external payable {}
}
