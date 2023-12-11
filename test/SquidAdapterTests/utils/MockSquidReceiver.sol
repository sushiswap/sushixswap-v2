// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {ISquidMulticall} from "src/interfaces/squid/ISquidMulticall.sol";

contract MockSquidReceiver is AxelarExecutable {
    using SafeERC20 for IERC20;

    error ApprovalFailed();

    event CrossMulticallExecuted(bytes32 indexed payloadHash);
    event CrossMulticallFailed(bytes32 indexed payloadHash, bytes reason, address indexed refundRecipient);

    ISquidMulticall public squidMulticall;

    constructor(address _axelarGateway, address _squidMulticall) AxelarExecutable(_axelarGateway) {
        squidMulticall = ISquidMulticall(_squidMulticall);
    }

    function _approve(address token, address spender, uint256 amount) private {
        uint256 allowance = IERC20(token).allowance(address(this), spender);
        if (allowance < amount) {
            if (allowance > 0) {
                _approveCall(token, spender, 0);
            }
            _approveCall(token, spender, type(uint256).max);
        }
    }

    function _approveCall(address token, address spender, uint256 amount) private {
        // Unlimited approval is not security issue since the contract doesn't store tokens
        (bool success,) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        if (!success) revert ApprovalFailed();
    }

    function exposed_executeWithToken(
        string calldata,
        string calldata,
        bytes calldata payload,
        string calldata bridgedTokenSymbol,
        uint256
    ) external {
        (ISquidMulticall.Call[] memory calls, address refundRecipient) =
            abi.decode(payload, (ISquidMulticall.Call[], address));

        address bridgedTokenAddress = gateway.tokenAddresses(bridgedTokenSymbol);
        uint256 contractBalance = IERC20(bridgedTokenAddress).balanceOf(address(this));

        _approve(bridgedTokenAddress, address(squidMulticall), contractBalance);

        try squidMulticall.run(calls) {
            emit CrossMulticallExecuted(keccak256(payload));
        } catch (bytes memory reason) {
            // Refund tokens to refund recipient if swap fails
            IERC20(bridgedTokenAddress).safeTransfer(refundRecipient, contractBalance);
            emit CrossMulticallFailed(keccak256(payload), reason, refundRecipient);
        }
    }
}
