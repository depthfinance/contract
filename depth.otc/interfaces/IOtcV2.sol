
pragma solidity ^0.8.0;

import "../openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IOtcV2 {
  event Swap(
    uint256 indexed nonce,
    uint256 timestamp,
    address indexed makerAddress,
    address makerToken,
    uint256 makerAmount,
    address indexed takerAddress,
    address takerToken,
    uint256 takerAmount,
    uint256 feeAmount
  );

  event Cancel(uint256 indexed nonce, address indexed makerAddress);

  event Authorize(address indexed signer, address indexed makerAddress);

  event Revoke(address indexed signer, address indexed makerAddress);

}
interface IHusdSwap {
  function swapTokensToHusd(address _token,uint256 _amount) external;
}

interface IStorage {
  function saveTradeInfo(uint256 _amount,uint256 _fee) external;
}
interface IDao {
  function donateHUSD(uint256 amount) external;
}
interface ISwapMining{
  function takerWithdraw() external;
}
