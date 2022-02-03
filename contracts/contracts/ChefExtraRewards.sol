// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-0.6/utils/Address.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";


/**
 * @title   ChefExtraRewards
 * @author  ConvexFinance
 * @notice  This is currently only a test contract to test extra rewards on master chef
 * @dev     When a user deposits/withdraws/claims in MasterChef, this hook `onReward` is called.
 */
contract ChefExtraRewards{
    using SafeERC20 for IERC20;
    
    IERC20 public rewardToken;
    address public chef;

    constructor(
        address chef_,
        address reward_
    ) public {
        chef = chef_;
        rewardToken = IERC20(reward_);
    }

    function pendingTokens(uint256 _pid, address _account, uint256 _sushiAmount) external view returns (IERC20[] memory, uint256[] memory) {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = rewardToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _sushiAmount;
        return (tokens,amounts);
    }


    function onReward(uint256 _pid, address _account, address _recipient, uint256 _sushiAmount, uint256 _newLpAmount) external{
        require(msg.sender == chef,"!auth");

        safeRewardTransfer(_recipient,_sushiAmount);
    }

    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 bal = rewardToken.balanceOf(address(this));
        if (_amount > bal) {
            rewardToken.safeTransfer(_to, bal);
        } else {
            rewardToken.safeTransfer(_to, _amount);
        }
    }

}