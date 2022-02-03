// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;


import "./interfaces/ILockedCvx.sol";
import "./interfaces/IVotingEligibility.sol";
import "@openzeppelin/contracts-0.6/math/SafeMath.sol";

/**
 * @title    VotingBalanceMax
 * @author   ConvexFinance
 * @notice   Retrieve a users voting balance based on their amount of locked CVX
 * @dev      Calls CvxLocker contract to get locked balance for a user
 *           upgrade of the original VotingBalance contract to seperate allow list
 *           and block list and get pending balances
 */
contract VotingBalanceMax{
    using SafeMath for uint256;

    address public immutable locker;
    address public immutable eligiblelist;
    uint256 public constant rewardsDuration = 86400 * 7;
    uint256 public constant lockDuration = rewardsDuration * 17;

    /** 
     * @param _eligiblelist     Address of VotingEligibility contract used for allow list and block list
     * @param _locker           CvxLocker contract address
     */
    constructor(
      address _eligiblelist, 
      address _locker 
    ) public {
        eligiblelist = _eligiblelist;
        locker = _locker;
    }

    /**
     * @notice  Get the voting balance of an address
     * @dev     Looks up locked CVX balance of address from CvxLocker
     * @param _account Address to lookup balance of
     */
    function balanceOf(address _account) external view returns(uint256){

        //check eligibility list
        if(!IVotingEligibility(eligiblelist).isEligible(_account)){
            return 0;
        }

        //compute to find previous epoch
        uint256 currentEpoch = block.timestamp.div(rewardsDuration).mul(rewardsDuration);
        uint256 epochindex = ILockedCvx(locker).epochCount() - 1;
        (, uint32 _enddate) = ILockedCvx(locker).epochs(epochindex);
        if(_enddate >= currentEpoch){
            //if end date is already the current epoch,  minus 1 to get the previous
            epochindex -= 1;
        }
        //get balances of current and previous
        uint256 balanceAtPrev = ILockedCvx(locker).balanceAtEpochOf(epochindex, _account);
        uint256 currentBalance = ILockedCvx(locker).balanceOf(_account);

        //return greater balance
        return max(balanceAtPrev, currentBalance);
    }

    /**
     * @notice  Get the pending voting balance of an address
     * @dev     Calculates the pending balance for the active epoch  
     * @param _account Address to lookup balance of
     */
    function pendingBalanceOf(address _account) external view returns(uint256){

        //check eligibility list
        if(!IVotingEligibility(eligiblelist).isEligible(_account)){
            return 0;
        }

        //determine when current epoch would end
        uint256 currentEpochUnlock = block.timestamp.div(rewardsDuration).mul(rewardsDuration).add(lockDuration);

        //grab account lock list
        (,,,ILockedCvx.LockedBalance[] memory balances) = ILockedCvx(locker).lockedBalances(_account);
        
        //if most recent lock is current epoch, then lock amount is pending balance
        uint256 pending;
        if(balances[balances.length-1].unlockTime == currentEpochUnlock){
            pending = balances[balances.length-1].boosted;
        }

        return pending;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }
  
    function totalSupply() view external returns(uint256){
        return ILockedCvx(locker).totalSupply();
    }
}
