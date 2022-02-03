// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Interfaces.sol";
import "./DepositToken.sol";
import "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-0.6/utils/Address.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";

/**
 * @title   TokenFactory
 * @author  ConvexFinance
 * @notice  Token factory used to create Deposit Tokens. These are the tokenized
 *          pool deposit tokens e.g cvx3crv
 */
contract TokenFactory {
    using Address for address;

    address public immutable operator;

    /**
     * @param _operator Operator is Booster
     */
    constructor(address _operator) public {
        operator = _operator;
    }

    function CreateDepositToken(address _lptoken) external returns(address){
        require(msg.sender == operator, "!authorized");

        DepositToken dtoken = new DepositToken(operator,_lptoken);
        return address(dtoken);
    }
}
