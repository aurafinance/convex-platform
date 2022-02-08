// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IFeeClaim{
    function claim(address) external;
    function claim_many(address[20] calldata ) external;
    function last_token_time() external view returns(uint256);
    function time_cursor() external view returns(uint256);
    function time_cursor_of(address) external view returns(uint256);
    function user_epoch_of(address) external view returns(uint256);
    function user_point_epoch(address) external view returns(uint256);
    function earmarkFees() external returns(bool);
    function balanceOf(address) external view returns(uint256);
}

/**
 * @title   ClaimVecrvFees
 * @author  ConvexFinance
 * @notice  Claim vecrv fees and distribute
 * @dev     Allows anyone to call `claimFees` that will basically collect any 3crv and distribute to cvxCrv
 *          via the booster.
 */
contract ClaimVecrvFees{

    address public immutable booster;
    address public immutable vecrv;
    address public immutable feeClaim;
    address public immutable account;
    address public immutable tokenaddress;

    uint256 public lastTokenTime;

    /**
     * @param _booster      Booster.sol, e.g. 0xF403C135812408BFbE8713b5A23a04b3D48AAE31
     * @param _vecrv        VotingEscrow, e.g. 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2
     * @param _feeClaim     Claim system fees e.g. 0xA464e6DCda8AC41e03616F95f4BC98a13b8922Dc
     * @param _account      CVX VoterProxy e.g. 0x989AEb4d175e16225E39E87d0D97A3360524AD80
     * @param _tokenaddress Fee token (3crv) e.g. 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490
     */
    constructor(
        address _booster,
        address _vecrv,
        address _feeClaim,
        address _account,
        address _tokenaddress
    ) public {
        booster = _booster;
        vecrv = _vecrv;
        feeClaim = _feeClaim;
        account = _account;
        tokenaddress = _tokenaddress;
    }

    function getName() external pure returns (string memory) {
        return "ClaimVecrvFees V1.0";
    }

    /**
     * @dev Claims fees from fee claimer, and pings the booster to distribute
     */
    function claimFees() external {
        uint256 tokenTime = IFeeClaim(feeClaim).last_token_time();
        require(tokenTime > lastTokenTime, "not time yet");
        uint256 bal = IFeeClaim(tokenaddress).balanceOf(account);
        IFeeClaim(feeClaim).claim(account);

        while(IFeeClaim(tokenaddress).balanceOf(account) <= bal){
            IFeeClaim(feeClaim).claim(account);
        }

        IFeeClaim(booster).earmarkFees();
        lastTokenTime = tokenTime;
    }

}