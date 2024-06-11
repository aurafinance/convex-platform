// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Interfaces.sol";

/**
 * @title   PoolFeeManagerProxy
 * @author  AuraFinance
 * @notice  Wraps PoolManagerV4 and Booster Fee Manager capabilites
 *           It allows to add pools and set their reward multiplier.
 */
contract PoolFeeManagerProxy {
    address public immutable poolManager;
    address public immutable booster;
    address public operator;

    bool public protectAddPool;

    /// @dev The value must be within the allowed range on Booster contract.
    uint256 public defaultRewardMultiplier;
    /// @dev Same value as Booster.REWARD_MULTIPLIER_DENOMINATOR
    uint256 public constant REWARD_MULTIPLIER_DENOMINATOR = 10000;

    event DefaultRewardMultiplierUpdated(uint256 newRewardMultiplier);

    /**
     * @param _poolManager      Currently PoolManagerV4
     * @param _booster          Booster address
     * @param _operator         Convex multisig
     */
    constructor(
        address _poolManager,
        address _booster,
        address _operator
    ) public {
        poolManager = _poolManager;
        booster = _booster;
        operator = _operator;
        protectAddPool = true;
    }

    //-------------------------------------//
    //---------- PoolManagerV4 ------------//
    //-------------------------------------//
    function setPoolManagerOperator(address _operator) external {
        require(msg.sender == operator, "!auth");
        IPoolManager(poolManager).setOperator(_operator);
    }

    function setOperator(address _operator) external {
        require(msg.sender == operator, "!auth");
        operator = _operator;
    }

    /**
     * @notice set if addPool is only callable by operator
     */
    function setProtectPool(bool _protectAddPool) external {
        require(msg.sender == operator, "!auth");
        protectAddPool = _protectAddPool;
    }

    /**
     * @notice Add a new curve pool to the system. (default stash to v3)
     */
    function addPool(address _gauge) external returns (bool) {
        uint256 pid = IPools(booster).poolLength();
        _addPool(_gauge);
        (, , , address crvRewards, , ) = IPools(booster).poolInfo(pid);
        _setRewardMultiplier(crvRewards, defaultRewardMultiplier);
        return true;
    }

    function _addPool(address _gauge) internal returns (bool) {
        if (protectAddPool) {
            require(msg.sender == operator, "!auth");
        }
        //get lp token from gauge
        return IPoolManager(poolManager).addPool(_gauge);
    }

    function shutdownPool(uint256 _pid) external returns (bool) {
        require(msg.sender == operator, "!auth");

        return IPoolManager(poolManager).shutdownPool(_pid);
    }

    //shutdown pool management and disallow new pools. change is immutable
    function shutdownSystem() external {
        require(msg.sender == operator, "!auth");
        return IPoolManager(poolManager).shutdownSystem();
    }

    //----------------------------------//
    //---------- Fee Manager------------//
    //----------------------------------//
    function _setRewardMultiplier(
        address _rewardContract,
        uint256 multiplier
    ) internal {
        IBoosterFees(booster).setRewardMultiplier(_rewardContract, multiplier);
    }
    function setDefaultRewardMultiplier(uint256 multiplier) external {
        require(msg.sender == operator, "!auth");
        require(multiplier <= REWARD_MULTIPLIER_DENOMINATOR * 2, "too high");

        defaultRewardMultiplier = multiplier;
        emit DefaultRewardMultiplierUpdated(multiplier);
    }

    function setFees(
        uint256 _lockFees,
        uint256 _stakerFees,
        uint256 _callerFees,
        uint256 _platform
    ) external {
        require(msg.sender == operator, "!auth");
        IBoosterFees(booster).setFees(
            _lockFees,
            _stakerFees,
            _callerFees,
            _platform
        );
    }
    function setTreasury(address _treasury) external {
        require(msg.sender == operator, "!auth");
        IBoosterFees(booster).setTreasury(_treasury);
    }
    function setBridgeDelegate(address _bridgeDelegate) external {
        require(msg.sender == operator, "!auth");
        IBoosterFees(booster).setBridgeDelegate(_bridgeDelegate);
    }
    function setRewardMultiplier(
        address _rewardContract,
        uint256 _multiplier
    ) external {
        require(msg.sender == operator, "!auth");
        _setRewardMultiplier(_rewardContract, _multiplier);
    }
}
