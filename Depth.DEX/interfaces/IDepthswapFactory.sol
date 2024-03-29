pragma solidity >=0.5.0 <0.8.1;

interface IDepthswapFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;

    function setallowAllOn(bool _bvalue) external;

    function getFeeRate(address _address) external view returns (uint256);

    function FEE_RATE_DENOMINATOR() external view returns (uint256);
    function feeRateNumerator() external view returns (uint256);
}
