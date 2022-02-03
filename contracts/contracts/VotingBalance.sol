// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;


import "./interfaces/ILockedCvx.sol";
import "@openzeppelin/contracts-0.6/utils/Address.sol";
import "@openzeppelin/contracts-0.6/access/Ownable.sol";

/**
 * @notice  Retrieve a users voting balance based on their amount of locked CVX
 * @dev     Calls CvxLocker contract to get locked balance for a user
 */
contract VotingBalance is Ownable{
    using Address for address;

    address public immutable locker;

    mapping(address => bool) blockList;
    mapping(address => bool) allowedList;
    bool public useBlock = true;
    bool public useAllow = false;

    event changeBlock(address indexed _account, bool _state);
    event changeAllow(address indexed _account, bool _state);

    /**
     * @param _locker CvxLocker contract address
     */
    constructor(address _locker) public {
        locker = _locker;
    }

    /**
     * @notice  Set if the contract should use the blocklist
     * @dev     Only callable by contract owner
     * @param _b Block boolean
     */
    function setUseBlock(bool _b) external onlyOwner{
        useBlock = _b;
    }

    /**
     * @notice  Set if the contract should use the allowlist 
     * @dev     Only callable by contract owner
     * @param _a Allow boolean
     */
    function setUseAllow(bool _a) external onlyOwner{
        useAllow = _a;
    }
  
    /**
     * @notice  Add account to the block list
     * @dev     Only callable by contract owner
     * @param _account Address to add to blocklist
     * @param _block   Block boolean
     */
    function setAccountBlock(address _account, bool _block) external onlyOwner{
        blockList[_account] = _block;
        emit changeBlock(_account, _block);
    }

    /**
     * @notice  Add account to the allow list 
     * @dev     Only callable by contract owner
     * @param _account Address to add to allow list 
     * @param _allowed Allow boolean
     */
    function setAccountAllow(address _account, bool _allowed) external onlyOwner{
        allowedList[_account] = _allowed;
        emit changeAllow(_account, _allowed);
    }

    /**
     * @notice  Get the voting balance of an address
     * @dev     Looks up locked CVX balance of address from CvxLocker
     * @param _account Address to lookup balance of
     */
    function balanceOf(address _account) external view returns(uint256){
        if(useBlock){
            if(blockList[_account]){
                return 0;
            }
        }

        if(useAllow){
            if(Address.isContract(_account) && !allowedList[_account]){
                return 0;
            }
        }

        return ILockedCvx(locker).balanceOf(_account);
    }

    function totalSupply() view external returns(uint256){
        return ILockedCvx(locker).totalSupply();
    }
}
