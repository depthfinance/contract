pragma solidity >=0.5.0 <0.8.0;

interface IDepthswapCallee {
    function DepthswapCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}
