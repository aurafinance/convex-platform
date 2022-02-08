// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./interfaces/ILockedCvx.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";

/** 
 * @title   LockerAdmin
 * @author  ConvexFinance
 * @notice  Admin proxy for locker contract to fix require checks and seal off staking proxy changes
 */
contract LockerAdmin{

    ILockedCvx public immutable locker; 
    address public operator;
  
    /**
     * @param _locker   CvxLocker contract
     * @param _operator Operator e.g multisig (0xa3C5A1e09150B75ff251c1a7815A07182c3de2FB0
     */
    constructor(ILockedCvx _locker, address _operator) public {
        locker = _locker;
        operator = _operator;
    }

    modifier onlyOwner() {
        require(operator == msg.sender, "!auth");
        _;
    }

    function setOperator(address _operator) external onlyOwner{
        operator = _operator;
    }


    function addReward(
        address _rewardsToken,
        address _distributor,
        bool _useBoost
    ) external onlyOwner{
        locker.addReward(_rewardsToken, _distributor, _useBoost);
    }

    function approveRewardDistributor(
        address _rewardsToken,
        address _distributor,
        bool _approved
    ) external onlyOwner{
        locker.approveRewardDistributor(_rewardsToken, _distributor, _approved);
    }

    //seal setStakingContract off, make it immutable
    // function setStakingContract(address _staking) external onlyOwner{
    //     locker.setStakingContract(_staking);
    // }

    function setStakeLimits(uint256 _minimum, uint256 _maximum) external onlyOwner {
        require(_minimum <= _maximum, "min range");
        locker.setStakeLimits(_minimum, _maximum);
    }

    function setBoost(uint256 _max, uint256 _rate, address _receivingAddress) external onlyOwner {
        require(_max < 1500, "over max payment"); //max 15%
        require(_rate < 30000, "over max rate"); //max 3x
        locker.setBoost(_max, _rate, _receivingAddress);
    }

    function setKickIncentive(uint256 _rate, uint256 _delay) external onlyOwner {
        locker.setKickIncentive(_rate, _delay);
    }

    function shutdown() external onlyOwner {
        locker.shutdown();
    }

    function recoverERC20(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        locker.recoverERC20(_tokenAddress, _tokenAmount);
        transferToken(_tokenAddress, _tokenAmount);
    }

    function transferToken(address _tokenAddress, uint256 _tokenAmount) public onlyOwner {
        IERC20(_tokenAddress).transfer(operator, _tokenAmount);
    }
}
