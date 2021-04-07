// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./PotatoToken.sol";

// MasterChef is the master of POTATO. He can make POTATO and he is a fair guy. But he doesn't like to eat potato :(
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once POTATO is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

	// Copied and modified from Goose code:
    // https://github.com/goosedefi/goose-contracts/blob/master/contracts/MasterChefV2.sol
	
    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of PTTs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accPotatoPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accPotatoPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. PTTs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that Ptts distribution occurs.
        uint256 accPotatoPerShare;   // Accumulated PTTs per share, times minDec. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }

    // The POTATO TOKEN!
    PotatoToken public POTATO;
    // Dev address.
    address public devaddr;
	// POTATO tokens created per block.
    uint256 public initPotatoPerBlock;
    // Deposit Fee address
    address public feeTreasuryAddress;
	address public feeBuyBackAddress;
	address public feeDevAddress;
	
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when POTATO mining starts.
    uint256 public startBlock;
	//min decimal for user
	uint256 constant minDec = 1e12;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetTreasuryFeeAddress(address indexed user, address indexed newAddress);
	event SetBuyBackFeeAddress(address indexed user, address indexed newAddress);
	event SetDevFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 goosePerBlock);

    constructor(
        address _potatoAddress,
        address _devaddr,
        address _feeTreasuryAddress,
		address _feeBuyBackAddress,
		address _feeDevAddress,
        uint256 _initPotatoPerBlock,
        uint256 _startBlock
    ) public {
        POTATO = PotatoToken(_potatoAddress);
        devaddr = _devaddr;
        feeTreasuryAddress = _feeTreasuryAddress;
		feeBuyBackAddress = _feeBuyBackAddress;
		feeDevAddress = _feeDevAddress;
		initPotatoPerBlock = _initPotatoPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IBEP20 => bool) public poolExistence;
    modifier nonDuplicated(IBEP20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken) {
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accPotatoPerShare : 0,
        depositFeeBP : _depositFeeBP
        }));
    }

    // Update the given pool's POTATO allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
		//60*60*24/3 = 28800
		if((block.number - startBlock)/28800 > 2) return _to.sub(_from);
		//second day *2 bonus
		if((block.number - startBlock)/28800 > 1) return _to.sub(_from).mul(2);
		//first day *3 bonus
        return _to.sub(_from).mul(3);
    }
	
	//60*60*24*7 / 3 = 201600
	function getWeeksFromStart() public view returns(uint256){
	    return (block.number - startBlock)/201600;
	}
    
	// Deflactionary System -5% minted token every week
	function getPotatoPerBlock()public view returns(uint256){
		uint curWeek = getWeeksFromStart();
		uint potatoPerBlock = initPotatoPerBlock;
	    for (uint256 i = 0; i < curWeek; i++) {
            potatoPerBlock = potatoPerBlock.div(20).mul(19);
        }
		return potatoPerBlock;
	}

    // View function to see pending POTATO on frontend.
    function pendingPotato(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPotatoPerShare = pool.accPotatoPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 potatoReward = multiplier.mul(getPotatoPerBlock()).mul(pool.allocPoint).div(totalAllocPoint);
            accPotatoPerShare = accPotatoPerShare.add(potatoReward.mul(minDec).div(lpSupply));
        }
        return user.amount.mul(accPotatoPerShare).div(minDec).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 potatoReward = multiplier.mul(getPotatoPerBlock()).mul(pool.allocPoint).div(totalAllocPoint);
        POTATO.mint(devaddr, potatoReward.div(20));
		POTATO.mint(feeDevAddress, potatoReward.div(20));
        POTATO.mint(address(this), potatoReward);
        pool.accPotatoPerShare = pool.accPotatoPerShare.add(potatoReward.mul(minDec).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for POTATO allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
		require(poolInfo.length > _pid, "pool: not exist");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accPotatoPerShare).div(minDec).sub(user.rewardDebt);
            if (pending > 0) {
                safePotatoTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeBuyBackAddress, depositFee.mul(4).div(10));
				pool.lpToken.safeTransfer(feeTreasuryAddress, depositFee.mul(3).div(10));
				pool.lpToken.safeTransfer(feeDevAddress, depositFee.mul(3).div(10));
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accPotatoPerShare).div(minDec);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accPotatoPerShare).div(minDec).sub(user.rewardDebt);
        if (pending > 0) {
            safePotatoTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPotatoPerShare).div(minDec);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe potato transfer function, just in case if rounding error causes pool to not have enough potato.
    function safePotatoTransfer(address _to, uint256 _amount) internal {
        uint256 potatoBal = POTATO.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > potatoBal) {
            transferSuccess = POTATO.transfer(_to, potatoBal);
        } else {
            transferSuccess = POTATO.transfer(_to, _amount);
        }
        require(transferSuccess, "safePotatoTransfer: transfer failed");
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

	function setFeeTreasuryAddressAddress(address _feeAddress) public{
        require(msg.sender == feeTreasuryAddress, "setFeeAddress: FORBIDDEN");
        feeTreasuryAddress = _feeAddress;
		emit SetTreasuryFeeAddress(msg.sender, _feeAddress);
    }
	
	function setFeeBuyBackAddressAddress(address _feeAddress) public{
        require(msg.sender == feeBuyBackAddress, "setFeeAddress: FORBIDDEN");
        feeBuyBackAddress = _feeAddress;
		emit SetBuyBackFeeAddress(msg.sender, _feeAddress);
    }
	
	function setFeeDevAddressAddress(address _feeAddress) public{
        require(msg.sender == feeDevAddress, "setFeeAddress: FORBIDDEN");
        feeDevAddress = _feeAddress;
		emit SetDevFeeAddress(msg.sender, _feeAddress);
    }

    function updateEmissionRate(uint256 _potatoPerBlock) public onlyOwner {
        massUpdatePools();
        initPotatoPerBlock = _potatoPerBlock;
        emit UpdateEmissionRate(msg.sender, _potatoPerBlock);
    }
}