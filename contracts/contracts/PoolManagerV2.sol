// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Interfaces.sol";
import "./interfaces/IGaugeController.sol";
import "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-0.6/utils/Address.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";

/**
 * @title   PoolManagerV2
 * @author  ConvexFinance
 * @notice  Add pool to Booster. Same as PoolManager with the following change:
 *          - Check validity of a gauge and token by going through the gauge controller instead of curve's registry
 */
contract PoolManagerV2{
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public operator;
    address public immutable pools;
    address public immutable gaugeController;
  
    /**
     * @param _pools            Contract to call addPool on e.g Boost
     * @param _gaugeController  Curve gauge controller e.g 0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB
     */
    constructor(address _pools, address _gaugeController) public {
        operator = msg.sender;
        pools = _pools;
        gaugeController = _gaugeController;
    }

    function setOperator(address _operator) external {
        require(msg.sender == operator, "!auth");
        operator = _operator;
    }

    //revert control of adding  pools back to operator
    function revertControl() external{
        require(msg.sender == operator, "!auth");
        IPools(pools).setPoolManager(operator);
    }

    /**
     * @notice  Add a new curve pool to the system.
     * @dev     This function is callable by anyone. The gauge must be on curve's registry. 
     * @param _gauge          Gauge contract
     * @param _stashVersion   ExtraRewardStash version
     */
    function addPool(address _gauge, uint256 _stashVersion) external returns(bool){
        require(_gauge != address(0),"gauge is 0");

        uint256 weight = IGaugeController(gaugeController).get_gauge_weight(_gauge);
        require(weight > 0, "must have weight");

        bool gaugeExists = IPools(pools).gaugeMap(_gauge);
        require(!gaugeExists, "already registered");

        address lptoken = ICurveGauge(_gauge).lp_token();
        require(lptoken != address(0),"no token");
        
        IPools(pools).addPool(lptoken,_gauge,_stashVersion);

        return true;
    }

    function shutdownPool(uint256 _pid) external returns(bool){
        require(msg.sender==operator, "!auth");

        IPools(pools).shutdownPool(_pid);
        return true;
    }

}
