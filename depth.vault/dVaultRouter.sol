pragma solidity ^0.8.0;

import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./openzeppelin/contracts/security/Pausable.sol";
import "./openzeppelin/contracts/security/ReentrancyGuard.sol";
interface IVaultPool{
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
}
/**depth.fi vault***/
contract dVaultRouter is ERC20,Ownable,Pausable,ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    uint256 public totalAllocPoint;
    struct PoolInfo{
        address vaultAddress;
        uint256 allocPoint;
        uint256 balance;
    }
    PoolInfo[] public poolInfo;
    address public want;
    uint256 public maxLimit;// max balance limit
    uint256 public totalBalance;//total token balance
    constructor (address _want) ERC20(
        string(abi.encodePacked("Depth.Fi Vault ", ERC20(_want).symbol())),
        string(abi.encodePacked("dv", ERC20(_want).symbol()))
    ) {

        require(_want != address(0), "INVALID TOKEN ADDRESS");
        want  = _want;

    }

    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function addPool(uint256 _allocPoint, address _vaultAddress) external onlyOwner{
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            vaultAddress : _vaultAddress,
            allocPoint : _allocPoint,
            balance : 0
        }));
    }

    function getMostInsufficientPool() public view returns(uint256 poolId,address poolAddress){
        uint256 _maxCanDeposit=0;
        for(uint256 i=0;i<poolLength();i++){
            if(poolInfo[i].allocPoint==0){
                continue;
            }
            uint256 _poolBalance=poolInfo[i].balance;
            uint256 _needDepositAmount = totalBalance.mul(poolInfo[i].allocPoint).div(totalAllocPoint);
            uint256 _canDepositAmount = _poolBalance>=_needDepositAmount?0:_needDepositAmount.sub(_poolBalance);
            if (_canDepositAmount>=_maxCanDeposit){
                poolId = i;
                poolAddress = poolInfo[i].vaultAddress;
                _maxCanDeposit = _canDepositAmount;
            }
        }
    }

    function getMostOverLockedPool(uint256 _withdrawAmount) public view returns(uint256 poolId,address poolAddress,uint256 availableWithdrawAmount){
        uint256 _totalBalance=totalBalance.sub(_withdrawAmount);
        for(uint256 i=0;i<poolLength();i++){
            if(poolInfo[i].balance==0){
                continue;
            }
            uint256 _current=poolInfo[i].balance;
            uint256 _optimal = _totalBalance.mul(poolInfo[i].allocPoint).div(totalAllocPoint);
            if (_current>=_optimal&&_current.sub(_optimal)>=availableWithdrawAmount){
                poolId = i;
                poolAddress = poolInfo[i].vaultAddress;
                availableWithdrawAmount = _current.sub(_optimal);
            }
        }
    }
    function getMostLockedPool() public view returns(uint256 poolId,address poolAddress,uint256 maxBalance){
        for(uint256 i=0;i<poolLength();i++){

            uint256 _current=poolInfo[i].balance;
            if (_current>=maxBalance){
                poolId = i;
                poolAddress = poolInfo[i].vaultAddress;
                maxBalance = _current;
            }
        }
    }
    function movePool(uint256 _fromPoolId,uint256 _toPoolId,uint256 _amount) public onlyOwner{
        address _fromAddress = poolInfo[_fromPoolId].vaultAddress;
        address _toAddress = poolInfo[_toPoolId].vaultAddress;
        require(_fromAddress!=address(0)&&_toAddress!=address(0),"invalid pool id!");
        require(_amount>0,"invalid amount!");
        IVaultPool(_fromAddress).withdraw(_amount);
        poolInfo[_fromPoolId].balance=poolInfo[_fromPoolId].balance.sub(_amount);


        IERC20(want).safeApprove(_toAddress,_amount);
        IVaultPool(_toAddress).deposit(_amount);
        poolInfo[_toPoolId].balance=poolInfo[_toPoolId].balance.add(_amount);
    }
    function updatePools() external nonReentrant{
        (uint256 _fromPoolId,address _fromPoolAddress,uint256 _overAmount) = getMostOverLockedPool(0);
        if (_overAmount>0){
            (uint256 _toPoolId,address _toPoolAddress) = getMostInsufficientPool();

            IVaultPool(_fromPoolAddress).withdraw(_overAmount);
            poolInfo[_fromPoolId].balance=poolInfo[_fromPoolId].balance.sub(_overAmount);


            IERC20(want).safeApprove(_toPoolAddress,_overAmount);
            IVaultPool(_toPoolAddress).deposit(_overAmount);
            poolInfo[_toPoolId].balance=poolInfo[_toPoolId].balance.add(_overAmount);
        }
    }



    // set max deposit limit
    function setMaxLimit(uint256 _max)   external onlyOwner{
        maxLimit = _max;
    }


    function setAllocPoint(uint256 _pid, uint256 _allocPoint) public onlyOwner {

        //update totalAllocPoint
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);

        //update poolInfo
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    //get underlying amount in compound pool
    function getSelfUnderlying() public view returns (uint256) {

        return totalBalance;
    }
    function _deposit(uint256 _amount) internal nonReentrant{
        (uint256 _poolId,address _poolAddress) = getMostInsufficientPool();
        IERC20(want).safeApprove(_poolAddress,_amount);
        IVaultPool(_poolAddress).deposit(_amount);
        poolInfo[_poolId].balance=poolInfo[_poolId].balance.add(_amount);
        totalBalance=totalBalance.add(_amount);

        _mint(msg.sender, _amount);
    }
    //deposit
    function deposit(uint256 _amount) external whenNotPaused {
        require(_amount>0,"invalid amount");
        require(maxLimit==0||totalBalance.add(_amount)<=maxLimit,"exceed max deposit limit");
        IERC20(want).safeTransferFrom(msg.sender, address(this), _amount);
        _deposit(_amount);
    }
    function _withdraw(uint256 _amount) internal nonReentrant{
        _burn(msg.sender, _amount);
        (uint256 _poolId,address _poolAddress,uint256 _maxWithdrawAmount) = getMostOverLockedPool(_amount);
        if (_poolAddress==address(0)||_maxWithdrawAmount==0){
            (_poolId,_poolAddress,_maxWithdrawAmount)= getMostLockedPool();
            require(_maxWithdrawAmount>=_amount,"too big amount to withdraw!");
        }
        IVaultPool(_poolAddress).withdraw(_amount);
        poolInfo[_poolId].balance=poolInfo[_poolId].balance.sub(_amount);
        totalBalance=totalBalance.sub(_amount);
    }
    //withdraw
    function withdraw(uint256 _amount) external {
        require(_amount>0,"invalid amount");

        _withdraw(_amount);

        IERC20(want).safeTransfer(msg.sender, _amount);


    }


    function pause() external onlyOwner {
        _pause();
    }


    function unpause() external onlyOwner {
        _unpause();
    }
    function decimals() public view override returns (uint8) {
        return ERC20(want).decimals();
    }

}
