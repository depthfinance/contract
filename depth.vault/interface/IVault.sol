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

}
interface UsdtSwapRouter {
    function exchange_underlying(int128, int128, uint256, uint256) external;
}
interface HusdSwapRouter {
    function getAmountsOut(uint amountIn, address[] calldata path) external returns (uint256[] memory);
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}
interface IDao {
    function donateHUSD(uint256 amount) external;
}
interface ISwapMining{
    function takerWithdraw() external;
}

