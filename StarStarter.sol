// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract Starter is Initializable, ContextUpgradeable, OwnableUpgradeable {

    using MathUpgradeable for uint;
    using SafeMathUpgradeable for uint;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public currency;
    IERC20Upgradeable public underlying;

    uint public price;
    uint public time;
    uint public settleRate;
    uint public timeSettle;
    bool public completed;

    uint public totalPurchasedCurrency;
    uint public totalSettledUnderlying;
    uint totalSettledCurrency;
    uint public maxNumber;
    uint public minNumber;

    mapping (address => uint) public purchasedCurrencyOf;
    mapping (address => uint) public settledUnderlyingOf;
    mapping (address => uint) public settledCurrencyOf;

    event Purchase(address indexed acct, uint amount, uint totalCurrency);
    event Settle(address indexed acct, uint amount, uint volume, uint rate);
    event Withdrawn(address to, uint amount, uint volume);

    function initialize(address currency_, address underlying_, uint price_, uint time_, uint timeSettle_, uint minNumber_, uint maxNumber_) public initializer {
        __Starter_init(currency_, underlying_, price_, time_, timeSettle_, minNumber_, maxNumber_);
    }

    function __Starter_init(address currency_, address underlying_, uint price_, uint time_, uint timeSettle_, uint minNumber_, uint maxNumber_) internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Starter_init_unchained(currency_, underlying_, price_, time_, timeSettle_, minNumber_, maxNumber_);
    }

    function __Starter_init_unchained(address currency_, address underlying_, uint price_, uint time_, uint timeSettle_, uint minNumber_, uint maxNumber_) internal initializer {
        currency    = IERC20Upgradeable(currency_);
        underlying  = IERC20Upgradeable(underlying_);
        price       = price_;
        time        = time_;
        timeSettle  = timeSettle_;
        minNumber = minNumber_;
        maxNumber =  maxNumber_;
        require(timeSettle_ >= time_, 'timeSettle_ should >= time_');
    }

    function savecompleted() public onlyOwner {
        completed = true;
    }

    function purchase(uint amount) external {
        require(block.timestamp < time, 'expired');
        require(amount >= minNumber && maxNumber >= amount, "amount error");
        require(maxNumber-purchasedCurrencyOf[_msgSender()] >= amount, "Maximum number exceeded");
        currency.safeTransferFrom(_msgSender(), address(this), amount);
        purchasedCurrencyOf[_msgSender()] = purchasedCurrencyOf[_msgSender()].add(amount);
        totalPurchasedCurrency = totalPurchasedCurrency.add(amount);
        emit Purchase(_msgSender(), amount, totalPurchasedCurrency);
    }

    function purchaseBNB() public payable {
        require(address(currency) == address(0), 'should call purchase(uint amount) instead');
        require(block.timestamp < time, 'expired');
        uint amount = msg.value;
        require(amount >= minNumber && maxNumber >= amount, "amount error");
        purchasedCurrencyOf[_msgSender()] = purchasedCurrencyOf[_msgSender()].add(amount);
        totalPurchasedCurrency = totalPurchasedCurrency.add(amount);
        emit Purchase(_msgSender(), amount, totalPurchasedCurrency);
    }

    function totalSettleable() public view  returns (bool completed_, uint amount, uint volume, uint rate) {
        return settleable(address(0));
    }

    function settleable(address acct) public view returns (bool completed_, uint amount, uint volume, uint rate) {
        completed_ = completed;
        if(completed_) {
            rate = settleRate;
        } else {
            uint totalCurrency = address(currency) == address(0) ? address(this).balance : currency.balanceOf(address(this));
            uint totalUnderlying = underlying.balanceOf(address(this));
            if(totalUnderlying.mul(price) < totalCurrency.mul(1e18))
                rate = totalUnderlying.mul(price).div(totalCurrency);
            else
                rate = 1 ether;
        }
        uint purchasedCurrency = acct == address(0) ? totalPurchasedCurrency : purchasedCurrencyOf[acct];
        uint settleAmount = purchasedCurrency.mul(rate).div(1e18);
        amount = purchasedCurrency.sub(settleAmount).sub(acct == address(0) ? totalSettledCurrency : settledCurrencyOf[acct]);
        volume = settleAmount.mul(1e18).div(price).sub(acct == address(0) ? totalSettledUnderlying : settledUnderlyingOf[acct]);
    }

    function settle() public {
        require(block.timestamp >= time, "It is not time yet");
        require(settledUnderlyingOf[_msgSender()] == 0 || settledCurrencyOf[_msgSender()] == 0 , 'settled already');
        (bool completed_, uint amount, uint volume, uint rate) = settleable(_msgSender());
        if(!completed_) {
            completed = true;
            settleRate = rate;
        }
        settledCurrencyOf[_msgSender()] = settledCurrencyOf[_msgSender()].add(amount);
        totalSettledCurrency = totalSettledCurrency.add(amount);
        if(address(currency) == address(0))
            payable(_msgSender()).transfer(amount);
        else
            currency.safeTransfer(_msgSender(), amount);
            require(amount > 0 || block.timestamp >= timeSettle, 'It is not time to settle underlying');
        if(block.timestamp >= timeSettle) {
            settledUnderlyingOf[_msgSender()] = settledUnderlyingOf[_msgSender()].add(volume);
            totalSettledUnderlying = totalSettledUnderlying.add(volume);
            underlying.safeTransfer(_msgSender(), volume);
        }
        emit Settle(_msgSender(), amount, volume, rate);
    }

    function withdrawable() public view returns (uint amt, uint vol) {
        if(!completed)
            return (0, 0);
        //amt = currency == address(0) ? address(this).balance : IERC20(currency).balanceOf(address(this));
        //amt = amt.add(totalSettledUnderlying.mul(price).div(settleRate).mul(uint(1e18).sub(settleRate)).div(1e18)).sub(totalPurchasedCurrency.mul(uint(1e18).sub(settleRate)).div(1e18));
        amt = totalPurchasedCurrency.mul(settleRate).div(1e18);
        vol = underlying.balanceOf(address(this)).add(totalSettledUnderlying).sub(totalPurchasedCurrency.mul(settleRate).div(price));
    }

    function withdraw(address payable to, uint amount, uint volume) external onlyOwner {
        require(completed, "uncompleted");
        (uint amt, uint vol) = withdrawable();
        amount = MathUpgradeable.min(amount, amt);
        volume = MathUpgradeable.min(volume, vol);
        if(address(currency) == address(0))
            to.transfer(amount);
        else
            currency.safeTransfer(to, amount);
        underlying.safeTransfer(to, volume);
        emit Withdrawn(to, amount, volume);
    }

    function allWithdraw(address payable to, uint amount, uint volume) external onlyOwner {
        currency.safeTransfer(to, amount);
        underlying.safeTransfer(to, volume);
        emit Withdrawn(to, amount, volume);
    }

    /// @notice This method can be used by the owner to extract mistakenly
    ///  sent tokens to this contract.
    /// @param _token The address of the token contract that you want to recover
    function rescueTokens(address _token, address _dst) public onlyOwner {
        require(address(_token) != address(currency) && address(_token) != address(underlying));
        uint balance = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(_dst, balance);
    }

    function withdrawBNB(address payable _dst) external onlyOwner {
        require(address(currency) != address(0));
        _dst.transfer(address(this).balance);
    }

    function withdrawBNB() external onlyOwner {
        require(address(currency) != address(0));
        payable(_msgSender()).transfer(address(this).balance);
    }

    receive() external payable{
    if(msg.value > 0)
        purchaseBNB();
    else
        settle();
    }

    fallback() external {
        settle();
    }
}

    contract Offering is Initializable, ContextUpgradeable, OwnableUpgradeable {

    using MathUpgradeable for uint;
    using SafeMathUpgradeable for uint;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public currency;
    IERC20Upgradeable public underlying;

    uint public ratio;
    uint public time;
    uint public timeSettle;

    uint public totalQuota;
    uint public totalPurchasedUnderlying;
    uint public totalSettledUnderlying;
    uint public minNumber;
    uint public maxNumber;

    address payable public recipient;

    mapping (address => uint) public quotaOf;
    mapping (address => uint) public purchasedUnderlyingOf;
    mapping (address => uint) public settledUnderlyingOf;

    event Quota(address indexed addr, uint amount, uint total);
    event Purchase(address indexed addr, uint amount, uint volume, uint total);
    event Settle(address indexed addr, uint volume, uint total);

    function initialize(address currency_, address underlying_, uint ratio_, address payable recipient_, uint time_, uint timeSettle_, uint minNumber_, uint maxNumber_) public initializer {
        __Offering_init(currency_, underlying_, ratio_, recipient_, time_, timeSettle_, minNumber_, maxNumber_);
    }

    function __Offering_init(address currency_, address underlying_, uint ratio_, address payable recipient_, uint time_, uint timeSettle_, uint minNumber_, uint maxNumber_) internal initializer {
        __Ownable_init_unchained();
        __Offering_init_unchained(currency_, underlying_, ratio_, recipient_, time_, timeSettle_, minNumber_, maxNumber_);
    }

    function __Offering_init_unchained(address currency_, address underlying_, uint ratio_, address payable recipient_, uint time_, uint timeSettle_, uint minNumber_, uint maxNumber_) internal initializer {
        currency = IERC20Upgradeable(currency_);
        underlying = IERC20Upgradeable(underlying_);
        ratio = ratio_;
        recipient = recipient_;
        time = time_;
        timeSettle = timeSettle_;
        minNumber = minNumber_;
        maxNumber = maxNumber_;
    }

    function savecompleted() public onlyOwner {
        timeSettle = block.timestamp;
    }

    function setQuota(address addr, uint amount) public onlyOwner {
        totalQuota = totalQuota.add(amount).sub(quotaOf[addr]);
        quotaOf[addr] = amount;
        emit Quota(addr, amount, totalQuota);
    }

    function setQuotas(address[] memory addrs, uint amount) external {
        for(uint i=0; i<addrs.length; i++)
        setQuota(addrs[i], amount);
    }

    function setQuotas(address[] memory addrs, uint[] memory amounts) external {
        for(uint i=0; i<addrs.length; i++)
        setQuota(addrs[i], amounts[i]);
    }

    function purchase(uint amount) external {
        require(address(currency) != address(0), 'should call purchaseBNB() instead');
        require(block.timestamp >= time, "it's not time yet");
        require(block.timestamp < timeSettle, "expired");
        require(amount >= minNumber && maxNumber >= amount, "amount error");
        amount = MathUpgradeable.min(amount, quotaOf[_msgSender()]);
        require(amount > 0, 'no quota');
        require(currency.allowance(_msgSender(), address(this)) >= amount, 'allowance not enough');
        require(currency.balanceOf(_msgSender()) >= amount, 'balance not enough');
        require(purchasedUnderlyingOf[_msgSender()] == 0, 'purchased already');

        currency.safeTransferFrom(_msgSender(), recipient, amount);
        uint volume = amount.mul(ratio).div(1e18);
        purchasedUnderlyingOf[_msgSender()] = volume;
        totalPurchasedUnderlying = totalPurchasedUnderlying.add(volume);
        require(totalPurchasedUnderlying <= underlying.balanceOf(address(this)), 'Quota is full');
        emit Purchase(_msgSender(), amount, volume, totalPurchasedUnderlying);
    }

    function purchaseBNB() public payable {
        require(address(currency) == address(0), 'should call purchase(uint amount) instead');
        require(block.timestamp >= time, "it's not time yet");
        require(block.timestamp < timeSettle, "expired");
        uint amount = MathUpgradeable.min(msg.value, quotaOf[_msgSender()]);
        require(amount >= minNumber && maxNumber >= amount, "amount error");
        require(amount > 0, 'no quota');
        require(purchasedUnderlyingOf[_msgSender()] == 0, 'purchased already');

        recipient.transfer(amount);
        uint volume = amount.mul(ratio).div(1e18);
        purchasedUnderlyingOf[_msgSender()] = volume;
        totalPurchasedUnderlying = totalPurchasedUnderlying.add(volume);
        require(totalPurchasedUnderlying <= underlying.balanceOf(address(this)), 'Quota is full');
        if(msg.value > amount)
        payable(_msgSender()).transfer(msg.value.sub(amount));
        emit Purchase(_msgSender(), amount, volume, totalPurchasedUnderlying);
    }

    function settle() public {
        require(block.timestamp >= timeSettle, "It is not time yet");
        require(settledUnderlyingOf[_msgSender()] == 0, "settled already");
        if(underlying.balanceOf(address(this)).add(totalSettledUnderlying) > totalPurchasedUnderlying)
        underlying.safeTransfer(recipient, underlying.balanceOf(address(this)).add(totalSettledUnderlying).sub(totalPurchasedUnderlying));
        uint volume = purchasedUnderlyingOf[_msgSender()];
        settledUnderlyingOf[_msgSender()] = volume;
        totalSettledUnderlying = totalSettledUnderlying.add(volume);
        underlying.safeTransfer(_msgSender(), volume);
        emit Settle(_msgSender(), volume, totalSettledUnderlying);
    }

    /// @notice This method can be used by the owner to extract mistakenly
    ///  sent tokens to this contract.
    /// @param _token The address of the token contract that you want to recover
    function rescueTokens(address _token, address _dst) public onlyOwner {
        require(block.timestamp > timeSettle);
        uint balance = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(_dst, balance);
    }

    function allWithdraw(address _token, address _dst) external onlyOwner {
        uint balance = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(_dst, balance);
    }

    function withdrawToken(address _dst) external onlyOwner {
        rescueTokens(address(underlying), _dst);
    }

    function withdrawToken() external onlyOwner {
        rescueTokens(address(underlying), _msgSender());
    }

    function withdrawBNB(address payable _dst) external onlyOwner {
        require(address(currency) != address(0));
        _dst.transfer(address(this).balance);
    }

    function withdrawBNB() external onlyOwner {
        require(address(currency) != address(0));
        payable(_msgSender()).transfer(address(this).balance);
    }

    receive() external payable{
        if(msg.value > 0)
        purchaseBNB();
        else
        settle();
    }

    fallback() external {
        settle();
    }
}