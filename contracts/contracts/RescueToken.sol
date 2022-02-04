// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-0.6/utils/Address.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/ERC20.sol";


/**
 * @title   RescueToken
 * @author  ConvexFinance
 * @notice  Dummy token to use for erc20 rescue. A private pool gets added
 *          to the booster that takes this dummy token and facilitates rescuing
 *          tokens from the VoterProxy see ExtraRewardStashTokenRescue for more details
 */
contract RescueToken is ERC20 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /**
     * @param _symbolArg e.g. cvxRT
     */
    constructor(string memory _symbolArg)
        public
        ERC20(
            "Recue Token",
            _symbolArg
        ){
    }
    
    function rewards_receiver(address _address) external view returns(address){
        return _address;
    }

}
