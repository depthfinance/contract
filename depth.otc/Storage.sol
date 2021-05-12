
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IDepth.sol";


/**
 * @title OtcV1: Simple otc swap v1
 * @notice https://www.depth.fi/
 */
contract OtcStorage is  Ownable {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  bool isPaused;
  mapping (address=>bool) otcContracts;//ony in this list can call saveMoney function


  uint256 public totalTradeAmount;//total trade amount by husd
  uint256 public totalFeeAmount;//total fee amount by husd;
  uint256 public totalAvailableFeeAmount;//total available fee amount by husd;
  uint256 public totalRewardTokenAmount;//total dep amount
  uint256 public totalClaimedTokenAmount; //total claimed dep amount by users;
  uint256 public lastRewardTimeKey;//recent time key to reward depth.if reward action has done.will update this value to currentTimeKey;
  uint256 public currentTimeKey;//current time key to record trading amount info
  uint256[] public timeKeys; //all pool time keys
  address[2][] public whitePairList;//in this list can suppport mining dep


  struct PoolTimeKeyInfo{
      uint256 tradeAmount;
      uint256 feeAmount;
      uint256 availableFeeAmount;
      uint256 rewardTokenAmount; //has reward depth token
      uint256 claimedTokenAmount; //has claimed depth token
      uint256 claimedAvailbleFeeAmount;//if claimedAvailbleFeeAmount==availableFeeAmount .all users has claimed rewards
      bool flag ;//check the pool is existed;

  }
  struct UserTimeKeyInfo{
      uint256 availableTradeAmount;
      uint256 availableFeeAmount;

  }

  mapping (uint256=>PoolTimeKeyInfo) public poolTimeKeyInfo; //pool info storaged by timekey
  mapping (address=>uint256[]) public userNoClaimedTimes;
  mapping (address=>mapping(uint256=>UserTimeKeyInfo)) public userNoClaimedTimeKeyInfo;
  address public depthStakeAddress;
  uint256 public depthStakePoolId;
  address public daoAddress;
  address public depTokenAddress;


  constructor(uint256 _timeKey,address _depthStakeAddress,uint256 _depthStakePoolId,address _daoAddress,address _depTokenAddress) public {
    if (_timeKey==0){
        lastRewardTimeKey = getTimeKey();
    }else{
        lastRewardTimeKey = _timeKey;
    }
    depthStakeAddress = _depthStakeAddress; //can set zero .and then set it in stakeLpToken function
    depthStakePoolId= _depthStakePoolId;//can set zero .and then set it in stakeLpToken function
    daoAddress = _daoAddress;
    depTokenAddress=_depTokenAddress;
  }

  //get time key by current time
  function getTimeKey() internal view returns(uint256){
      uint256 _timeKey =block.timestamp/86400*86400+86400;
      if (_timeKey<lastRewardTimeKey){
          return lastRewardTimeKey;
      }
      else{
          return _timeKey;
      }
  }


// set contract paused or not
  function setPaused(bool b)   external onlyOwner{
      isPaused = b ;
  }

  //set depth stake address and stake lp token .
  function stakeLpToken(address _address,uint256 _poolId)   external onlyOwner{

       depthStakePoolId= _poolId;
      //set depth start mining block and otc pool start mining block
       require(_address!=address(0),"invalid address");
       depthStakeAddress=_address;
       stakeContract _stake= stakeContract(depthStakeAddress);
      //get depth stake pool info
      (address _lpToken,,,,,) =_stake.poolInfo(depthStakePoolId);
      require(_lpToken!=address(0),"invalid lp token address");

      //get balance of lp token
      uint256 balance = IERC20(_lpToken).balanceOf(address(this));
      IERC20(_lpToken).approve(depthStakeAddress,balance);
      //start to stake
      require(balance>0,"invalid lp token balance");
      stakeContract(depthStakeAddress).stake(depthStakePoolId,balance) ;
  }
  //set depth dao address
  function setDaoAddress(address _address)   external onlyOwner{
      if (_address!=address(0)){
        daoAddress = _address;
      }
  }
  //set depth token address
  function setDepTokenAddress(address _address)   external onlyOwner{
      if (_address!=address(0)){
        depTokenAddress = _address;
      }
  }




  function addOtcContract(address _address) external onlyOwner {
    otcContracts[_address] = true;
  }

  function removeOtcContract(address _address) external onlyOwner {
    if (otcContracts[_address] ){
        delete otcContracts[_address];
    }
  }

//set firstTokenAllocTimeKey
  function setLastTokenRewardTimeKey(uint256 _time) external onlyOwner{
    //if has totalTradeAmount.can not set firstTokenAllocTimeKey
    require(totalTradeAmount==0,"has trade amount.can not set");
    if (_time==0){
        lastRewardTimeKey = getTimeKey();
    }else{
        lastRewardTimeKey = _time;
    }
  }



    //delete has claimed all depth pool by time key.must next has allocated depth token.
    function deletePool(uint256 timeKey)   external onlyOwner{
        PoolTimeKeyInfo memory _poolInfo = poolTimeKeyInfo[timeKey];
        if (_poolInfo.availableFeeAmount>0&&_poolInfo.availableFeeAmount==_poolInfo.claimedAvailbleFeeAmount){

            delete poolTimeKeyInfo[timeKey];

        }
    }

    //add white tokne pair.can mine depth
    function addWhitePairs(uint256 _index,address _token1,address  _token2) external onlyOwner{
      // Ensure the fee is less than divisor
        require(_token1!=address(0)&&_token2!=address(0)&&_token1!=_token2, "INVALID_ADDRESS");
        uint256 len = whitePairList.length;
        require(_index <= len, "INVALID_INDEX");

        if (len==0||_index==len){

            whitePairList.push([_token1,_token2]);
        }else{
            whitePairList[_index] = [_token1,_token2];
        }


     }
    //remove white tokne pair.can mine depth
    function removeWhitePairs(uint256 _index) external onlyOwner{

        delete  whitePairList[_index];

    }
     function isWhitePair(address _token1,address _token2) public view returns(bool){
         for(uint i = 0; i < whitePairList.length; i++) {
             if ((whitePairList[i][0]==_token1&&whitePairList[i][1]==_token2)||(whitePairList[i][0]==_token2&&whitePairList[i][1]==_token1)){
                 return true;
             }
         }
         return false;
     }
    //save otc trade amount info
    function saveTradeInfo(address _maker,address _taker,address _makeToken,address _takeToken,uint256 _amount,uint256 _fee) external{
        require(!isPaused,"paused");
        //check the caller in otc contracts
        require(otcContracts[msg.sender],"invalid otc contract address");

        if(_amount<=0){
            return;
        }
        totalTradeAmount=totalTradeAmount.add(_amount);//add global trade amount;
        totalFeeAmount=totalFeeAmount.add(_fee);//add global fee amount
        //check tokens are in white list
        uint256 availableFee = 0;
        uint256 _timeKey = getTimeKey();

        if(isWhitePair(_makeToken,_takeToken)){
            availableFee = _fee;
        }
        totalAvailableFeeAmount=totalAvailableFeeAmount.add(availableFee);
        //check timekey is existed
        if (availableFee.div(2)>0){
            if(poolTimeKeyInfo[_timeKey].flag==false){
                timeKeys.push(_timeKey);
                poolTimeKeyInfo[_timeKey].flag=true;
                currentTimeKey = _timeKey;
            }


            poolTimeKeyInfo[_timeKey].tradeAmount=poolTimeKeyInfo[_timeKey].tradeAmount.add(_amount);
            poolTimeKeyInfo[_timeKey].feeAmount= poolTimeKeyInfo[_timeKey].feeAmount.add(_fee);
            poolTimeKeyInfo[_timeKey].availableFeeAmount=poolTimeKeyInfo[_timeKey].availableFeeAmount.add(availableFee);
            //above to set pool info
            //begin to set address time info

            saveAddressFeeAmount(_timeKey,_maker,_amount.div(2),availableFee.div(2));
            saveAddressFeeAmount(_timeKey,_taker,_amount.sub(_amount.div(2)),availableFee.sub(availableFee.div(2)));

        }

    }
    //internal function to save address amount and fee.
    function saveAddressFeeAmount(uint256 _timeKey,address _address,uint256 _amount,uint256 _fee) internal{
        if (userNoClaimedTimeKeyInfo[_address][_timeKey].availableTradeAmount ==0){
            userNoClaimedTimes[_address].push(_timeKey);
        }
        userNoClaimedTimeKeyInfo[_address][_timeKey].availableTradeAmount =userNoClaimedTimeKeyInfo[_address][_timeKey].availableTradeAmount.add(_amount);
        userNoClaimedTimeKeyInfo[_address][_timeKey].availableFeeAmount =userNoClaimedTimeKeyInfo[_address][_timeKey].availableFeeAmount.add(_fee);
    }

    function getRewardTimeKey() public view returns(uint256){
        uint256 _timeKey = 0;
        uint256 _todayTimeKey =block.timestamp/86400*86400;

        if (_todayTimeKey>=lastRewardTimeKey&&poolTimeKeyInfo[lastRewardTimeKey].flag&&poolTimeKeyInfo[lastRewardTimeKey].rewardTokenAmount==0){
            return lastRewardTimeKey;
        }
        if (_todayTimeKey>=currentTimeKey&&poolTimeKeyInfo[currentTimeKey].flag&&poolTimeKeyInfo[currentTimeKey].rewardTokenAmount==0){
            return currentTimeKey;
        }
        return _timeKey;


    }
    //claim depth token and reward to pool.every adress can call this function
    function rewardToken() external{
        uint256 _timeKey = getRewardTimeKey();
        require(_timeKey>0,"not need to reward ");
        require(!isPaused,"paused");
        require(depTokenAddress!=address(0),"invalid depth token address");
        require(depthStakeAddress!=address(0),"invalid depth stake contract address");
        uint256 _before = IERC20(depTokenAddress).balanceOf(address(this));
        //first call stake contract claim depth token to this contract.
        stakeContract(depthStakeAddress).claim(depthStakePoolId);
        uint256 _rewardAmount = IERC20(depTokenAddress).balanceOf(address(this)).sub(_before);

        totalRewardTokenAmount = totalRewardTokenAmount.add(_rewardAmount);
        poolTimeKeyInfo[_timeKey].rewardTokenAmount = _rewardAmount;

        lastRewardTimeKey = currentTimeKey;

    }

    //calculate address can claim dep tokens .
    function canClaim(address _address) public view returns(uint256){
        uint256[] memory noClaimTimes = userNoClaimedTimes[_address];
        uint256 _tokenAmount=0;
        uint256 _currentTimeKey= getTimeKey();
        for (uint i=0;i<noClaimTimes.length;i++){

            uint256 _timeKey=noClaimTimes[i];


            if(_timeKey<_currentTimeKey&&poolTimeKeyInfo[_timeKey].availableFeeAmount>0){
                uint256 _poolTokenAmount = poolTimeKeyInfo[_timeKey].rewardTokenAmount;


                _tokenAmount = _tokenAmount.add(userNoClaimedTimeKeyInfo[_address][_timeKey].availableFeeAmount.mul(_poolTokenAmount).div(poolTimeKeyInfo[_timeKey].availableFeeAmount));
            }

        }
        return _tokenAmount;
    }

    function nextCanClaim(address _address) public view returns(uint256){

        uint256 _tokenAmount=0;
        uint256 _timeKey=getTimeKey();
        if(poolTimeKeyInfo[_timeKey].availableFeeAmount>0){
            uint256 _poolTokenAmount = poolTimeKeyInfo[_timeKey].rewardTokenAmount;
            if (_poolTokenAmount==0){//not reward from depth stake contract.get the balance
                _poolTokenAmount = stakeContract(depthStakeAddress).pendingPiggy(depthStakePoolId,address(this));
            }
            _tokenAmount = userNoClaimedTimeKeyInfo[_address][_timeKey].availableFeeAmount.mul(_poolTokenAmount).div(poolTimeKeyInfo[_timeKey].availableFeeAmount);
        }


        return _tokenAmount;
    }
    //unstake lp token
    function unStake() external onlyOwner{
        //first must claim.
        claim();
       stakeContract _stake= stakeContract(depthStakeAddress);
      (uint256 amount,,,)=_stake.userInfo(depthStakePoolId,address(this));
      if (amount>0){
          _stake.unStake(depthStakePoolId,amount);
      }


    }
    //user claim depth token .
    function claim() public{
        require(!isPaused,"paused");




        uint256[] memory userTimeKeys=userNoClaimedTimes[msg.sender];
        delete userNoClaimedTimes[msg.sender];
        uint256 _depAmount =0;
        for(uint i=0;i<userTimeKeys.length;i++){
            uint256 _timeKey = userTimeKeys[i];
            PoolTimeKeyInfo storage _poolInfo=poolTimeKeyInfo[_timeKey];
            UserTimeKeyInfo memory _userInfo=userNoClaimedTimeKeyInfo[msg.sender][_timeKey];
            uint256 _poolTokenAmount = _poolInfo.rewardTokenAmount;
            if(_poolTokenAmount>0&&poolTimeKeyInfo[_timeKey].availableFeeAmount>0){
                //this pool has reward depth token.can claim.
                uint256 _tokenAmount = _userInfo.availableFeeAmount.mul(_poolTokenAmount).div(poolTimeKeyInfo[_timeKey].availableFeeAmount);
                _depAmount=_depAmount.add(_tokenAmount);
                totalClaimedTokenAmount = totalClaimedTokenAmount.add(_tokenAmount);
                _poolInfo.claimedTokenAmount = _poolInfo.claimedTokenAmount.add(_tokenAmount);
                _poolInfo.claimedAvailbleFeeAmount = _poolInfo.claimedAvailbleFeeAmount.add(_userInfo.availableFeeAmount);
                if ( _poolInfo.claimedAvailbleFeeAmount >=_poolInfo.availableFeeAmount){
                    //all users have claimed depth token
                    delete poolTimeKeyInfo[_timeKey];
                }
                delete userNoClaimedTimeKeyInfo[msg.sender][_timeKey];
            }else{
                userNoClaimedTimes[msg.sender].push(_timeKey);
            }
        }
        if (_depAmount>0){
            IERC20(depTokenAddress).safeTransfer(msg.sender,_depAmount);
        }




    }

    //return global trade datas
    function getTradeDatas() external view returns(uint256,uint256,uint256,uint256,uint256){
        return (totalTradeAmount,totalFeeAmount,totalAvailableFeeAmount,totalRewardTokenAmount,totalClaimedTokenAmount);

    }




}
