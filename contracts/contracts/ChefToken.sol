// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts-0.6/token/ERC20/ERC20.sol";


/**
 * @title   ChefToken
 * @author  ConvexFinance
 * @notice  Dummy token for master chef plugin
 */
contract ChefToken is ERC20 {

    bool public isInit;

    /**
     * @param _symbolArg  token symbol
     */
    constructor(string memory _symbolArg)
        public
        ERC20(
            "Chef Token",
            _symbolArg
        ){
    }
    
    /**
     * @dev One time init fn, mints a single token to sender
     */
    function create() external {
        require(!isInit, "init");
        
        _mint(msg.sender, 1e18);
        isInit = true;
    }

}