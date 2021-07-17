pragma solidity >=0.5.0 <0.8.0;

import './interfaces/IDepthswapFactory.sol';
import './DepthswapPair.sol';

contract DepthswapFactory is IDepthswapFactory {
    using SafeMath for uint256;
    address public feeTo;
    address public feeToSetter;
    bytes32 public initCodeHash;

    bool public allowAllOn;
    mapping(address => bool) whiteList;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
        initCodeHash = keccak256(abi.encodePacked(type(DepthswapPair).creationCode));
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {

        if (allowAllOn == false){
            require(whiteList[tokenA] == true, "token not in whiteList");
            require(whiteList[tokenB] == true, "token not in whiteList");
        }

        require(tokenA != tokenB, 'DepthSwapFactory: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'DepthSwapFactory: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'DepthSwapFactory: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(DepthswapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IDepthswapPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'DepthSwap: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'DepthSwap: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }

    function addWhiteList(address _address) public {
        require(msg.sender == feeToSetter, 'DepthSwapFactory: FORBIDDEN');
        whiteList[_address] = true;
    }

    function deleteWhiteList(address _address) public {
        require(msg.sender == feeToSetter, 'DepthSwapFactory: FORBIDDEN');
        whiteList[_address] = false;
    }

    function setallowAllOn(bool _bvalue) public {
        require(msg.sender == feeToSetter, 'DepthSwapFactory: FORBIDDEN');
        allowAllOn = _bvalue;
    }

}
