// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./interfaces/IBooster.sol";
import "@openzeppelin/contracts-0.6/math/SafeMath.sol";

/**
 * @title   VoteDelegateExtension
 * @author  ConvexFinance
 * @notice  Add a layer to voting to easily apply data packing into vote id, as well as simplify calling functions
 * @dev     Wraps the Convex -> Curve voting process and applies some shared addresses, methods and helper fns for
 *          relaying the result of a Convex snapshot proposal to the Curve DAO.
 */
contract VoteDelegateExtension{
    using SafeMath for uint256;

    address public immutable voteOwnership;
    address public immutable voteParameter;
    address public immutable booster;

    uint256 private constant MAX_UINT_128  = (2**128) - 1;
    uint256 private constant MAX_UINT_64  = (2**64) - 1;
    uint256 private constant MAX_VOTE = 1e18;

    address public owner;
    address public daoOperator;
    address public gaugeOperator;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @param _owner         e.g. 0xa3C5A1e09150B75ff251c1a7815A07182c3de2FB
     * @param _daoOperator   e.g. 0xa3C5A1e09150B75ff251c1a7815A07182c3de2FB
     * @param _gaugeOperator e.g. 0xa3C5A1e09150B75ff251c1a7815A07182c3de2FB
     * @param _voteOwnership e.g. 0xE478de485ad2fe566d49342Cbd03E49ed7DB3356
     * @param _voteParameter  e.g. 0xBCfF8B0b9419b9A88c44546519b1e909cF330399
     * @param _booster       e.g. 0xF403C135812408BFbE8713b5A23a04b3D48AAE31
     */
    constructor(
        address _owner,
        address _daoOperator,
        address _gaugeOperator,
        address _voteOwnership,
        address _voteParameter,
        address _booster
    ) public {
        owner = _owner;
        daoOperator = _daoOperator;
        gaugeOperator = _gaugeOperator;
        voteOwnership = _voteOwnership;
        voteParameter = _voteParameter;
        booster = _booster;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "!owner");
        _;
    }

    modifier onlyDaoOperator() {
        require(daoOperator == msg.sender, "!dop");
        _;
    }

    modifier onlyGaugeOperator() {
        require(gaugeOperator == msg.sender, "!gop");
        _;
    }

    //set owner - only OWNER
    function setOwner(address _owner) external onlyOwner{
        owner = _owner;
    }

    //set operator - only OWNER
    function setDaoOperator(address _operator) external onlyOwner{
        daoOperator = _operator;
    }

    function setGaugeOperator(address _operator) external onlyOwner{
        gaugeOperator = _operator;
    }

    //revert to booster's owner
    function revertControl() external onlyOwner{
        IBooster(booster).setVoteDelegate(IBooster(booster).owner());
    }

    //pack data by shifting and ORing
    function _encodeData(uint256 _value, uint256 _shiftValue, uint256 _base) internal pure returns(uint256) {
        return uint256((_value << _shiftValue) | _base);
    }

    function packData(uint256 _voteId, uint256 _yay, uint256 _nay) public pure returns(uint256){
        uint256 pack = _encodeData(_yay, 192, 0);
        pack = _encodeData(_nay,128,pack);
        pack = _encodeData(_voteId, 0, pack);
        return pack;
    }

    //Submit a DAO vote (with weights)
    function DaoVoteWithWeights(uint256 _voteId, uint256 _yay, uint256 _nay, bool _isOwnership) external onlyDaoOperator returns(bool){
        //convert 10,000 to 1e18
        _yay = _yay.mul(1e18).div(10000);
        _nay = _nay.mul(1e18).div(10000);
        require(_yay.add(_nay) == MAX_VOTE, "!equal max_vote");

        uint256 data = packData(_voteId, _yay, _nay);

        //vote with enocded vote id.  "supported" needs to be false if doing this type
        return IBooster(booster).vote(data, _isOwnership ? voteOwnership : voteParameter, false);
    }

    //Submit a DAO vote
    function DaoVote(uint256 _voteId, bool _support, bool _isOwnership) external onlyDaoOperator returns(bool){
        //vote with full voting power on either choice
        return IBooster(booster).vote(_voteId, _isOwnership ? voteOwnership : voteParameter, _support);
    }

    //Submit Gauge Weights
    function GaugeVote(address[] calldata _gauge, uint256[] calldata _weight) external onlyGaugeOperator returns(bool){
        //vote for gauge weights
        return IBooster(booster).voteGaugeWeight(_gauge, _weight);
    }

    /**
     * @notice Submit a valid vote hash to the Booster
     */
    function setVote(bytes32 hash, bool valid) external onlyDaoOperator returns (bool) {
      return IBooster(booster).setVote(hash, valid);
    } 
}
