
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
interface DepToken{
    function mint(address _to, uint256 _amount) external;
}
contract BDepMining is Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
        uint256 pendingReward;
        bool unStakeBeforeEnableClaim;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. DepTokens to distribute per block.
        uint256 lastRewardBlock;  // Last block number that DepTokens distribution occurs.
        uint256 accDepPerShare; // Accumulated DepTokens per share, times 1e12. See below.
        uint256 totalDeposit ;      // Accumulated deposit tokens.

    }

    // The DepToken !
    address public Dep;

    // Dev address.
    address public devAddr;

    // Percentage of developers mining
    uint256 public devMiningRate;

    // Dep tokens created per block.
    uint256 public DepPerBlock;

    // The block number when WPC mining starts.
    uint256 public startBlock;

    // The block number when WPC claim starts.
    uint256 public enableClaimBlock;

    // Interval blocks to reduce mining volume.
    uint256 public reduceIntervalBlock;

    // reduce rate
    uint256 public reduceRate;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(uint256 => address[]) public userAddresses;
    mapping(uint256 => mapping(address => uint)) private userPoolAddresses;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    event Stake(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid);
    event UnStake(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event ReplaceMigrate(address indexed user, uint256 pid, uint256 amount);
    event Migrate(address indexed user, uint256 pid, uint256 targetPid, uint256 amount);

    constructor (
        address _Dep,
        address _devAddr,
        uint256 _DepPerBlock,
        uint256 _startBlock,
        uint256 _enableClaimBlock,
        uint256 _reduceIntervalBlock,
        uint256 _reduceRate,
        uint256 _devMiningRate
    ) public {
        Dep = _Dep;
        devAddr = _devAddr;
        DepPerBlock = _DepPerBlock;
        startBlock = _startBlock;
        reduceIntervalBlock = _reduceIntervalBlock;
        reduceRate = _reduceRate;
        devMiningRate = _devMiningRate;
        enableClaimBlock = _enableClaimBlock;

        //totalAllocPoint = 0;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function usersLength(uint256 _pid) external view returns (uint256) {
        return userAddresses[_pid].length;
    }

    // Update dev address by the previous dev.
    function setDevAddr(address _devAddr) public onlyOwner {
        devAddr = _devAddr;
    }



    // set the enable claim block
    function setEnableClaimBlock(uint256 _enableClaimBlock) public onlyOwner {
        enableClaimBlock = _enableClaimBlock;
    }

    // update reduceIntervalBlock
    function setReduceIntervalBlock(uint256 _reduceIntervalBlock, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        reduceIntervalBlock = _reduceIntervalBlock;
    }

    // Update the given pool's Dep allocation point. Can only be called by the owner.
    function setAllocPoint(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        //update totalAllocPoint
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);

        //update poolInfo
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // update reduce rate
    function setReduceRate(uint256 _reduceRate, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        reduceRate = _reduceRate;
    }

    // update dev mining rate
    function setDevMiningRate(uint256 _devMiningRate) public onlyOwner {
        devMiningRate = _devMiningRate;
    }


    // Return DepPerBlock, baseOn power  --> DepPerBlock * (reduceRate/1000)^power
    function getDepPerBlock(uint256 _power) public view returns (uint256){
        if (_power == 0) {
            return DepPerBlock;
        } else {
            uint256 z = DepPerBlock;
            for (uint256 i = 0; i < _power; i++) {
                z = z.mul(reduceRate).div(1000);
            }
            return z;
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see all pending DepToken on frontend.
    function allPendingDep(address _user) external view returns (uint256){
        uint sum = 0;
        for (uint i = 0; i < poolInfo.length; i++) {
            sum = sum.add(_pending(i, _user));
        }
        return sum;
    }

    // View function to see pending DepToken on frontend.
    function pendingDep(uint256 _pid, address _user) external view returns (uint256) {
        return _pending(_pid, _user);
    }

    //internal function
    function _pending(uint256 _pid, address _user) internal view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accDepPerShare = pool.accDepPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            // pending Dep reward
            uint256 DepReward = 0;
            uint256 lastRewardBlockPower = pool.lastRewardBlock.sub(startBlock).div(reduceIntervalBlock);
            uint256 blockNumberPower = block.number.sub(startBlock).div(reduceIntervalBlock);

            // get DepReward from pool.lastRewardBlock to block.number.
            // different interval different multiplier and DepPerBlock, sum DepReward
            if (lastRewardBlockPower == blockNumberPower) {
                uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
                DepReward = DepReward.add(multiplier.mul(getDepPerBlock(blockNumberPower)).mul(pool.allocPoint).div(totalAllocPoint));
            } else {
                for (uint256 i = lastRewardBlockPower; i <= blockNumberPower; i++) {
                    uint256 multiplier = 0;
                    if (i == lastRewardBlockPower) {
                        multiplier = getMultiplier(pool.lastRewardBlock, startBlock.add(lastRewardBlockPower.add(1).mul(reduceIntervalBlock)).sub(1));
                    } else if (i == blockNumberPower) {
                        multiplier = getMultiplier(startBlock.add(blockNumberPower.mul(reduceIntervalBlock)), block.number);
                    } else {
                        multiplier = reduceIntervalBlock;
                    }
                    DepReward = DepReward.add(multiplier.mul(getDepPerBlock(i)).mul(pool.allocPoint).div(totalAllocPoint));
                }
            }

            accDepPerShare = accDepPerShare.add(DepReward.mul(1e12).div(lpSupply));
        }

        // get pending value
        uint256 pendingValue = user.amount.mul(accDepPerShare).div(1e12).sub(user.rewardDebt);

        // if enableClaimBlock after block.number, return pendingValue + user.pendingReward.
        // else return pendingValue.
        if (enableClaimBlock > block.number) {
            return pendingValue.add(user.pendingReward);
        } else if (user.pendingReward > 0 && user.unStakeBeforeEnableClaim) {
            return pendingValue.add(user.pendingReward);
        }
        return pendingValue;
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
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        // get DepReward. DepReward base on current DepPerBlock.
        uint256 power = block.number.sub(startBlock).div(reduceIntervalBlock);
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 DepReward = multiplier.mul(getDepPerBlock(power)).mul(pool.allocPoint).div(totalAllocPoint);

        // mint
        DepToken(Dep).mint(devAddr, DepReward.mul(devMiningRate).div(100));
        DepToken(Dep).mint(address(this), DepReward);

        //update pool
        pool.accDepPerShare = pool.accDepPerShare.add(DepReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;

    }

    // Add a new lp to the pool. Can only be called by the owner.
    // DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        require(address(_lpToken) != address(0), "lp token is the zero address");
        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;

        //update totalAllocPoint
        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        // add poolInfo
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accDepPerShare : 0,
        totalDeposit : 0
        }));
    }

    // Stake LP tokens to DepBreeder for WPC allocation.
    function stake(uint256 _pid, uint256 _amount) public {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        //update poolInfo by pid
        updatePool(_pid);

        // if user's amount bigger than zero, transfer DepToken to user.
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accDepPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                // if enableClaimBlock after block.number, save the pending to user.pendingReward.
                if (enableClaimBlock <= block.number) {
                    IERC20(Dep).safeTransfer(msg.sender, pending);

                    // transfer user.pendingReward if user.pendingReward > 0, and update user.pendingReward to 0
                    if (user.pendingReward > 0) {
                        IERC20(Dep).safeTransfer(msg.sender, user.pendingReward);
                        user.pendingReward = 0;
                    }
                } else {
                    user.pendingReward = user.pendingReward.add(pending);
                }
            }
        }

        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.totalDeposit = pool.totalDeposit.add(_amount);
            uint hasAddress = userPoolAddresses[_pid][msg.sender];
            if (hasAddress==0){
                userPoolAddresses[_pid][msg.sender]=1;
                userAddresses[_pid].push(msg.sender);
            }
        }

        user.rewardDebt = user.amount.mul(pool.accDepPerShare).div(1e12);

        emit Stake(msg.sender, _pid, _amount);

    }

    // UnStake LP tokens from DepBreeder.
    function unStake(uint256 _pid, uint256 _amount) public {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "unStake: not good");

        //update poolInfo by pid
        updatePool(_pid);

        //transfer DepToken to user.
        uint256 pending = user.amount.mul(pool.accDepPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            // if enableClaimBlock after block.number, save the pending to user.pendingReward.
            if (enableClaimBlock <= block.number) {
                IERC20(Dep).safeTransfer(msg.sender, pending);

                // transfer user.pendingReward if user.pendingReward > 0, and update user.pendingReward to 0
                if (user.pendingReward > 0) {
                    IERC20(Dep).safeTransfer(msg.sender, user.pendingReward);
                    user.pendingReward = 0;
                }
            } else {
                user.pendingReward = user.pendingReward.add(pending);
                user.unStakeBeforeEnableClaim = true;
            }
        }

        if (_amount > 0) {
            // transfer LP tokens to user
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            // update user info
            user.amount = user.amount.sub(_amount);
            pool.totalDeposit = pool.totalDeposit.sub(_amount);
        }

        user.rewardDebt = user.amount.mul(pool.accDepPerShare).div(1e12);

        emit UnStake(msg.sender, _pid, _amount);
    }

    // claim WPC
    function claim(uint256 _pid) public {

        require(enableClaimBlock <= block.number, "too early to claim");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        //update poolInfo by pid
        updatePool(_pid);

        // if user's amount bigger than zero, transfer DepToken to user.
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accDepPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                IERC20(Dep).safeTransfer(msg.sender, pending);
            }
        }

        // transfer user.pendingReward if user.pendingReward > 0, and update user.pendingReward to 0
        if (user.pendingReward > 0) {
            IERC20(Dep).safeTransfer(msg.sender, user.pendingReward);
            user.pendingReward = 0;
        }

        // update user info
        user.rewardDebt = user.amount.mul(pool.accDepPerShare).div(1e12);

        emit Claim(msg.sender, _pid);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 amount = user.amount;
        // update user info
        user.amount = 0;
        user.rewardDebt = 0;
        // transfer LP tokens to user
        pool.lpToken.safeTransfer(address(msg.sender), amount);

        pool.totalDeposit = pool.totalDeposit.sub(amount);


        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }


}