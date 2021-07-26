pragma solidity ^0.8.0;

import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./openzeppelin/contracts/security/Pausable.sol";
contract SingleTokenPool is Ownable,Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    address public rewardToken; 
    uint256 public totalReward;
    uint256 public totalClaimedReward;
    uint256 public totalClaimedLock;
    uint256 public totalLockAmount;
    address public lockToken;
    uint256 public lockLimitAmount;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public lastRewardTime;
    uint256 public rewardPerLock;
    mapping(address=>UserInfo) public userInfo;
    struct UserInfo{
        uint256 lockAmount;
        uint256 rewardDebt;
        uint256 pendingReward;
    }
    constructor (address _lockToken, address _rewardToken,uint256 _lockLimitAmount,uint256 _totalReward,uint256 _startTime,uint256 _lockDays) {

        require(_lockToken != address(0), "invalid lock token");
        require(_rewardToken != address(0), "invalid reward token");
        lockToken = _lockToken;
        rewardToken = _rewardToken;
        lockLimitAmount = _lockLimitAmount;
        totalReward = _totalReward;
        startTime = _startTime;
        lastRewardTime = _startTime;
        uint256 currentTime = block.timestamp;
        require(startTime==0||startTime>=currentTime,"start time must over now!");
        if (_lockDays>0&&startTime>0){
            endTime = startTime.add(86400*_lockDays);
        }
    }
    function setSetting(uint256 _lockLimitAmount,uint256 _totalReward,uint256 _startTime,uint256 _lockDays) external onlyOwner{
        uint256 currentTime = block.timestamp;

        if(_totalReward>0){
            require(startTime==0||startTime>currentTime,"The activity has begun!");
            totalReward = _totalReward;
        }
        if(_startTime>0){
            require(startTime==0||(startTime>currentTime&&_startTime>currentTime&&_lockDays>0),"invalid start time!");
            startTime = _startTime;
            lastRewardTime = _startTime;
        }
        if (_lockDays>0){
            require(startTime>0&&startTime>currentTime,"The activity has begun!");
            endTime = startTime.add(86400*_lockDays);
        }
        if (_lockLimitAmount>0){
            lockLimitAmount = _lockLimitAmount;
        }
    }
    function lock(uint256 _amount) external{
        uint256 currentTime = block.timestamp;
        require(startTime > 0,"no start time!");
        require(currentTime<endTime,"The activity has finished!");
        if (lockLimitAmount>0){
            require(totalLockAmount.add(_amount)<=lockLimitAmount,"exceed lock limit amount!");
        }
        UserInfo storage _user= userInfo[msg.sender];

        updatePool();
        if (_user.lockAmount>0){
            uint256 _pending = _user.lockAmount.mul(rewardPerLock).div(10**12).sub(_user.rewardDebt);
            if (_pending>0){
                _user.pendingReward = _user.pendingReward.add(_pending);
            }
        }
        if (_amount>0){
            IERC20(lockToken).safeTransferFrom(msg.sender,address(this),_amount);
            _user.lockAmount = _user.lockAmount.add(_amount);
            totalLockAmount = totalLockAmount.add(_amount);
        }
        _user.rewardDebt = _user.lockAmount.mul(rewardPerLock).div(10**12);
    }
    function unLock() external{
        updatePool();
        uint256 currentTime = block.timestamp;
        require(currentTime > endTime,"The activity is not over");
        UserInfo storage _user= userInfo[msg.sender];
        uint256 _pending = _user.lockAmount.mul(rewardPerLock).div(10**12).sub(_user.rewardDebt);
        uint256 _reward = _user.pendingReward.add(_pending);
        if (_user.lockAmount>0){
            IERC20(lockToken).safeTransfer(msg.sender,_user.lockAmount);
        }
        if (_reward>0){
            uint256 _balance = IERC20(rewardToken).balanceOf(address(this));
            require(_balance>=_reward,"not enough balance!");
            totalClaimedReward = totalClaimedReward.add(_reward);
            totalClaimedLock = totalClaimedLock.add(_user.lockAmount);


        }
        delete userInfo[msg.sender];
        IERC20(rewardToken).safeTransfer(msg.sender,_reward);
    }

    function emergencyWithdraw() external{
        require(currentTime > endTime,"The activity is not over");
        UserInfo storage _user= userInfo[msg.sender];
        require(_user.lockAmount>0,"haven't stake!");
        IERC20(lockToken).safeTransfer(msg.sender,_user.lockAmount);
        delete userInfo[msg.sender];
    }
    function pendingReward(address _address) public view returns(uint256){
        UserInfo memory _user= userInfo[_address];
        uint256 currentTime = block.timestamp;
        if (currentTime<=startTime||startTime==0||endTime==0){
            return 0;
        }
        uint256 _endTime = currentTime>endTime?endTime:currentTime;
        uint256 _totalTimes = _endTime.sub(startTime);
        uint256 _rewardPerLock =rewardPerLock.add(getRewardPerTime().mul(_totalTimes).div(totalReward));
        return _user.lockAmount.mul(_rewardPerLock).div(10**12).add(_user.pendingReward).sub(_user.rewardDebt);
    }

    function getRewardPerTime() public view returns(uint256){
        if (endTime==0){
            return 0;
        }
        return totalReward.mul(10**12).div(endTime.sub(startTime));
    }
    function updatePool() public{
        uint256 currentTime = block.timestamp;
        if (currentTime<=lastRewardTime){
            return;
        }
        if (totalLockAmount==0){
            lastRewardTime = currentTime;
            return;
        }
        uint256 _endTime = currentTime>endTime?endTime:currentTime;
        uint256 _totalTimes = _endTime.sub(lastRewardTime);
        rewardPerLock =rewardPerLock.add(getRewardPerTime().mul(_totalTimes).div(totalReward));
        lastRewardTime = currentTime;
    }
}
