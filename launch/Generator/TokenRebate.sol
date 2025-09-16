//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IFactory {
    function isPair(address pair) external view returns (bool);
    function feeToken() external view returns (address);
    function tokenOwner(address token) external view returns (address);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract TokenRebate {

    // Factory to fetch token owner and other information
    address public immutable factory;

    // Rebate rate for each token
    mapping ( address => uint256 ) public rebateRate;
    uint256 public constant REBATE_RATE_DENOM = 10_000;

    // Events
    event SetRebateRate(address token, uint256 rate);
    event Rebate(address token, address to, uint256 amount);

    constructor(address _factory) {
        factory = _factory;
    }

    function setRebateRate(address token, uint256 rate) external {
        require(IFactory(factory).tokenOwner(token) == msg.sender, 'Not the owner of the token');
        rebateRate[token] = rate;
        emit SetRebateRate(token, rate);
    }

    function bought(address to, uint256 amount) external {
        require(IFactory(factory).isPair(msg.sender), 'Not a pair');
        address feeToken = IFactory(factory).feeToken();
        if (feeToken != address(0)) {
            uint256 rate = rebateRate[feeToken];
            if (rate > 0) {
                uint256 rebateAmount = ( amount * rate ) / REBATE_RATE_DENOM;
                uint256 balance = IERC20(feeToken).balanceOf(address(this));
                if (rebateAmount > balance) {
                    rebateAmount = balance;
                }
                if (rebateAmount > 0) {
                    IERC20(feeToken).transfer(to, rebateAmount);
                    emit Rebate(feeToken, to, rebateAmount);
                }
            }
        }
    }
}