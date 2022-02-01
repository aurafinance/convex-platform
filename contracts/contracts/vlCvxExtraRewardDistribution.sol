// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./interfaces/ILockedCvx.sol";
import "./interfaces/BoringMath.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";

/**
 * @title   vlCvxExtraRewardDistribution
 * @author  ConvexFinance
 * @notice  Distribute various rewards to locked cvx holders (vlCVX)
 *          - Rewards added are assigned to the previous epoch (it was the previous epoch lockers who deserve today's rewards)
 *          - As soon as claiming for a token at an epoch is eligibe, no more tokens should be allowed to be added
 *          - To allow multiple txs to add to the same token, rewards added during the current epoch (and assigned to previous) will not
 *            be claimable until the beginning of the next epoch. The "reward assigning phase" must be complete first
 *          example: 
 *          - Current epoch: 10
 *          - During this week all addReward() calls are assigned to users in epoch 9
 *          - Users who were locked in epoch 9 can claim once epoch 11 begins
 *          - epoch 10 is the assigning phase for epoch 9, thus we must wait until 10 is complete before claiming 9
 */
contract vlCvxExtraRewardDistribution {
    using SafeERC20
    for IERC20;
    using BoringMath
    for uint256;

    ILockedCvx public immutable cvxlocker;
    uint256 public immutable rewardsDuration;

    mapping(address => mapping(uint256 => uint256)) public rewardData; // token -> epoch -> amount
    mapping(address => uint256[]) public rewardEpochs; // token -> epochList
    mapping(address => mapping(address => uint256)) public userClaims; //token -> account -> last claimed epoch index

    /**
     * @param _cvxlocker        CvxLocker contract
     * @param _rewardsDuration  epoch duration for rewards
     */
    constructor(ILockedCvx _cvxlocker, uint256 _rewardsDuration) public {
      rewardsDuration = _rewardsDuration;
      cvxlocker = _cvxlocker;
    }


    function rewardEpochsCount(address _token) external view returns(uint256) {
        return rewardEpochs[_token].length;
    }

    /**
     * @notice add reward token to a specific epoch
     * @param _token    reward token address
     * @param _amount   amount of reward tokens to add
     * @param _epoch    which epoch to add to (must be less than the previous epoch)
     */
    function addRewardToEpoch(address _token, uint256 _amount, uint256 _epoch) external {
        //checkpoint locker
        cvxlocker.checkpointEpoch();


        //if adding a reward to a specific epoch, make sure it's
        //a.) an epoch older than the previous epoch (in which case use addReward)
        //b.) more recent than the previous reward
        //this means addRewardToEpoch can only be called *once* for a specific reward for a specific epoch
        //because they will be claimable immediately and amount shouldnt change after claiming begins
        //
        //conversely rewards can be piled up with addReward() because claiming is only available to completed epochs
        require(_epoch < cvxlocker.epochCount() - 2, "!prev epoch");
        uint256 l = rewardEpochs[_token].length;
        require(l == 0 || rewardEpochs[_token][l - 1] < _epoch, "old epoch");

        _addReward(_token, _amount, _epoch);
    }

    /**
     * @notice add a reward to the current epoch. can be called multiple times for the same reward token
     * @param _token    reward token address
     * @param _amount   amount of reward token
     */
    function addReward(address _token, uint256 _amount) external {
        //checkpoint locker
        cvxlocker.checkpointEpoch();

        //assign to previous epoch
        uint256 prevEpoch = cvxlocker.epochCount() - 2;

        _addReward(_token, _amount, prevEpoch);
    }

    /**
     * @notice  transfer reward tokens from sender to contract for vlCVX holders
     * @dev     add reward token for specific epoch
     * @param _token    reward token address
     * @param _amount   amount of reward tokens
     * @param _epoch    epoch to add tokens to
     */
    function _addReward(address _token, uint256 _amount, uint256 _epoch) internal {
        //convert to reward per token
        uint256 supply = cvxlocker.totalSupplyAtEpoch(_epoch);
        uint256 rPerT = _amount.mul(1e20).div(supply);
        rewardData[_token][_epoch] = rewardData[_token][_epoch].add(rPerT);

        //add epoch to list
        uint256 l = rewardEpochs[_token].length;
        if (l == 0 || rewardEpochs[_token][l - 1] < _epoch) {
            rewardEpochs[_token].push(_epoch);
        }

        //pull
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    
        //event
        emit RewardAdded(_token, _epoch, _amount);
    }

    /**
     * @notice get claimable rewards (rewardToken) for vlCVX holder
     */
    function claimableRewards(address _account, address _token) external view returns(uint256) {
        (uint256 rewards,) = _allClaimableRewards(_account, _token);
        return rewards;
    }

    /**
     * @notice get claimable rewards for a token at a specific epoch
     */
    function claimableRewardsAtEpoch(address _account, address _token, uint256 _epoch) external view returns(uint256) {
        return _claimableRewards(_account, _token, _epoch);
    }

    /**
     * @notice  get all claimable rewards by looping through each epoch starting with the latest
     *          saved epoch the user last claimed from
     * @param _account  address of vlCVX holder
     * @param _token    reward token
     */
    function _allClaimableRewards(address _account, address _token) internal view returns(uint256,uint256) {
        uint256 epochIndex = userClaims[_token][_account];
        uint256 prevEpoch = cvxlocker.epochCount() - 2;
        uint256 claimableTokens = 0;
        for (uint256 i = epochIndex; i < rewardEpochs[_token].length; i++) {
            //only claimable after rewards are "locked in"
            if (rewardEpochs[_token][i] < prevEpoch) {
                claimableTokens = claimableTokens.add(_claimableRewards(_account, _token, rewardEpochs[_token][i]));
                //return index user claims should be set to
                epochIndex = i+1;
            }
        }
        return (claimableTokens, epochIndex);
    }

    //get claimable rewards for a token at a specific epoch
    function _claimableRewards(address _account, address _token, uint256 _epoch) internal view returns(uint256) {
        //get balance and calc share
        uint256 balance = cvxlocker.balanceAtEpochOf(_epoch, _account);
        return balance.mul(rewardData[_token][_epoch]).div(1e20);
    }

    /**
     * @notice claim rewards for a specific token at a specific epoch
     */
    function getReward(address _account, address _token) public {
        //get claimable tokens
        (uint256 claimableTokens, uint256 index) = _allClaimableRewards(_account, _token);

        if (claimableTokens > 0) {
            //set claim checkpoint
            userClaims[_token][_account] = index;

            //send
            IERC20(_token).safeTransfer(_account, claimableTokens);

            //event
            emit RewardPaid(_account, _token, claimableTokens);
        }
    }

    //claim multiple tokens
    function getRewards(address _account, address[] calldata _tokens) external {
        for(uint i = 0; i < _tokens.length; i++){
            getReward(_account, _tokens[i]);
        }
    }

    /**
     * @notice  allow a user to set their claimed index forward without claiming rewards
     *          Because claims cycle through all periods that a specific reward was given
     *          there becomes a situation where, for example, a new user could lock
     *          2 years from now and try to claim a token that was given out every week prior.
     *          This would result in a 2mil gas checkpoint.(about 20k gas * 52 weeks * 2 years)
     * @param _token  reward token to forfeit
     * @param _index  epoch index to forfeit from
     */
    function forfeitRewards(address _token, uint256 _index) external {
        require(_index > 0 && _index < rewardEpochs[_token].length-1, "!past");
        require(_index >= userClaims[_token][msg.sender], "already claimed");

        //set claim checkpoint. next claim starts from index+1
        userClaims[_token][msg.sender] = _index + 1;

        emit RewardForfeited(msg.sender, _token, _index);
    }


    /* ========== EVENTS ========== */
    event RewardAdded(address indexed _token, uint256 indexed _epoch, uint256 _reward);
    event RewardPaid(address indexed _user, address indexed _rewardsToken, uint256 _reward);
    event RewardForfeited(address indexed _user, address indexed _rewardsToken, uint256 _index);
}
