pragma solidity >=0.5.0 <0.8.0;

import './interfaces/IDepthswapFactory.sol';
import './DepthswapPair.sol';

contract DepthswapFactory is IDepthswapFactory {
    using SafeMath for uint256;
    address public feeTo;
    address public feeToSetter;
    bytes32 public initCodeHash;

    struct FeeInfo{
        uint256 stakeAmount;
        uint256 feeRate;
    }
    FeeInfo[] public feeInfo;
    uint256 public constant FEE_RATE_DENOMINATOR = 10000;
    uint256 public feeRateNumerator = 30;
    address public xdepAddress = 0xDeEfD50FE964Cd03694EF7AbFB4147Cb1dd41c9B;

    bool public allowAllOn;
    mapping(address => bool) public whiteList;

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

    // set stake token address
    function setXdepAddress(address _address) public {
        require(msg.sender == feeToSetter, 'DepthSwapFactory: FORBIDDEN');
        xdepAddress = _address;
    }

    //set fee feeRate
    function setFeeRate(uint256 index, uint256 stakeAmount, uint256 rate) public {
        require(msg.sender == feeToSetter, 'DepthSwapFactory: FORBIDDEN');
        // Ensure the fee is less than divisor
        require(rate <= 50, "INVALID_FEE");
        uint256 len = feeInfo.length;
        require(index <= len, "INVALID_INDEX");

        FeeInfo memory _new = FeeInfo({
        stakeAmount : stakeAmount,
        feeRate : rate
        });
        if (len==0||index==len){
            feeInfo.push(_new);
        }else{
            feeInfo[index] = _new;
        }
    }

    // Set default fee ，max is 0.003%
    function setFeeRateNumerator(uint256 _feeRateNumerator) public {
        require(msg.sender == feeToSetter, 'MdexSwapFactory: FORBIDDEN');
        require(_feeRateNumerator <= 50, "MdexSwapFactory: EXCEEDS_FEE_RATE_DENOMINATOR");
        feeRateNumerator = _feeRateNumerator;
    }

    //return address swap fee
    function getFeeRate(address _address) public view returns (uint256){
        require(_address != address(0), "INVALID_ADDRESS");
        uint256 balance = IERC20(xdepAddress).balanceOf(_address);
        //loop the fee rate array
        uint256 lastAmount = 0;
        uint256 feeRate = 0;
        uint256 stakeTokenDecimal = IERC20(xdepAddress).decimals();
        for(uint i = 0; i < feeInfo.length; i++) {
            if (balance>=feeInfo[i].stakeAmount.mul(stakeTokenDecimal)&&(lastAmount==0||feeInfo[i].stakeAmount>lastAmount)){
                feeRate = feeInfo[i].feeRate;
                lastAmount = feeInfo[i].stakeAmount;
            }
        }

        if (feeRate == 0) {
            return feeRateNumerator;
        }

        return feeRate;
    }
}
