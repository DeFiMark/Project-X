//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./IERC20.sol";

interface IBalanceLogger {
    function logBalance(address account, uint256 balance) external;
}

interface ITransferLogger {
    function logTransfer(address sender, address recipient, uint256 amount) external;
}

contract StandardTokenData {

    // total supply
    uint256 internal _totalSupply;

    // token data
    string internal _name;
    string internal _symbol;
    uint8  internal constant _decimals = 18;

    // balances
    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowances;

    // logger for tokenomics
    address public balanceLogger;
    address public transferLogger;

    // owner
    address public owner;

    // metadata url
    string public imageUri;

    // metadata description
    string public description;

    // events
    event SetBalanceLogger(address logger);
    event SetTransferLogger(address logger);
    event SetImageUri(string imageUri);
    event SetOwner(address owner);

    modifier onlyOwner() {
        require(msg.sender == owner, 'Only Owner');
        _;
    }
}

contract StandardToken is IERC20, StandardTokenData {

    function __init__(
        bytes calldata initData
    ) external {
        require(_totalSupply == 0, 'Already Initialized');

        (bytes memory initalizeData, bytes memory setUpData) = abi.decode(initData, (bytes, bytes));

        (
            string memory name_,
            string memory symbol_,
            address balanceLogger_,
            address transferLogger_,
            string memory imageUri_,
            string memory description_,
            address owner_
        ) = abi.decode(initalizeData, (string, string, address, address, string, string, address));

        // set initial token data
        _name = name_;
        _symbol = symbol_;

        // set logger
        balanceLogger = balanceLogger_;
        transferLogger = transferLogger_;

        // set metadata
        imageUri = imageUri_;
        description = description_;

        // set owner
        owner = owner_;

        // get setUp data
        (
            address[] memory initialHolders,
            uint256[] memory initialBalances
        ) = abi.decode(setUpData, (address[], uint256[]));

        // set initial holders
        for (uint256 i = 0; i < initialHolders.length; i++) {
            _balances[initialHolders[i]] = initialBalances[i];
            unchecked {
                _totalSupply += initialBalances[i];
            }
            emit Transfer(address(0), initialHolders[i], initialBalances[i]);
            if (balanceLogger_ != address(0)) {
                IBalanceLogger(balanceLogger_).logBalance(initialHolders[i], initialBalances[i]);
            }
            if (transferLogger_ != address(0)) {
                ITransferLogger(transferLogger_).logTransfer(address(0), initialHolders[i], initialBalances[i]);
            }
        }

        require(_totalSupply > 0, 'Total Supply Is Zero');
    }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }
    
    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /** Transfer Function */
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    /** Transfer Function */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        require(
            _allowances[sender][msg.sender] >= amount,
            'Insufficient Allowance'
        );
        _allowances[sender][msg.sender] -= amount;
        return _transferFrom(sender, recipient, amount);
    }

    function withdrawETH(address to) external onlyOwner {
        require(to != address(0), 'Zero Address');
        (bool s,) = payable(to).call{value: address(this).balance}("");
        require(s);
    }

    function setOwner(address owner_) external onlyOwner {
        owner = owner_;
        emit SetOwner(owner_);
    }
    
    function setBalanceLogger(address balanceLogger_) external onlyOwner {
        balanceLogger = balanceLogger_;
        emit SetBalanceLogger(balanceLogger_);
    }
    
    function setTransferLogger(address transferLogger_) external onlyOwner {
        transferLogger = transferLogger_;
        emit SetTransferLogger(transferLogger_);
    }

    function setImageUri(string memory imageUri_) external onlyOwner {
        imageUri = imageUri_;
        emit SetImageUri(imageUri_);
    }

    function burn(uint256 amount) external returns (bool) {
        return _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external returns (bool) {
        require(
            _allowances[account][msg.sender] >= amount,
            'Insufficient Allowance'
        );
        _allowances[account][msg.sender] -= amount;
        return _burn(account, amount);
    }
    
    /** Internal Transfer */
    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(
            recipient != address(0),
            'Zero Recipient'
        );
        require(
            amount > 0,
            'Zero Amount'
        );
        require(
            amount <= _balances[sender],
            'Insufficient Balance'
        );
        
        // decrement sender balance
        _balances[sender] -= amount;

        // give amount to recipient
        _balances[recipient] += amount;

        // log balance
        if (balanceLogger != address(0)) {
            IBalanceLogger(balanceLogger).logBalance(sender, _balances[sender]);
            IBalanceLogger(balanceLogger).logBalance(recipient, _balances[recipient]);
        }
        if (transferLogger != address(0)) {
            ITransferLogger(transferLogger).logTransfer(sender, recipient, amount);
        }

        // emit transfer
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function _burn(address account, uint256 amount) internal returns (bool) {
        require(
            account != address(0),
            'Zero Address'
        );
        require(
            amount > 0,
            'Zero Amount'
        );
        require(
            amount <= _balances[account],
            'Insufficient Balance'
        );

        // burn
        _balances[account] -= amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);

        // log balance
        if (balanceLogger != address(0)) {
            IBalanceLogger(balanceLogger).logBalance(account, _balances[account]);
        }
        if (transferLogger != address(0)) {
            ITransferLogger(transferLogger).logTransfer(account, address(0), amount);
        }
        return true;
    }

    receive() external payable {}
}