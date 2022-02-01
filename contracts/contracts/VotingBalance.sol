// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;


import "./interfaces/ILockedCvx.sol";
import "@openzeppelin/contracts-0.6/utils/Address.sol";
import "@openzeppelin/contracts-0.6/access/Ownable.sol";

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
     * @notice retrieve a users voting balance based on their amount of locked CVX
     * @dev calls CvxLocker contract to get locked balance for a user
     * @param _locker CvxLocker contract address
     */
    constructor(address _locker) public {
        locker = _locker;
    }

    /**
     * @notice set if the contract should use the blocklist
     * @dev only callable by contract owner
     * @param _b block boolean
     */
    function setUseBlock(bool _b) external onlyOwner{
        useBlock = _b;
    }

    /**
     * @notice set if the contract should use the allowlist 
     * @dev only callable by contract owner
     * @param _a allow boolean
     */
    function setUseAllow(bool _a) external onlyOwner{
        useAllow = _a;
    }
  
    /**
     * @notice add account to the block list
     * @dev only callable by contract owner
     * @param _account address to add to blocklist
     * @param _block   block boolean
     */
    function setAccountBlock(address _account, bool _block) external onlyOwner{
        blockList[_account] = _block;
        emit changeBlock(_account, _block);
    }

    /**
     * @notice add account to the allow list 
     * @dev only callable by contract owner
     * @param _account address to add to allow list 
     * @param _allowed allow boolean
     */
    function setAccountAllow(address _account, bool _allowed) external onlyOwner{
        allowedList[_account] = _allowed;
        emit changeAllow(_account, _allowed);
    }

    /**
     * @notice get the voting balance of an address
     * @dev looks up locked CVX balance of address from CvxLocker
     * @param _account address to lookup balance of
     * @returns balance
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
