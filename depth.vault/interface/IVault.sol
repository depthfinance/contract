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

