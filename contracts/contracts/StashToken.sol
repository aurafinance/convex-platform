// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Interfaces.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable-0.6/utils/ReentrancyGuardUpgradeable.sol";

interface IERC20Metadata {
    function name() external view returns (string memory); 
    function symbol() external view returns (string memory); 
}

/**
 * @title StashToken
 * @notice StashToken is not ERC20 compliant. 
 * @dev StashToken is not ERC20 compliant. 
 *      it represents a token that can be minted only by the stash contract, and transfered by the reward pool.
 */
contract StashToken is ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint256 public constant MAX_TOTAL_SUPPLY = 1e38;

    // State variables
    address public immutable stash;
    address public operator;
    address public rewardPool;
    address public baseToken;
    bool public isValid;
    bool public isImplementation;
    uint256 internal _totalSupply;

    /**
     * @dev Constructor function
     * @param _stash Address of the stash contract.
     */
    constructor(address _stash) public {
        stash = _stash;
        isImplementation = true;
    }

    /**
     * @dev Initialization function to set operator, reward pool, and base token addresses.
     * @param _operator Address of the operator.
     * @param _rewardPool Address of the reward pool.
     * @param _baseToken Address of the base token.
     */
    function init(
        address _operator,
        address _rewardPool,
        address _baseToken
    ) external initializer {
        require(!isImplementation, "isImplementation");
        
        __ReentrancyGuard_init();

        operator = _operator;
        rewardPool = _rewardPool;
        baseToken = _baseToken;
        isValid = true;
    }

    /**
     * @dev Get the concatenated name of the StashToken.
     * @return The concatenated name of the StashToken.
     */
    function name() external view returns (string memory) {
        return string(abi.encodePacked("Stash Token ", IERC20Metadata(baseToken).name()));
    }

    /**
     * @dev Get the concatenated symbol of the StashToken.
     * @return The concatenated symbol of the StashToken.
     */
    function symbol() external view returns (string memory) {
        return string(abi.encodePacked("STASH-", IERC20Metadata(baseToken).symbol()));
    }

    /**
     * @dev Set the validity status of the StashToken.
     * @param _isValid Boolean indicating the validity status.
     */
    function setIsValid(bool _isValid) external {
        require(msg.sender == IDeposit(operator).owner(), "!owner");
        isValid = _isValid;
    }

    /**
     * @dev Get the total supply of the StashToken.
     * @return The total supply of the StashToken.
     */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Mint new StashToken tokens, only callable  by the stash contract.
     * @param _amount Amount of tokens to mint.
     */
    function mint(uint256 _amount) external nonReentrant {
        require(msg.sender == stash, "!stash");
        require(_totalSupply.add(_amount) < MAX_TOTAL_SUPPLY, "totalSupply exceeded");

        _totalSupply = _totalSupply.add(_amount);
        IERC20(baseToken).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @dev Transfer StashToken tokens to a specified address. Only callable by the reward pool contract.
     * @param _to Address to which tokens are transferred.
     * @param _amount Amount of tokens to transfer. 
     * @return A boolean indicating whether the transfer was successful.
     */
    function transfer(address _to, uint256 _amount) public nonReentrant returns (bool) {
        require(msg.sender == rewardPool, "!rewardPool");
        require(_totalSupply >= _amount, "amount>totalSupply");

        _totalSupply = _totalSupply.sub(_amount);
        IERC20(baseToken).safeTransfer(_to, _amount);

        return true;
    }
}
