// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SwapAllToETH {
    IUniswapV2Router02 public immutable uniswapRouter;
    address public immutable WETH;

    event TokenSwapped(
        address indexed user,
        address indexed token,
        uint256 amountIn,
        uint256 minAmountOut
    );

    event TokenRefunded(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    constructor(address _router, address _weth) {
        uniswapRouter = IUniswapV2Router02(_router);
        WETH = _weth;
    }

    function swapAllTokensToETH(address[] calldata tokens, uint256 slippageBps) external {
        require(slippageBps <= 10_000, "Slippage too high");

        for (uint256 i = 0; i < tokens.length; i++) {
            address tokenAddress = tokens[i];
            IERC20 token = IERC20(tokenAddress);

            uint256 userBalance = token.balanceOf(msg.sender);
            if (userBalance == 0) continue;

            // Transfer tokens to this contract using low-level call
            (bool success, bytes memory data) = tokenAddress.call(
                abi.encodeWithSelector(token.transferFrom.selector, msg.sender, address(this), userBalance)
            );

            bool transferOK = success && (data.length == 0 || abi.decode(data, (bool)));
            if (!transferOK) continue;

            uint256 received = token.balanceOf(address(this));
            if (received == 0) continue;

            // Approve the router
            if (token.allowance(address(this), address(uniswapRouter)) < received) {
                try token.approve(address(uniswapRouter), type(uint256).max) {} catch {
                    try token.approve(address(uniswapRouter), 0) {
                        token.approve(address(uniswapRouter), type(uint256).max);
                    } catch {
                        // Refund if approval fails
                        _refundToken(tokenAddress, msg.sender, received);
                        continue;
                    }
                }
            }

            address[] memory path = new address[](2) ;
            path[0] = tokenAddress;
            path[1] = WETH;

            uint256[] memory amountsOut;
            try uniswapRouter.getAmountsOut(received, path) returns (uint256[] memory out) {
                amountsOut = out;
            } catch {
                // Refund if getAmountsOut fails
                _refundToken(tokenAddress, msg.sender, received);
                continue;
            }

            if (amountsOut.length < 2) {
                _refundToken(tokenAddress, msg.sender, received);
                continue;
            }

            uint256 minOut = (amountsOut[1] * (10_000 - slippageBps)) / 10_000;

            // Try swapping
            try uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
                received,
                minOut,
                path,
                msg.sender,
                block.timestamp
            ) {
                emit TokenSwapped(msg.sender, tokenAddress, received, minOut);
            } catch {
                // Refund if swap fails
                _refundToken(tokenAddress, msg.sender, received);
                continue;
            }
        }
    }

    // Internal function to refund user
    function _refundToken(address tokenAddress, address user, uint256 amount) internal {
        (bool sent, bytes memory data) = tokenAddress.call(
            abi.encodeWithSelector(IERC20.transfer.selector, user, amount)
        );

        bool refundOK = sent && (data.length == 0 || abi.decode(data, (bool)));
        if (refundOK) {
            emit TokenRefunded(user, tokenAddress, amount);
        }
    }

    // Allow contract to receive ETH
    receive() external payable {}

    // Optional manual rescue function (only if anything still gets stuck)
    function rescueStuckTokens(address tokenAddress) external {
        IERC20 token = IERC20(tokenAddress);
        uint256 stuckAmount = token.balanceOf(address(this));
        require(stuckAmount > 0, "No tokens to rescue");

        (bool success, bytes memory data) = tokenAddress.call(
            abi.encodeWithSelector(token.transfer.selector, msg.sender, stuckAmount)
        );

        bool transferOK = success && (data.length == 0 || abi.decode(data, (bool)));
        require(transferOK, "Rescue transfer failed");
    }

    function rescueETH() external {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to rescue");

        (bool sent, ) = msg.sender.call{value: balance}("");
        require(sent, "ETH rescue failed");
    }
}
