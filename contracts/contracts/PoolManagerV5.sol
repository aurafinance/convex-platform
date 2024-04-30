// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Interfaces.sol";
interface IBoosterFees {
    function setFees(
        uint256 _lockFees,
        uint256 _stakerFees,
        uint256 _callerFees,
        uint256 _platform
    ) external;
    function setTreasury(address _treasury) external;
    function setBridgeDelegate(address _bridgeDelegate) external;
    function setRewardMultiplier(
        address _rewardContract,
        uint256 multiplier
    ) external;
}

/**
 * @title   PoolManagerV5
 * @author  ConvexFinance -> AuraFinance
 * @notice  Pool Manager v5
 *          - Changes: add Fee Manager fns
 */
contract PoolManagerV5 {
    address public immutable pools;
    address public operator;

    bool public protectAddPool;
    uint256 public defaultRewardMultiplier;

    event DefaultRewardMultiplierUpdated(uint256 newRewardMultiplier);
    /**
     * @param _pools            Currently PoolManagerSecondaryProxy
     * @param _operator         Convex multisig
     */
    constructor(address _pools, address _operator) public {
        pools = _pools;
        operator = _operator;
        protectAddPool = true;
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
    function addPool(address _gauge) external virtual returns (bool) {
        uint256 pid = IPools(pools).poolLength();
        (, , , address crvRewards, , ) = IPools(pools).poolInfo(pid);
        _addPool(_gauge, 3);
        _setRewardMultiplier(crvRewards);
        return true;
    }

    function _addPool(address _gauge, uint256 _stashVersion) internal {
        if (protectAddPool) {
            require(msg.sender == operator, "!auth");
        }
        //get lp token from gauge
        address lptoken = ICurveGauge(_gauge).lp_token();

        //gauge/lptoken address checks will happen in the next call
        IPools(pools).addPool(lptoken, _gauge, _stashVersion);
    }

    function shutdownPool(uint256 _pid) external returns (bool) {
        require(msg.sender == operator, "!auth");

        IPools(pools).shutdownPool(_pid);
        return true;
    }

    //shutdown pool management and disallow new pools. change is immutable
    function shutdownSystem() external {
        require(msg.sender == operator, "!auth");
        IPools(pools).shutdownSystem();
    }

    //----------------------------------//
    //---------- Fee Manager------------//
    //----------------------------------//
    function _setRewardMultiplier(address _rewardContract) internal {
        IBoosterFees(pools).setRewardMultiplier(
            _rewardContract,
            defaultRewardMultiplier
        );
    }
    function setDefaultRewardMultiplier(
        uint256 _defaultRewardMultiplier
    ) external {
        require(msg.sender == operator, "!auth");
        defaultRewardMultiplier = _defaultRewardMultiplier;
        emit DefaultRewardMultiplierUpdated(_defaultRewardMultiplier);
    }

    function setFees(
        uint256 _lockFees,
        uint256 _stakerFees,
        uint256 _callerFees,
        uint256 _platform
    ) external {
        require(msg.sender == operator, "!auth");
        IBoosterFees(pools).setFees(
            _lockFees,
            _stakerFees,
            _callerFees,
            _platform
        );
    }
    function setTreasury(address _treasury) external {
        require(msg.sender == operator, "!auth");
        IBoosterFees(pools).setTreasury(_treasury);
    }
    function setBridgeDelegate(address _bridgeDelegate) external {
        require(msg.sender == operator, "!auth");
        IBoosterFees(pools).setBridgeDelegate(_bridgeDelegate);
    }
    function setRewardMultiplier(address _rewardContract) external {
        require(msg.sender == operator, "!auth");
        _setRewardMultiplier(_rewardContract);
    }
}
