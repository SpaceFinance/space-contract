// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract Airdrop is Initializable, ContextUpgradeable, OwnableUpgradeable {

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct UserInfo {
        uint256 claimInitial;
        uint256 isFarm;
        uint256 isNode;
        uint256 isNFT;
        uint256 isVote;
		bool freeze;
    }

    struct ReceiveInfo {
        uint256 initialReceive;
        uint256 farmReceive;
        uint256 nodeReceive;
        uint256 nftReceive;
        uint256 voteReceive;
    }

    struct Ratio {
        uint256 initialRatio;
        uint256 farmRatio;
        uint256 nodeRatio;
        uint256 nftRatio;
        uint256 voteRatio;
    }

    struct SlotInfo {
        uint256 initialAmount;
        uint256 receiveInitialAmount;
        uint256 farmAmount;
        uint256 receiveFarmAmount;
        uint256 nodeAmount;
        uint256 receiveNodeAmount;
        uint256 nftAmount;
        uint256 receiveNFTAmount;
        uint256 voteAmount;
        uint256 receiveVoteAmount;
        uint256 amount;
        uint256 receiveAmount;
    }

    IERC20Upgradeable public starToken;
    address public lockAddr;
    uint256 public startTime;
    uint256 public endTime;
    address[] public admin;
    address[] public users;
    Ratio public RatioInfo;

    mapping (address => UserInfo) public userInfo;
    mapping (address => uint256) public userNum;
    mapping (address => ReceiveInfo) public receiveInfo;
    mapping (address => bool) public adminInfo;
    mapping (address => uint256) public userIndexd;

    event Receives(address _user, uint256 _amount);
    event Received(address, uint);
    event EndAirdrop(uint256 amount, uint256 endTime);

    function initialize(address _starToken, address _lockAddr, uint256 _startTime, uint256 _endTime) public initializer {
        __Airdrop_init(_starToken, _lockAddr, _startTime, _endTime);
    }

    function __Airdrop_init(address _starToken, address _lockAddr, uint256 _startTime, uint256 _endTime) internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Airdrop_init_unchained(_starToken, _lockAddr, _startTime, _endTime);
    }

    function __Airdrop_init_unchained(address _starToken, address _lockAddr, uint256 _startTime, uint256 _endTime) internal initializer {
        starToken = IERC20Upgradeable(_starToken);
        lockAddr = _lockAddr;
        startTime = _startTime;
        endTime = _endTime;
        adminInfo[_msgSender()] = true;
        admin.push(_msgSender());
        RatioInfo.initialRatio = 2000;
        RatioInfo.farmRatio = 2000;
        RatioInfo.nodeRatio = 2000;
        RatioInfo.nftRatio = 2000;
        RatioInfo.voteRatio = 2000;
    }

    function setUserInfo(address _user, uint256 _isFarm, uint256 _isNode, uint256 _isNFT, uint256 _isVote) public onlyAdmin {
        require(_user != address(0), "user address error");
        require(_isFarm <=1, "isFarm error");
        require(_isNode <=1, "isNode error");
        require(_isNFT <=1, "isNFT error");
        require(_isVote <=1, "isVote error");
        UserInfo storage user = userInfo[_user];
        user.isFarm = _isFarm;
        user.isNode = _isNode;
        user.isNFT = _isNFT;
        user.isVote = _isVote;
    }

    function setUser(address _user, uint256 _type) external onlyAdmin {
        require(_user != address(0), "user address error");
        UserInfo storage user = userInfo[_user];
        if(_type == 1){
            user.isFarm = 1;
        }
        if(_type == 2){
            user.isNode = 1;
        }
        if(_type == 3){
            user.isNFT = 1;
        }
        if(_type == 4){
            user.isVote = 1;
        }
    }

    function freeze(address _user) public onlyAdmin {
        require(_user != address(0), "user address error");
        UserInfo storage user = userInfo[_user];
        user.freeze = true;
    }

    function unfreeze(address _user) public onlyAdmin {
        require(_user != address(0), "user address error");
        UserInfo storage user = userInfo[_user];
        user.freeze = false;
    }

    function getReceive(address _user) public view returns(uint256, uint256){
        UserInfo storage user = userInfo[_user];
        if(user.freeze == true){
            return (0, 0);
        }
        ReceiveInfo storage received = receiveInfo[_user];
        SlotInfo memory slot;
        slot.initialAmount = user.claimInitial.mul(RatioInfo.initialRatio);
        slot.receiveInitialAmount = received.initialReceive.mul(RatioInfo.initialRatio);
        slot.farmAmount = user.isFarm.mul(RatioInfo.farmRatio);
        slot.receiveFarmAmount = received.farmReceive.mul(RatioInfo.farmRatio);
        slot.nodeAmount = user.isNode.mul(RatioInfo.nodeRatio);
        slot.receiveNodeAmount = received.nodeReceive.mul(RatioInfo.nodeRatio);
        slot.nftAmount = user.isNFT.mul(RatioInfo.nftRatio);
        slot.receiveNFTAmount = received.nftReceive.mul(RatioInfo.nftRatio);
        slot.voteAmount = user.isVote.mul(RatioInfo.voteRatio);
        slot.receiveVoteAmount = received.voteReceive.mul(RatioInfo.voteRatio);

        slot.amount = userNum[_user].mul(slot.initialAmount.add(slot.farmAmount).add(slot.nodeAmount).add(slot.nftAmount).add(slot.voteAmount)).div(10000);
        slot.receiveAmount = userNum[_user].mul(slot.receiveInitialAmount.add(slot.receiveFarmAmount).add(slot.receiveNodeAmount).add(slot.receiveNFTAmount).add(slot.receiveVoteAmount)).div(10000);
        return (slot.amount, slot.receiveAmount);
    }

    function separatelyReceive(uint256 _type) public {
        require(startTime < block.timestamp, 'Not started');
        require(endTime > block.timestamp, 'Has ended');
        UserInfo storage user = userInfo[_msgSender()];
        require(user.freeze == false, "address is freeze.");
        ReceiveInfo storage received = receiveInfo[_msgSender()];
        uint256 initialAmount = 0;
        uint256 nftAmount = 0;
        uint256 voteAmount = 0;
        uint256 farmAmount = 0;
        uint256 nodeAmount = 0;
		if(_type == 1){
            require(user.claimInitial > received.initialReceive, "initialReceive error");
            if(user.claimInitial == 1 && received.initialReceive == 0){
                initialAmount = user.claimInitial.mul(RatioInfo.initialRatio);
                received.initialReceive = 1;
            }
		}
        if(_type == 2){
            require(user.isFarm > received.farmReceive, "farmReceive error");
            if(user.isFarm == 1 && received.farmReceive == 0){
                farmAmount = user.isFarm.mul(RatioInfo.farmRatio);
                received.farmReceive = 1;
            }
        }
        if(_type == 3){
            require(user.isNode > received.nodeReceive, "nodeReceive error");
            if(user.isNode == 1 && received.nodeReceive == 0){
                nodeAmount = user.isNode.mul(RatioInfo.nodeRatio);
                received.nodeReceive = 1;
            }
		}
        if(_type == 4){
            require(user.isNFT > received.nftReceive, "nftReceive error");
            if(user.isNFT == 1 && received.nftReceive == 0){
                nftAmount = user.isNFT.mul(RatioInfo.nftRatio);
                received.nftReceive = 1;
            }
        }
        if(_type == 5){
            require(user.isVote > received.voteReceive, "voteReceive error");
            if(user.isVote == 1 && received.voteReceive == 0){
                voteAmount = user.isVote.mul(RatioInfo.voteRatio);
                received.voteReceive = 1;
            }
        }
        uint256 amount = initialAmount.add(farmAmount).add(nodeAmount).add(nftAmount).add(voteAmount);
        starToken.safeTransfer(_msgSender(), userNum[_msgSender()].mul(amount).div(10000));
        emit Receives(_msgSender(), amount);
    }

    receive() external payable {
        emit Received(_msgSender(), msg.value);
    }

    function setRatioInfo(uint256 _initialRatio, uint256 _farmRatio, uint256 _nodeRatio, uint256 _nftRatio, uint256 _voteRatio) public onlyOwner {
        RatioInfo.initialRatio = _initialRatio;
        RatioInfo.farmRatio = _farmRatio;
        RatioInfo.nodeRatio = _nodeRatio;
        RatioInfo.nftRatio = _nftRatio;
        RatioInfo.voteRatio = _voteRatio;
    }

    function setAirdropNum(address[] memory _users, uint256 _airdropNum) public onlyAdmin {
        require(_airdropNum > 0, "airdropNum error");
        for(uint256 i=0; i < _users.length; i++){
            address _user = _users[i];
            require(users.length == 0 || (users.length > 0 && userIndexd[_user] == 0), "address exists");
            userInfo[_user].claimInitial = 1;
            userNum[_user] = _airdropNum;
            users.push(_user);
            userIndexd[_user] = users.length - 1;
        }
    }

    function getUserNum() public view returns (uint256) {
        return users.length;
    }

    function setTime(uint256 _startTime, uint256 _endTime) public onlyOwner {
        require(_startTime > 0, "startTime error");
        require(_endTime > 0, "endTime error");
        startTime = _startTime;
        endTime = _endTime;
    }

    function endAirdrop() public onlyOwner {
        require( block.timestamp >= endTime, "Airdrop is in progress");
        uint256 amount = starToken.balanceOf(address(this));
        starToken.safeTransfer(lockAddr, amount);
        emit EndAirdrop(amount, endTime);
    }

    function setLockAddr(address _addr) onlyOwner public {
        require(address(0) != _addr, "address error");
        lockAddr = _addr;
    }

    function setAdmin(address _admin) public onlyOwner {
        require(_admin != address(0) && adminInfo[_admin] == false, "address err");
        adminInfo[_admin] = true;
        admin.push(_admin);
    }

    function setStarToken(address _starToken) public onlyOwner {
        require(address(0) != _starToken, "address error");
        starToken = IERC20Upgradeable(_starToken);
    }

    modifier onlyAdmin() {
        require(adminInfo[msg.sender] == true, "Ownable: caller is not the administrators");
        _;
    }
}