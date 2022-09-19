// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Interfaces.sol";
import "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";

/**
 * @title   PoolManagerLite
 * @author  ConvexFinance
 * @notice  Pool Manager Lite
 * @dev     Add pools to the Booster contract
 */
contract PoolManagerLite {
    using SafeMath for uint256;

    address public immutable booster;
    address public operator;
    bool public protectAddPool;

    constructor(address _booster, address _operator) public {
        booster = _booster;
        operator = _operator;
        protectAddPool = true;
    }

    function setOperator(address _operator) external {
        require(msg.sender == operator, "!auth");
        operator = _operator;
    }

    function setProtectPool(bool _protectAddPool) external {
        require(msg.sender == operator, "!auth");
        protectAddPool = _protectAddPool;
    }

    function addPool(address _gauge) external returns (bool) {
        return _addPool(_gauge, 3);
    }

    function addPool(address _gauge, uint256 _stashVersion) external returns (bool) {
        return _addPool(_gauge, _stashVersion);
    }

    function _addPool(address _gauge, uint256 _stashVersion) public returns (bool) {
        require(!IPools(booster).gaugeMap(_gauge), "already registered gauge");

        if (protectAddPool) {
            require(msg.sender == operator, "!auth");
        }

        address lptoken = ICurveGauge(_gauge).lp_token();
        require(!IPools(booster).gaugeMap(lptoken), "already registered lptoken");

        return IPools(booster).addPool(lptoken, _gauge, _stashVersion);
    }

    function shutdownPool(uint256 _pid) external returns (bool) {
        // get pool info
        (address lptoken, address depositToken, , , , bool isshutdown) = IPools(booster).poolInfo(_pid);
        require(!isshutdown, "already shutdown");

        // shutdown pool and get before and after amounts
        uint256 beforeBalance = IERC20(lptoken).balanceOf(booster);
        IPools(booster).shutdownPool(_pid);
        uint256 afterBalance = IERC20(lptoken).balanceOf(booster);

        // check that proper amount of tokens were withdrawn(will also fail if already shutdown)
        require(afterBalance.sub(beforeBalance) >= IERC20(depositToken).totalSupply(), "supply mismatch");

        return true;
    }
}
