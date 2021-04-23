
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface stakeContract {
    function poolInfo(uint256) external view returns(address lpToken,uint256 allocPoint,uint256 lastRewardBlock,uint256 accPiggyPerShare,uint256 totalDeposit,address migrator);
    function userInfo(uint256,address) external view returns(uint256,uint256,uint256,bool);
    function stake(uint256,uint256) external;
    function pendingPiggy(uint256 _pid, address _user) external view returns (uint256) ;
    function claim(uint256 _pid) external; 
    function unStake(uint256 _pid, uint256 _amount) external ;
}
