// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Interfaces.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-0.6/math/SafeMath.sol";

/**
 * @title   PoolManagerShutdownProxy
 * @author  ConvexFinance
 * @notice  Basically a PoolManager to has a better shutdown and calls addPool on PoolManagerProxy 
 *          Immutable pool manager proxy to enforce that when a  pool is shutdown, the proper number
 *          of lp tokens are returned to the booster contract for withdrawal
 */
contract PoolManagerShutdownProxy{
    using SafeMath for uint256;

    address public immutable pools;
    address public immutable booster;
    address public owner;
    address public operator;

    constructor(
      address _pools,
      address _booster,
      address _owner,
      address _operator
    ) public {
        pools = _pools;
        booster = _booster;
        owner = _owner; 
        operator = msg.sender;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "!owner");
        _;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "!op");
        _;
    }

    //set owner - only OWNER
    function setOwner(address _owner) external onlyOwner{
        owner = _owner;
    }

    //set operator - only OWNER
    function setOperator(address _operator) external onlyOwner{
        operator = _operator;
    }

    /**
     * @notice  Shutdown a pool - only OPERATOR
     * @dev     Shutdowns a pool and ensures all the LP tokens are properly
     *          withdrawn to the Booster contract 
     */
    function shutdownPool(uint256 _pid) external onlyOperator returns(bool){
        //get pool info
        (address lptoken, address depositToken,,,,bool isshutdown) = IPools(booster).poolInfo(_pid);
        require(!isshutdown, "already shutdown");

        //shutdown pool and get before and after amounts
        uint256 beforeBalance = IERC20(lptoken).balanceOf(booster);
        IPools(pools).shutdownPool(_pid);
        uint256 afterBalance = IERC20(lptoken).balanceOf(booster);

        //check that proper amount of tokens were withdrawn(will also fail if already shutdown)
        require( afterBalance.sub(beforeBalance) >= IERC20(depositToken).totalSupply(), "supply mismatch");

        return true;
    }

    //add a new pool - only OPERATOR
    function addPool(address _lptoken, address _gauge, uint256 _stashVersion) external onlyOperator returns(bool){
        return IPools(pools).addPool(_lptoken,_gauge,_stashVersion);
    }
}
