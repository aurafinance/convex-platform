// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./interfaces/IRewardHook.sol";
import "./interfaces/IChef.sol";
import "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";


/**
 * @title   ChefRewardHook
 * @author  ConvexFinance
 * @notice  Receive rewards from chef for distribution to a pool
 * @dev     This effectively syphons rewards from the MasterChef contract and sends to the Stash of
 *          an active RewardPool. The Booster orchestrates this by calling `IStash(stash).claimRewards()`
 *          which calls `onRewardClaim` here, transferring CVX back to the stash, then `IStash(stash).processStash()`
 *          which processes the rwds to the given VirtualRewardPool.
 */
contract ChefRewardHook is IRewardHook{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public immutable rewardToken;
    
    address public immutable chef;
    address public distributor;
    uint256 public pid;

    bool public isInit;

    /**
     * @notice Sets up state
     * @param _rewardToken  e.g. CVX
     * @param _chef         e.g. MasterChef
     */
    constructor(address _rewardToken, address _chef) public {
        rewardToken = IERC20(_rewardToken);
        chef = _chef;
    }

    /**
     * @dev Initialises settings here
     * @param _distributor  e.g. ExtraRewardsStash
     * @param _pid          e.g. Pid of the pool for `dummyToken` in the chef
     * @param dummyToken    e.g. This token is used to siphon 100% of the rewards from the chef
     */
    function init(address _distributor, uint256 _pid, IERC20 dummyToken) external {
        require(!isInit,"already init");
        isInit = true;
        distributor = _distributor;
        pid = _pid;

        uint256 balance = dummyToken.balanceOf(msg.sender);
        require(balance != 0, "Balance must exceed 0");
        dummyToken.safeTransferFrom(msg.sender, address(this), balance);
        dummyToken.approve(chef, balance);
        IChef(chef).deposit(pid, balance);
    }
    

    /**
     * @notice Hook called by the stash
     * @dev    Claims from the Chef and then transfers the balance back to the Stash for redistribution
     */
    function onRewardClaim() override external {
        require(msg.sender == distributor,"!auth");

        IChef(chef).claim(pid,address(this));

        uint256 bal = rewardToken.balanceOf(address(this));
        if(bal > 0){
            rewardToken.safeTransfer(distributor,bal);
        }
    }

}