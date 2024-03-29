// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Interfaces.sol";
import "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-0.6/utils/Address.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-0.6/utils/ReentrancyGuard.sol";

interface ICoordinator {
    function queueNewRewards(
        address,
        uint256,
        uint256,
        address
    ) external payable;
}

/**
 * @title   BoosterLite
 * @author  ConvexFinance -> AuraFinance
 * @dev     A lite version of the original Booster for use on sidechains
 */
contract BoosterLite is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public crv;

    uint256 public lockIncentive = 825; //incentive to crv stakers
    uint256 public stakerIncentive = 825; //incentive to native token stakers
    uint256 public earmarkIncentive = 50; //incentive to users who spend gas to make calls
    uint256 public platformFee = 0; //possible fee to build treasury
    uint256 public constant MaxFees = 4000;
    uint256 public constant FEE_DENOMINATOR = 10000;

    address public owner;
    address public feeManager;
    address public poolManager;
    address public immutable staker;
    address public minter;
    address public rewardFactory;
    address public stashFactory;
    address public tokenFactory;
    address public treasury;
    address public rewards; //cvxCrv rewards(crv)
    bool public isShutdown;

    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards;
        address stash;
        bool shutdown;
    }

    //index(pid) -> pool
    PoolInfo[] public poolInfo;
    mapping(address => bool) public gaugeMap;

    event Deposited(address indexed user, uint256 indexed poolid, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed poolid, uint256 amount);

    event PoolAdded(address lpToken, address gauge, address token, address rewardPool, address stash, uint256 pid);
    event PoolShutdown(uint256 poolId);

    event OwnerUpdated(address newOwner);
    event FeeManagerUpdated(address newFeeManager);
    event PoolManagerUpdated(address newPoolManager);
    event FactoriesUpdated(address rewardFactory, address stashFactory, address tokenFactory);
    event RewardContractsUpdated(address rewards);
    event FeesUpdated(uint256 lockIncentive, uint256 stakerIncentive, uint256 earmarkIncentive, uint256 platformFee);
    event TreasuryUpdated(address newTreasury);

    /**
     * @dev Constructor doing what constructors do. It is noteworthy that
     *      a lot of basic config is set to 0 - expecting subsequent calls setFeeManager etc.
     * @param _staker          VoterProxyLite (locks the crv and adds to all gauges)
     */
    constructor(address _staker) public {
        staker = _staker;
        isShutdown = false;

        owner = msg.sender;
        treasury = address(0);

        emit OwnerUpdated(msg.sender);
    }

    /**
     * @notice Initialize the contract.
     * @param _minter           CVX token, or the thing that mints it
     * @param _crv              CRV Token address
     * @param _owner            Owner address
     */

    function initialize(
        address _minter,
        address _crv,
        address _owner
    ) external {
        require(msg.sender == owner, "!auth");
        require(crv == address(0), "Only once");
        minter = _minter;
        crv = _crv;
        owner = _owner;
        feeManager = _owner;
        poolManager = _owner;

        emit OwnerUpdated(msg.sender);
        emit FeeManagerUpdated(msg.sender);
        emit PoolManagerUpdated(msg.sender);
    }

    /// SETTER SECTION ///

    /**
     * @notice Owner is responsible for setting initial config, updating vote delegate and shutting system
     */
    function setOwner(address _owner) external {
        require(msg.sender == owner, "!auth");
        owner = _owner;

        emit OwnerUpdated(_owner);
    }

    /**
     * @notice Fee Manager can update the fees (lockIncentive, stakeIncentive, earmarkIncentive, platformFee)
     */
    function setFeeManager(address _feeM) external {
        require(msg.sender == owner, "!auth");
        feeManager = _feeM;

        emit FeeManagerUpdated(_feeM);
    }

    /**
     * @notice Pool manager is responsible for adding new pools
     */
    function setPoolManager(address _poolM) external {
        require(msg.sender == poolManager, "!auth");
        poolManager = _poolM;

        emit PoolManagerUpdated(_poolM);
    }

    /**
     * @notice Factories are used when deploying new pools. Only the stash factory is mutable after init
     */
    function setFactories(
        address _rfactory,
        address _sfactory,
        address _tfactory
    ) external {
        require(msg.sender == owner, "!auth");

        //stash factory should be considered more safe to change
        //updating may be required to handle new types of gauges
        stashFactory = _sfactory;

        //reward factory only allow this to be called once even if owner
        //removes ability to inject malicious staking contracts
        //token factory can also be immutable
        if (rewardFactory == address(0)) {
            rewardFactory = _rfactory;
            tokenFactory = _tfactory;

            emit FactoriesUpdated(_rfactory, _sfactory, _tfactory);
        } else {
            emit FactoriesUpdated(address(0), _sfactory, address(0));
        }
    }

    /**
     * @notice Only called once, to set the addresses of cvxCrv (rewards)
     */
    function setRewardContracts(address _rewards) external {
        require(msg.sender == owner, "!auth");

        //reward contracts are immutable or else the owner
        //has a means to redeploy and mint cvx via rewardClaimed()
        if (rewards == address(0)) {
            rewards = _rewards;
            emit RewardContractsUpdated(_rewards);
        }
    }

    /**
     * @notice Fee manager can set all the relevant fees
     * @param _lockFees     % for cvxCrv stakers where 1% == 100
     * @param _stakerFees   % for CVX stakers where 1% == 100
     * @param _callerFees   % for whoever calls the claim where 1% == 100
     * @param _platform     % for "treasury" or vlCVX where 1% == 100
     */
    function setFees(
        uint256 _lockFees,
        uint256 _stakerFees,
        uint256 _callerFees,
        uint256 _platform
    ) external nonReentrant {
        require(msg.sender == feeManager, "!auth");

        uint256 total = _lockFees.add(_stakerFees).add(_callerFees).add(_platform);
        require(total <= MaxFees, ">MaxFees");

        require(_lockFees >= 300 && _lockFees <= 3500, "!lockFees");
        require(_stakerFees >= 300 && _stakerFees <= 1500, "!stakerFees");
        require(_callerFees >= 10 && _callerFees <= 100, "!callerFees");
        require(_platform <= 200, "!platform");

        lockIncentive = _lockFees;
        stakerIncentive = _stakerFees;
        earmarkIncentive = _callerFees;
        platformFee = _platform;

        emit FeesUpdated(_lockFees, _stakerFees, _callerFees, _platform);
    }

    /**
     * @notice Set the address of the treasury (i.e. vlCVX)
     */
    function setTreasury(address _treasury) external {
        require(msg.sender == feeManager, "!auth");
        treasury = _treasury;

        emit TreasuryUpdated(_treasury);
    }

    /// END SETTER SECTION ///

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @notice Called by the PoolManager (i.e. PoolManagerProxy) to add a new pool - creates all the required
     *         contracts (DepositToken, RewardPool, Stash) and then adds to the list!
     */
    function addPool(
        address _lptoken,
        address _gauge,
        uint256 _stashVersion
    ) external returns (bool) {
        require(msg.sender == poolManager && !isShutdown, "!add");
        require(_gauge != address(0) && _lptoken != address(0), "!param");

        //the next pool's pid
        uint256 pid = poolInfo.length;

        //create a tokenized deposit
        address token = ITokenFactory(tokenFactory).CreateDepositToken(_lptoken);
        //create a reward contract for crv rewards
        address newRewardPool = IRewardFactory(rewardFactory).CreateCrvRewards(pid, token, _lptoken);
        //create a stash to handle extra incentives
        address stash = IStashFactory(stashFactory).CreateStash(pid, _gauge, staker, _stashVersion);

        //add the new pool
        poolInfo.push(
            PoolInfo({
                lptoken: _lptoken,
                token: token,
                gauge: _gauge,
                crvRewards: newRewardPool,
                stash: stash,
                shutdown: false
            })
        );
        gaugeMap[_gauge] = true;
        //give stashes access to rewardfactory and voteproxy
        //   voteproxy so it can grab the incentive tokens off the contract after claiming rewards
        //   reward factory so that stashes can make new extra reward contracts if a new incentive is added to the gauge
        if (stash != address(0)) {
            poolInfo[pid].stash = stash;
            IStaker(staker).setStashAccess(stash, true);
            IRewardFactory(rewardFactory).setAccess(stash, true);
        }

        emit PoolAdded(_lptoken, _gauge, token, newRewardPool, stash, pid);
        return true;
    }

    /**
     * @notice Shuts down the pool by withdrawing everything from the gauge to here (can later be
     *         claimed from depositors by using the withdraw fn) and marking it as shut down
     */
    function shutdownPool(uint256 _pid) external nonReentrant returns (bool) {
        require(msg.sender == poolManager, "!auth");
        PoolInfo storage pool = poolInfo[_pid];

        //withdraw from gauge
        try IStaker(staker).withdrawAll(pool.lptoken, pool.gauge) {} catch {}

        pool.shutdown = true;
        gaugeMap[pool.gauge] = false;

        emit PoolShutdown(_pid);
        return true;
    }

    /**
     * @notice Shuts down the WHOLE SYSTEM by withdrawing all the LP tokens to here and then allowing
     *         for subsequent withdrawal by any depositors.
     */
    function shutdownSystem() external {
        require(msg.sender == owner, "!auth");
        isShutdown = true;

        for (uint256 i = 0; i < poolInfo.length; i++) {
            PoolInfo storage pool = poolInfo[i];
            if (pool.shutdown) continue;

            address token = pool.lptoken;
            address gauge = pool.gauge;

            //withdraw from gauge
            try IStaker(staker).withdrawAll(token, gauge) {
                pool.shutdown = true;
            } catch {}
        }
    }

    /**
     * @notice  Deposits an "_amount" to a given gauge (specified by _pid), mints a `DepositToken`
     *          and subsequently stakes that on Convex BaseRewardPool
     */
    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _stake
    ) public nonReentrant returns (bool) {
        require(!isShutdown, "shutdown");
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.shutdown == false, "pool is closed");

        //send to proxy to stake
        address lptoken = pool.lptoken;
        IERC20(lptoken).safeTransferFrom(msg.sender, staker, _amount);

        //stake
        address gauge = pool.gauge;
        require(gauge != address(0), "!gauge setting");
        IStaker(staker).deposit(lptoken, gauge);

        //some gauges claim rewards when depositing, stash them in a seperate contract until next claim
        address stash = pool.stash;
        if (stash != address(0)) {
            IStash(stash).stashRewards();
        }

        address token = pool.token;
        if (_stake) {
            //mint here and send to rewards on user behalf
            ITokenMinter(token).mint(address(this), _amount);
            address rewardContract = pool.crvRewards;
            IERC20(token).safeApprove(rewardContract, 0);
            IERC20(token).safeApprove(rewardContract, _amount);
            IRewards(rewardContract).stakeFor(msg.sender, _amount);
        } else {
            //add user balance directly
            ITokenMinter(token).mint(msg.sender, _amount);
        }

        emit Deposited(msg.sender, _pid, _amount);
        return true;
    }

    /**
     * @notice  Deposits all a senders balance to a given gauge (specified by _pid), mints a `DepositToken`
     *          and subsequently stakes that on Convex BaseRewardPool
     */
    function depositAll(uint256 _pid, bool _stake) external returns (bool) {
        address lptoken = poolInfo[_pid].lptoken;
        uint256 balance = IERC20(lptoken).balanceOf(msg.sender);
        deposit(_pid, balance, _stake);
        return true;
    }

    /**
     * @notice  Withdraws LP tokens from a given PID (& user).
     *          1. Burn the cvxLP balance from "_from" (implicit balance check)
     *          2. If pool !shutdown.. withdraw from gauge
     *          3. If stash, stash rewards
     *          4. Transfer out the LP tokens
     */
    function _withdraw(
        uint256 _pid,
        uint256 _amount,
        address _from,
        address _to
    ) internal nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        address lptoken = pool.lptoken;
        address gauge = pool.gauge;

        //remove lp balance
        address token = pool.token;
        ITokenMinter(token).burn(_from, _amount);

        //pull from gauge if not shutdown
        // if shutdown tokens will be in this contract
        if (!pool.shutdown) {
            IStaker(staker).withdraw(lptoken, gauge, _amount);
        }

        //some gauges claim rewards when withdrawing, stash them in a seperate contract until next claim
        //do not call if shutdown since stashes wont have access
        address stash = pool.stash;
        if (stash != address(0) && !isShutdown && !pool.shutdown) {
            IStash(stash).stashRewards();
        }

        //return lp tokens
        IERC20(lptoken).safeTransfer(_to, _amount);

        emit Withdrawn(_to, _pid, _amount);
    }

    /**
     * @notice  Withdraw a given amount from a pool (must already been unstaked from the Convex Reward Pool -
     *          BaseRewardPool uses withdrawAndUnwrap to get around this)
     */
    function withdraw(uint256 _pid, uint256 _amount) public returns (bool) {
        _withdraw(_pid, _amount, msg.sender, msg.sender);
        return true;
    }

    /**
     * @notice  Withdraw all the senders LP tokens from a given gauge
     */
    function withdrawAll(uint256 _pid) public returns (bool) {
        address token = poolInfo[_pid].token;
        uint256 userBal = IERC20(token).balanceOf(msg.sender);
        withdraw(_pid, userBal);
        return true;
    }

    /**
     * @notice Allows the actual BaseRewardPool to withdraw and send directly to the user
     */
    function withdrawTo(
        uint256 _pid,
        uint256 _amount,
        address _to
    ) external returns (bool) {
        address rewardContract = poolInfo[_pid].crvRewards;
        require(msg.sender == rewardContract, "!auth");

        _withdraw(_pid, _amount, msg.sender, _to);
        return true;
    }

    /**
     * @notice Allows a stash to claim secondary rewards from a gauge
     */
    function claimRewards(uint256 _pid, address _gauge) external returns (bool) {
        address stash = poolInfo[_pid].stash;
        require(msg.sender == stash, "!auth");

        IStaker(staker).claimRewards(_gauge);
        return true;
    }

    /**
     * @notice Tells the Curve gauge to redirect any accrued rewards to the given stash via the VoterProxy
     */
    function setGaugeRedirect(uint256 _pid) external returns (bool) {
        address stash = poolInfo[_pid].stash;
        require(msg.sender == stash, "!auth");
        address gauge = poolInfo[_pid].gauge;
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("set_rewards_receiver(address)")), stash);
        IStaker(staker).execute(gauge, uint256(0), data);
        return true;
    }

    /**
     * @notice Basically a hugely pivotal function.
     *         Responsible for collecting the crv from gauge, and then redistributing to the correct place.
     *         Pays the caller a fee to process this.
     */
    function _earmarkRewards(uint256 _pid, address _zroPaymentAddress) internal {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.shutdown == false, "pool is closed");

        uint256 crvBal;
        {
            // If there is idle CRV in the Booster we need to transfer it out
            // in order that our accounting doesn't get scewed.
            uint256 crvBBalBefore = IERC20(crv).balanceOf(address(this));
            uint256 crvVBalBefore = IERC20(crv).balanceOf(staker);
            uint256 crvBalBefore = crvBBalBefore.add(crvVBalBefore);

            //claim crv
            IStaker(staker).claimCrv(pool.gauge);

            //crv balance
            uint256 crvBalAfter = IERC20(crv).balanceOf(address(this));
            crvBal = crvBalAfter.sub(crvBalBefore);

            if (crvBalBefore > 0 && treasury != address(0)) {
                IERC20(crv).safeTransfer(treasury, crvBalBefore);
            }
        }

        //check if there are extra rewards
        address stash = pool.stash;
        if (stash != address(0)) {
            //claim extra rewards
            IStash(stash).claimRewards();
            //process extra rewards
            IStash(stash).processStash();
        }

        if (crvBal > 0) {
            // LockIncentive = cvxCrv stakers
            uint256 _lockIncentive = crvBal.mul(lockIncentive).div(FEE_DENOMINATOR);
            // StakerIncentive = cvx stakers
            uint256 _stakerIncentive = crvBal.mul(stakerIncentive).div(FEE_DENOMINATOR);
            // CallIncentive = caller of this contract
            uint256 _callIncentive = crvBal.mul(earmarkIncentive).div(FEE_DENOMINATOR);
            // Platform incentives
            uint256 _platformIncentive = crvBal.mul(platformFee).div(FEE_DENOMINATOR);

            uint256 _totalIncentive = _lockIncentive.add(_stakerIncentive).add(_platformIncentive);

            //remove incentives from balance
            crvBal = crvBal.sub(_totalIncentive).sub(_callIncentive);

            //send incentives for calling
            IERC20(crv).safeTransfer(msg.sender, _callIncentive);

            //send crv to lp provider reward contract
            address rewardContract = pool.crvRewards;
            IERC20(crv).safeTransfer(rewardContract, crvBal);
            IRewards(rewardContract).queueNewRewards(crvBal);

            //send lockers' share of crv to reward contract
            IERC20(crv).safeTransfer(rewards, _totalIncentive);
            ICoordinator(rewards).queueNewRewards{ value: msg.value }(
                msg.sender,
                _totalIncentive,
                crvBal,
                _zroPaymentAddress
            );
        }
    }

    /**
     * @notice Basically a hugely pivotal function.
     *         Responsible for collecting the crv from gauge, and then redistributing to the correct place.
     *         Pays the caller a fee to process this.
     */
    function earmarkRewards(uint256 _pid, address _zroPaymentAddress) external payable nonReentrant returns (bool) {
        require(!isShutdown, "shutdown");
        _earmarkRewards(_pid, _zroPaymentAddress);
        return true;
    }

    /**
     * @notice Callback from reward contract when crv is received.
     * @dev    Goes off and mints a relative amount of `CVX` based on the distribution schedule.
     */
    function rewardClaimed(
        uint256 _pid,
        address _address,
        uint256 _amount
    ) external returns (bool) {
        address rewardContract = poolInfo[_pid].crvRewards;
        require(msg.sender == rewardContract, "!auth");

        if (_amount > 0) {
            //mint reward tokens
            ITokenMinter(minter).mint(_address, _amount);
        }

        return true;
    }
}
