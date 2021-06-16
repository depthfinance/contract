pragma solidity ^0.8.0;

import "../openzeppelin/contracts/token/ERC20/IERC20.sol";

interface CToken {
    function balanceOf(address owner) external view returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function balanceOfUnderlying(address owner) external returns (uint256);
    function mint(uint256 mintAmount) external returns (uint256);
    function getAccountSnapshot(address account)
    external
    view
    returns (
        uint256,
        uint256,
        uint256,
        uint256
    );
    function underlying() external view returns (address);
    function comptroller() external view returns (address);
}
interface CompControl {
    // Claim all the COMP accrued by holder in specific markets
    function claimComp(address holder, address[] calldata cTokens) external;
    function getCompAddress() external view returns (address);
    function claimCan(address holder, address[] calldata cTokens) external;
    function getCanAddress() external view returns (address);

}
interface IHusdSwap {
    function swapTokensToHusd(address _token,uint256 _amount) external;
}
interface IDao {
    function donateHUSD(uint256 amount) external;
}
interface ISwapMining{
    function takerWithdraw() external;
}

interface IPilot{
    function totalToken(address token) external view returns (uint256);
    function deposit(address token, uint256 amount) external;
    function withdraw(address token, uint256 pAmount) external;
    function banks(address _token) external view returns(address tokenAddr,
address pTokenAddr,
bool isOpen,
bool canDeposit,
bool canWithdraw,
uint256 totalVal,
uint256 totalDebt,
uint256 totalDebtShare,
uint256 totalReserve,
uint256 lastInterestTime);
}
interface IBack{
    function supplyToken() external view returns (address);
    function getTotalShare() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalBorrow() external view returns (uint256);
    function poolReserve() external view returns (uint256);
    function totalInterestToPay() external view returns (uint256);
    function queryBack(address) external view returns(uint256);
    function deposit(address _token,uint256 _amount) external;
    function withdraw(address _token,uint256 _amount) external;
    function mintBack() external;
}
interface ICow{
    function poolLength() external view returns(uint256);
    function deposit(address _token, uint256 _amount) external;
    function withdraw(address _token, uint256 _amount) external;
    function pending(uint256 _poolId,address _userAddress) external view returns(uint256,uint256,uint256);
    function pendingCow(uint256 _poolId,address _userAddress) external view returns(uint256);
    function poolInfo(uint256 _poolId) external view returns(address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256);
}
