// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

interface IStarNode {
    function nodeGain(address _user) external view returns (uint256, uint256);
    function settleNode(address _user, uint256 _amount, uint256 _selfAmount) external;
}

interface INFTLogic {
    function starMeta(uint256 _tokenId) view external returns (uint8, uint256, uint256, uint256);
    // @error Exception to be handled
}

interface IBonus {
    function getlockRatio() view external returns (uint256);
    function addTotalAmount(uint256) external;
}

interface IStarToken {
    function farmMint(address account, uint256 amount) external;
}

// import "@nomiclabs/buidler/console.sol";
interface IMigratorChef {
    function migrate(IERC20Upgradeable token) external returns (IERC20Upgradeable);
}

interface IAirdrop {
    function setUser(address _user, uint256 _type) external;
}

// MasterChef is the master of Star. He can make Star and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once STAR is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 lastDeposit;
        uint256 nftAmount;
        uint256 nftRewardDebt;
        uint256 nftLastDeposit;
        //
        // We do some fancy math here. Basically, any point in time, the amount of STARs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accStarPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accStarPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20Upgradeable lpToken;  // Address of LP token contract.
        uint256 lpSupply;
        uint256 allocPoint;         // How many allocation points assigned to this pool. STARs to distribute per block.
        uint256 lastRewardBlock;    // Last block number that STARs distribution occurs.
        uint256 accStarPerShare;    // Accumulated STARs per share, times 1e12. See below.
        uint256 extraAmount;        // Extra amount of token. users from node or NFT.
        uint256 fee;
        uint256 size;
    }

    struct SlotInfo {
        uint256 accStarPerShare;
        uint256 lpSupply;
        uint256 multiplier;
        uint256 starReward;
        uint256 _amount;
        uint256 _amountGain;
        uint256 nftAmount;
        uint256 allNFTPendingStar;
    }

    struct BlockReward {
        uint256 plannedBlock;
        uint256 plannedReward;
    }

    // The STAR TOKEN!
    IERC20Upgradeable public starToken;
    IStarToken public iToken;
    // Star node.
    address public nodeAddr;
    IStarNode public starNode;
    // Dev address.
    address public bonusAddr;
    // Star NFT.
    IERC721Upgradeable public starNFT;
    // NFT logic
    INFTLogic public nftLogic;
    // STAR tokens created per block.
    uint256 public starPerBlock;
    // Bonus muliplier for early star makers.
    uint256 public BONUS_MULTIPLIER;
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;
    IBonus public Bonus;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    mapping (uint256 => mapping (uint256 => address)) public userIndex;
    mapping (uint256 => mapping (address => bool)) public isPoolUser;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when STAR mining starts.
    uint256 public startBlock;
    address public lockAddr;
    address public teamAddr;
    address public rewardAddr;
    uint256 public lockRatio;
    uint256 public teamRatio;
    uint256 public rewardRatio;
    uint256 public lastPerReward;
    BlockReward[] public blockReward;

    // Node user
    mapping (address => bool) public isNodeUser;
    mapping (address => uint256[]) public userNFTs;
    uint256[] public StakingNFTs;
    mapping (uint256 => address) public nftUser;
    mapping (uint256 => uint256) public StakingIndex;
    mapping (uint256 => uint256[]) public NFTGroup;
    mapping (uint256 => mapping(uint256 => uint256)) public groupIndex;
    IAirdrop public Airdrop;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, bool isNodeUser);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 pending, bool isNodeUser, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount, bool isNodeUser);

    function initialize(address _starToken, address _bonus, address _node, uint256 _starPerBlock, uint256 _startBlock) public initializer {
        __farm_init(_starToken, _bonus, _node, _starPerBlock, _startBlock);
    }

    function __farm_init(address _starToken, address _bonus, address _node, uint256 _starPerBlock, uint256 _startBlock) internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __farm_init_unchained(_starToken, _bonus, _node, _starPerBlock, _startBlock);
    }

    function __farm_init_unchained(address _starToken, address _bonus, address _node, uint256 _starPerBlock, uint256 _startBlock) internal initializer {
        starToken = IERC20Upgradeable(_starToken);
        iToken = IStarToken(_starToken);
        bonusAddr = _bonus;
        nodeAddr = _node;
        Bonus = IBonus(_bonus);
        starNode = IStarNode(_node);
        starPerBlock = _starPerBlock;
        startBlock = _startBlock;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: IERC20Upgradeable(_starToken),
            lpSupply: 0,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accStarPerShare: 0,
            extraAmount: 0,
            fee: 0,
            size: 0
            }));

        totalAllocPoint = 1000;
        BONUS_MULTIPLIER = 1;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20Upgradeable _lpToken, uint256 _fee, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            lpSupply: 0,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accStarPerShare: 0,
            extraAmount: 0,
            fee: _fee,
            size: 0
            }));
    }

    // Update the given pool's STAR allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint256 _fee, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].fee = _fee;
    }

    function addBlockReward(uint256 _block, uint256 _reward) public onlyOwner {
        require(_block > block.number,"block error");
        blockReward.push(BlockReward({
            plannedBlock: _block,
            plannedReward: _reward
            }));
    }

    function setBlockReward(uint256 _rid, uint256 _block, uint256 _reward) public onlyOwner {
        BlockReward storage breward = blockReward[_rid];
        require(_block > block.number && breward.plannedBlock > block.number,"block error");
        breward.plannedBlock = _block;
        breward.plannedReward = _reward;
    }

    function delBlockReward(uint256 _rid) public onlyOwner {
        for(uint256 i; i< blockReward.length; i++){
            if(i == _rid){
                blockReward[i] = blockReward[blockReward.length - 1];
                blockReward.pop();
            }
        }
    }

    function updatePerBlock(uint256 _i) private {
        lastPerReward = starPerBlock;
        starPerBlock = blockReward[_i].plannedReward;
        for(uint256 i = 0; i < poolInfo.length; i++){
            PoolInfo storage pool = poolInfo[i];
            if(pool.lastRewardBlock > blockReward[_i].plannedBlock){
                continue;
            }
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, blockReward[_i].plannedBlock);
            uint256 starReward = multiplier.mul(lastPerReward).mul(pool.allocPoint).div(totalAllocPoint);
            uint256 lpSupply = pool.lpSupply.add(pool.extraAmount);
            if (blockReward[_i].plannedBlock > pool.lastRewardBlock && lpSupply != 0) {
                uint256 accStarPerShare = starReward.mul(1e12).div(lpSupply);
                pool.accStarPerShare = accStarPerShare;
                pool.lastRewardBlock = blockReward[_i].plannedBlock;
                return;
            }
        }
    }

    function addStarPerBlock() public onlyOwner {
        for(uint256 i; i < blockReward.length; i++){
            if(block.number >= blockReward[i].plannedBlock && starPerBlock < blockReward[i].plannedReward){
                updatePerBlock(i);
                break;
            }
        }
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. We trust that migrator contract is good.
    function migrate(uint256 _pid) public onlyOwner {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20Upgradeable lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20Upgradeable newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending STARs on frontend.
    function pendingStar(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accStarPerShare = pool.accStarPerShare;
        uint256 _amountpendingStar;
        if (block.number > pool.lastRewardBlock && pool.lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 starReward = multiplier.mul(starPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            uint256 lpSupply = pool.lpSupply.add(pool.extraAmount);
            accStarPerShare = accStarPerShare.add(starReward.mul(1e12).div(lpSupply));
            (uint256 _selfGain, uint256 _parentGain) = starNode.nodeGain(_user);
            uint256 _amountGain = user.amount.add(user.amount.mul(_selfGain.add(_parentGain)).div(100));
            _amountpendingStar = _amountGain.mul(accStarPerShare).div(1e12).sub(user.rewardDebt);
            if(_amountpendingStar > 0) {
                _amountpendingStar = _amountpendingStar.sub(_amountpendingStar.mul(lockRatio.add(teamRatio)).div(10000));
                _amountpendingStar = _amountpendingStar.sub(_amountpendingStar.mul(rewardRatio).div(10000));
                _amountpendingStar = _amountpendingStar.mul(100).div(_selfGain.add(_parentGain).add(100));
            }
        }
        return _amountpendingStar;
    }

    //View function to see pending STARs on frontend of nft.
    function nftPendingStar(address _user,uint256 _tokenId) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][_user];
        SlotInfo memory slot;
        slot.accStarPerShare = pool.accStarPerShare;
        slot.lpSupply = pool.lpSupply.add(pool.extraAmount);
        uint256 _amountpendingStar;
        if (block.number > pool.lastRewardBlock && slot.lpSupply != 0) {
            slot.multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            slot.starReward = slot.multiplier.mul(starPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            slot.accStarPerShare = slot.accStarPerShare.add(slot.starReward.mul(1e12).div(slot.lpSupply));
            (uint256 _selfGain, uint256 _parentGain) = starNode.nodeGain(_user);
            (, , uint256 _price, uint256 _multi) = nftLogic.starMeta(_tokenId);
            slot._amount = _price.mul(_multi).div(100);
            slot._amountGain = slot._amount.add(slot._amount.mul(_selfGain.add(_parentGain)).div(100));
            slot.nftAmount = user.nftAmount.add(user.nftAmount.mul(_selfGain.add(_parentGain)).div(100));
            slot.allNFTPendingStar = slot.nftAmount.mul(slot.accStarPerShare).div(1e12).sub(user.nftRewardDebt);
            _amountpendingStar = slot.allNFTPendingStar.mul(slot._amountGain).div(slot.nftAmount);
            if(_amountpendingStar > 0) {
                _amountpendingStar = _amountpendingStar.sub(_amountpendingStar.mul(lockRatio.add(teamRatio)).div(10000));
                _amountpendingStar = _amountpendingStar.sub(_amountpendingStar.mul(rewardRatio).div(10000));
                _amountpendingStar = _amountpendingStar.mul(100).div(_selfGain.add(_parentGain).add(100));
            }
        }
        return _amountpendingStar;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function reckon() public {
        uint256 len = blockReward.length;
        if(len == 0){
            return;
        }
        for(uint256 i; i < len; i++){
            if(block.number >= blockReward[i].plannedBlock && starPerBlock > blockReward[i].plannedReward){
                updatePerBlock(i);
                break;
            }
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        if (pool.lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        reckon();
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 starReward = multiplier.mul(starPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        uint256 lpSupply = pool.lpSupply.add(pool.extraAmount);
        pool.accStarPerShare = pool.accStarPerShare.add(starReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    function harvest(uint256 _pid, uint256 _amount, bool isNFT) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        (uint256 _selfGain, uint256 _parentGain) = starNode.nodeGain(_msgSender());
        uint256 _amountGain;
        uint256 pending;
        if(isNFT == false){
            _amountGain = user.amount.add(user.amount.mul(_selfGain.add(_parentGain)).div(100));
            pending = _amountGain.mul(pool.accStarPerShare).div(1e12).sub(user.rewardDebt);
        }else{
            _amountGain = user.nftAmount.add(user.nftAmount.mul(_selfGain.add(_parentGain)).div(100));
            pending = _amountGain.mul(pool.accStarPerShare).div(1e12).sub(user.nftRewardDebt);
        }
        if(pending > 0) {
            iToken.farmMint(address(this), pending);
            starToken.safeTransfer(lockAddr,pending.mul(lockRatio).div(10000));
            starToken.safeTransfer(teamAddr,pending.mul(teamRatio).div(10000));
            pending = pending.sub(pending.mul(lockRatio.add(teamRatio)).div(10000));
            starToken.safeTransfer(rewardAddr,pending.mul(rewardRatio).div(10000));
            pending = pending.sub(pending.mul(rewardRatio).div(10000));
            pending = pending.mul(100).div(_selfGain.add(_parentGain).add(100));
            uint256 withdrawAmount;
            if (user.lastDeposit > block.timestamp.sub(2592000) && isNFT == false) {
                uint256 fee = pending.mul(pool.fee).div(10000);
                withdrawAmount = (pending.sub(fee)).mul(_selfGain.add(100)).div(100);
                starToken.safeTransfer(_msgSender(), (pending.sub(fee)));
                starToken.safeTransfer(nodeAddr, (pending.sub(fee)).mul(_parentGain).div(100));
                starToken.safeTransfer(nodeAddr, (pending.sub(fee)).mul(_selfGain).div(100));
                starNode.settleNode(_msgSender(), (pending.sub(fee)).mul(_parentGain).div(100), (pending.sub(fee)).mul(_selfGain).div(100));
                if(pool.fee > 0){
                    starToken.safeTransfer(lockAddr, fee.mul(Bonus.getlockRatio()).div(100));
                    uint256 amountBonus = fee.sub(fee.mul(Bonus.getlockRatio()).div(100));
                    starToken.safeTransfer(bonusAddr, amountBonus);
                    Bonus.addTotalAmount(amountBonus);
                }
            }else{
                withdrawAmount = pending;
                starToken.safeTransfer(_msgSender(), pending);
                starToken.safeTransfer(nodeAddr, pending.mul(_parentGain).div(100));
                starToken.safeTransfer(nodeAddr, pending.mul(_selfGain).div(100));
                starNode.settleNode(_msgSender(), pending.mul(_parentGain).div(100), pending.mul(_selfGain).div(100));
            }
            emit Withdraw(_msgSender(), _pid, withdrawAmount, isNodeUser[_msgSender()], _amount);
        }
    }

    // Deposit LP tokens to MasterChef for STAR allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        updatePool(_pid);
        harvest(_pid, 0, false);
        if(startBlock == 0){
            startBlock = block.number;
        }
        (uint256 _selfGain, uint256 _parentGain) = starNode.nodeGain(_msgSender());
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(_msgSender(), address(this), _amount);
            user.amount = user.amount.add(_amount);
            user.lastDeposit = block.timestamp;
            uint256 _extraAmount = _amount.mul(_selfGain.add(_parentGain)).div(100);
            pool.extraAmount = pool.extraAmount.add(_extraAmount);
            pool.lpSupply = pool.lpSupply.add(_amount);
            if(isPoolUser[_pid][_msgSender()] == false){
                userIndex[_pid][pool.size] = _msgSender();
                pool.size = pool.size.add(1);
                isPoolUser[_pid][_msgSender()] = true;
            }
            Airdrop.setUser(_msgSender(),1);
        }
        uint256 _amountGain = user.amount.add(user.amount.mul(_selfGain.add(_parentGain)).div(100));
        user.rewardDebt = _amountGain.mul(pool.accStarPerShare).div(1e12);
        emit Deposit(_msgSender(), _pid, _amount, isNodeUser[_msgSender()]);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        require(user.amount >= _amount, "withdraw: amount error");
        updatePool(_pid);
        harvest(_pid, _amount, false);
        (uint256 _selfGain, uint256 _parentGain) = starNode.nodeGain(_msgSender());
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            uint256 _extraAmount = _amount.mul(_selfGain.add(_parentGain)).div(100);
            pool.extraAmount = pool.extraAmount.sub(_extraAmount);
            pool.lpSupply = pool.lpSupply.sub(_amount);
            pool.lpToken.safeTransfer(_msgSender(), _amount);
        }
        uint256 _amountGain = user.amount.add(user.amount.mul(_selfGain.add(_parentGain)).div(100));
        user.rewardDebt = _amountGain.mul(pool.accStarPerShare).div(1e12);
    }

    // Stake Star NFT to MasterChef
    function enterStakingNFT(uint256 _tokenId) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][_msgSender()];
        require(starNFT.ownerOf(_tokenId) == _msgSender(), "error NFT user");
        updatePool(0);
        (uint256 _selfGain, uint256 _parentGain) = starNode.nodeGain(_msgSender());
        harvest(0, 0, true);
        if (_tokenId > 0) {
            starNFT.transferFrom(_msgSender(), address(this), _tokenId);
            (uint256 level, , uint256 _price, uint256 _multi) = nftLogic.starMeta(_tokenId);
            userNFTs[_msgSender()].push(_tokenId);
            StakingNFTs.push(_tokenId);
            StakingIndex[_tokenId] = StakingNFTs.length - 1;
            NFTGroup[level].push(_tokenId);
            groupIndex[level][_tokenId] = NFTGroup[level].length - 1;
            nftUser[_tokenId] = _msgSender();
            uint256 _amount = _price.mul(_multi).div(100);
            uint256 _extraAmount = _amount.mul(_selfGain.add(_parentGain)).div(100);
            pool.extraAmount = pool.extraAmount.add(_extraAmount);
            pool.lpSupply = pool.lpSupply.add(_amount);
            user.nftAmount = user.nftAmount.add(_amount);
            user.nftLastDeposit = block.timestamp;
            if(isPoolUser[0][_msgSender()] == false){
                userIndex[0][pool.size] = _msgSender();
                pool.size = pool.size.add(1);
                isPoolUser[0][_msgSender()] = true;
            }
        }
        uint256 _amountGain = user.nftAmount.add(user.nftAmount.mul(_selfGain.add(_parentGain)).div(100));
        user.nftRewardDebt = _amountGain.mul(pool.accStarPerShare).div(1e12);
        emit Deposit(_msgSender(), 0, _tokenId, isNodeUser[_msgSender()]);
    }

    // Withdraw Star NFT from STAKING.
    function leaveStakingNFT(uint256 _tokenId) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][_msgSender()];
        require(userNFTs[_msgSender()].length > 0, "no NFT");
        updatePool(0);
        (uint256 _selfGain, uint256 _parentGain) = starNode.nodeGain(_msgSender());
        uint256 _self_parentGain = _selfGain.add(_parentGain);
        uint256 _amount;
        if (_tokenId > 0) {
            require(nftUser[_tokenId] == _msgSender(), "error NFT user");
            (, , uint256 _price, uint256 _multi) = nftLogic.starMeta(_tokenId);
            _amount = _price.mul(_multi).div(100);
        }
        harvest(0, _amount, true);
        if (_tokenId > 0) {
            uint256[] storage _userNFTs = userNFTs[_msgSender()];
            for (uint256 i = 0; i < _userNFTs.length; i++) {
                if(_userNFTs[i] == _tokenId) {
                    if(_amount > 0) {
                        (uint256 level, , ,) = nftLogic.starMeta(_tokenId);
                        uint256 _extraAmount = _amount.mul(_self_parentGain).div(100);
                        pool.extraAmount = pool.extraAmount.sub(_extraAmount);
                        pool.lpSupply = pool.lpSupply.sub(_amount);
                        user.nftAmount = user.nftAmount.sub(_amount);
                        _userNFTs[i] = _userNFTs[_userNFTs.length - 1];
                        _userNFTs.pop();
                        uint256 indexd = StakingIndex[_tokenId];
                        StakingNFTs[indexd] = StakingNFTs[StakingNFTs.length - 1];
                        StakingIndex[StakingNFTs[indexd]] = indexd;
                        StakingIndex[_tokenId] = 0;
                        StakingNFTs.pop();
                        uint256 groupIndexd = groupIndex[level][_tokenId];
                        NFTGroup[level][groupIndexd] = NFTGroup[level][NFTGroup[level].length - 1];
                        groupIndex[level][NFTGroup[level][groupIndexd]] = groupIndexd;
                        groupIndex[level][_tokenId] = 0;
                        NFTGroup[level].pop();
                        nftUser[_tokenId] = address(0);
                    }
                    starNFT.transferFrom(address(this), _msgSender(), _tokenId);
                    break;
                }
            }
        }
        uint256 _amountGain = user.nftAmount.add(user.nftAmount.mul(_self_parentGain).div(100));
        user.nftRewardDebt = _amountGain.mul(pool.accStarPerShare).div(1e12);
    }

    function getNFTGroupAmount(uint256 _level) view public returns(uint256) {
        return NFTGroup[_level].length;
    }

    function getUserStakingNFTAmount(address _user) view public returns (uint256) {
        return userNFTs[_user].length;
    }

    function getStakingNFTAmount() view public returns (uint256) {
        return StakingNFTs.length;
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        pool.lpToken.safeTransfer(_msgSender(), user.amount);
        emit EmergencyWithdraw(_msgSender(), _pid, user.amount, isNodeUser[_msgSender()]);
        uint256 nftLength = userNFTs[_msgSender()].length;
        for(uint256 i = 0; i < nftLength; i++){
            leaveStakingNFT(userNFTs[_msgSender()][i]);
        }
        (uint256 _selfGain, uint256 _parentGain) = starNode.nodeGain(_msgSender());
        uint256 _extraAmount = user.amount.mul(_selfGain.add(_parentGain)).div(100);
        pool.extraAmount = pool.extraAmount.sub(_extraAmount);
        pool.lpSupply = pool.lpSupply.sub(user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    function getAllocationInfo() view public returns(address ,address ,address ,uint256 ,uint256 ,uint256 ) {
        return (lockAddr,teamAddr,rewardAddr,lockRatio,teamRatio,rewardRatio);
    }

    function setAllocationInfo(address _lockAddr,address _teamAddr,address _rewardAddr,uint256 _lockRatio,uint256 _teamRatio,uint256 _rewardRatio) public onlyOwner {
        lockAddr = _lockAddr;
        teamAddr = _teamAddr;
        rewardAddr = _rewardAddr;
        lockRatio = _lockRatio;
        teamRatio = _teamRatio;
        rewardRatio = _rewardRatio;
    }

    function setStarNFT(address _addr) external onlyOwner {
        require(address(0) != _addr, "NFT address can not be address 0");
        starNFT = IERC721Upgradeable(_addr);
    }

    function regNodeUser(address _user) external onlyNode {
        require(address(0) != _user, '');
        for(uint256 i = 0; i < poolInfo.length; i++){
            UserInfo storage user = userInfo[i][_user];
            updatePool(i);
            uint256 _amount = user.amount.add(user.nftAmount);
            if(_amount > 0) {
                (uint256 _selfGain, uint256 _parentGain) = starNode.nodeGain(_user);
                uint256 _extraAmount = _amount.mul(_selfGain.add(_parentGain)).div(100);
                poolInfo[i].extraAmount = poolInfo[i].extraAmount.add(_extraAmount);
                uint256 _amountGain = user.amount.add(user.amount.mul(_selfGain.add(_parentGain)).div(100));
                uint256 pending = user.amount.mul(poolInfo[i].accStarPerShare).div(1e12).sub(user.rewardDebt);
                user.rewardDebt = _amountGain.mul(poolInfo[i].accStarPerShare).div(1e12).sub(pending);
                if(i == 0){
                    uint256 _nftAmountGain = user.nftAmount.add(user.nftAmount.mul(_selfGain.add(_parentGain)).div(100));
                    uint256 nftpending = user.nftAmount.mul(poolInfo[i].accStarPerShare).div(1e12).sub(user.nftRewardDebt);
                    user.nftRewardDebt = _nftAmountGain.mul(poolInfo[i].accStarPerShare).div(1e12).sub(nftpending);
                }
            }
        }
        isNodeUser[_user] = true;
    }

    function getLockAddr() view public returns(address){
        return lockAddr;
    }

    function getUserNFTs(address _user) view external returns(uint256[] memory){
        return userNFTs[_user];
    }

    function setNode(address _node) public onlyOwner {
        require(address(0) != _node, 'node can not be address 0');
        nodeAddr = _node;
        starNode = IStarNode(_node);
    }

    function setNFTLogic(address _addr) external onlyOwner {
        require(address(0) != _addr, "logic address can not be address 0");
        nftLogic = INFTLogic(_addr);
    }

    function setBonus(address _addr) external onlyOwner {
        require(address(0) != _addr, "bonus address can not be address 0");
        bonusAddr = _addr;
    }

    function setAirdrop(address _addr) external onlyOwner {
        require(address(0) != _addr, "bonus address can not be address 0");
        Airdrop = IAirdrop(_addr);
    }

    function setToken(address _tokenaddr) public onlyOwner {
        starToken = IERC20Upgradeable(_tokenaddr);
        iToken = IStarToken(_tokenaddr);
		poolInfo[0].lpToken = IERC20Upgradeable(_tokenaddr);
    }

    modifier onlyNode() {
        require(_msgSender() == address(starNode), "not node");
        _;
    }
}