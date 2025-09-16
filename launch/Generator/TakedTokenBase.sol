//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./IERC20.sol";

contract ModularTaxedTokenData {

    // total supply
    uint256 internal _totalSupply;

    // token data
    string internal _name;
    string internal _symbol;
    uint8  internal constant _decimals = 18;

    // balances
    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowances;

    // Taxation on transfers
    uint32 public buyFee             = 0;
    uint32 public sellFee            = 0;
    uint32 public transferFee        = 0;
    uint256 public constant TAX_DENOM = 10000;

    // permissions
    struct Permissions {
        bool isFeeExempt;
        bool isLiquidityPool;
    }
    mapping ( address => Permissions ) public permissions;

    // Fee Recipients
    address public feeRecipient;

    // owner
    address public owner;

    // events
    event SetFeeRecipient(address recipient);
    event SetFeeExemption(address account, bool isFeeExempt);
    event SetAutomatedMarketMaker(address account, bool isMarketMaker);
    event SetFees(uint256 buyFee, uint256 sellFee, uint256 transferFee);
}

contract ModularTaxedToken is IERC20, ModularTaxedTokenData {

    function __init__(
        bytes calldata initData
    ) external {
        require(_totalSupply == 0, 'Already Initialized');

        (bytes memory initalizeData, bytes memory setUpData) = abi.decode(initData, (bytes, bytes));

        (
            string memory name_,
            string memory symbol_,
            address feeRecipient_,
            uint32 buyFee_,
            uint32 sellFee_,
            uint32 transferFee_,
            address owner_
        ) = abi.decode(initalizeData, (string, string, address, uint32, uint32, uint32, address));

        // set initial token data
        _name = name_;
        _symbol = symbol_;
    
        // set initial fees
        buyFee = buyFee_;
        sellFee = sellFee_;
        transferFee = transferFee_;
        feeRecipient = feeRecipient_;

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

            // exempt initial holders
            permissions[initialHolders[i]].isFeeExempt = true;
        }

        // exempt owner
        permissions[owner_].isFeeExempt = true;
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

        // fee for transaction
        (uint256 fee) = getTax(sender, recipient, amount);

        // allocate fee
        if (fee > 0) {
            address feeDestination = feeRecipient == address(0) ? address(this) : feeRecipient;
            _balances[feeDestination] += fee;
            emit Transfer(sender, feeDestination, fee);
        }

        // give amount to recipient
        uint256 sendAmount = amount - fee;
        _balances[recipient] += sendAmount;

        // emit transfer
        emit Transfer(sender, recipient, sendAmount);
        return true;
    }

    function withdraw(address token) external onlyOwner {
        require(token != address(0), 'Zero Address');
        bool s = IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
        require(s, 'Failure On Token Withdraw');
    }

    function withdrawETH() external onlyOwner {
        (bool s,) = payable(msg.sender).call{value: address(this).balance}("");
        require(s);
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Zero Address');
        feeRecipient = recipient;
        permissions[recipient].isFeeExempt = true;
        emit SetFeeRecipient(recipient);
    }

    function registerAutomatedMarketMaker(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(!permissions[account].isLiquidityPool, 'Already An AMM');
        permissions[account].isLiquidityPool = true;
        emit SetAutomatedMarketMaker(account, true);
    }

    function unRegisterAutomatedMarketMaker(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(permissions[account].isLiquidityPool, 'Not An AMM');
        permissions[account].isLiquidityPool = false;
        emit SetAutomatedMarketMaker(account, false);
    }

    function setFees(uint _buyFee, uint _sellFee, uint _transferFee) external onlyOwner {
        require(
            _buyFee <= FEE_DENOM,
            'Buy Fee Too High'
        );
        require(
            _sellFee <= FEE_DENOM,
            'Sell Fee Too High'
        );
        require(
            _transferFee <= FEE_DENOM,
            'Transfer Fee Too High'
        );

        buyFee = _buyFee;
        sellFee = _sellFee;
        transferFee = _transferFee;

        emit SetFees(_buyFee, _sellFee, _transferFee);
    }

    function setFeeExempt(address account, bool isExempt) external onlyOwner {
        require(account != address(0), 'Zero Address');
        permissions[account].isFeeExempt = isExempt;
        emit SetFeeExemption(account, isExempt);
    }

    function getTax(address sender, address recipient, uint256 amount) public view returns (uint256) {
        if ( permissions[sender].isFeeExempt || permissions[recipient].isFeeExempt ) {
            return 0;
        }
        return permissions[sender].isLiquidityPool ? 
               ((amount * buyFee) / TAX_DENOM) : 
               permissions[recipient].isLiquidityPool ? 
               ((amount * sellFee) / TAX_DENOM) :
               ((amount * transferFee) / TAX_DENOM);
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
        _balances[account] -= amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
        return true;
    }

    receive() external payable {}
}