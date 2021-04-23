
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IOtcV1 {
  event Swap(
    uint256 indexed nonce,
    uint256 timestamp,
    address indexed makerAddress,
    IERC20 makerToken,
    uint256 makerAmount,
    address indexed takerAddress,
    IERC20 takerToken,
    uint256 takerAmount,
    uint256 feeAmount
  );

  event Cancel(uint256 indexed nonce, address indexed makerAddress);

  event Authorize(address indexed signer, address indexed makerAddress);

  event Revoke(address indexed signer, address indexed makerAddress);

  function swap(
    uint256 nonce,
    uint256 expiry,
    address makerAddress,
    IERC20 makerToken,
    uint256 makerAmount,
    address takerAddress,
    IERC20 takerToken,
    uint256 takerAmount,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;

  function authorize(address sender) external;

  function revoke() external;

  function cancel(uint256[] calldata nonces) external;

  function nonceUsed(address, uint256) external view returns (bool);

  function authorized(address) external view returns (address);
}
interface UsdtSwapRouter {
    function exchange_underlying(int128, int128, uint256, uint256) external;
}
interface HusdSwapRouter {
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}
interface IStorage {
     function saveTradeInfo(address _maker,address _taker,address _makeToken,address _takeToken,uint256 _amount,uint256 _fee) external;
}
interface IDao {
     function donateHUSD(uint256 amount) external;
}
