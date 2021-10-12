pragma solidity ^0.8.0;

import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./openzeppelin/contracts/security/Pausable.sol";

interface Ixbxh {
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
}

interface ISwap {
    function swapTokensToEarnToken(address _token, uint256 _amount) external;
}

interface IDao {
    function donateHUSD(uint256 amount) external;
}

interface IWBNB{
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

interface IMining {

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;
}

interface ISwapRouter {
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}

contract dDepBxhVault is ERC20,Ownable,Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public want;  // deposit address busd usdt wbnb

    address public constant busd = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;  //BUSD ADDRESS
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant BXH = 0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F; // BXH TOKEN

    address public daoAddress;              //DEP DAO ADDRESS
    address public teamAddress=0x01D61BE40bFF0c48A617F79e6FAC6d09D7a52aAF;
    address public earnToken=0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;

    address public dexSwapAddress;
    address public xTokenAddress;           // bxh xtoken
    address public miningAddress;           // BXH XToken mining address
    uint256 public miningPid;               // mining pool pid

    uint256 public balance;                 // total token balance
    uint256 public minClaim=1;              // min interest to claim
    uint256 public maxLimit;                // max balance limit

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    mapping(address => address[]) public paths;

    constructor (address _want, address _tokenAddress,address _swapAddress, address _miningAddress, uint256 _pid) ERC20(
        string(abi.encodePacked("Depth.Fi Vault BXH", ERC20(_want).symbol())),
        string(abi.encodePacked("da", ERC20(_want).symbol()))
    ) {
        require(_want != address(0), "INVALID _want ADDRESS");
        require(_swapAddress != address(0), "INVALID _swapAddress ADDRESS");
        require(_miningAddress != address(0), "INVALID _miningAddress ADDRESS");

        want = _want;                   // deposit token address
        miningAddress = _miningAddress; // mining  address
        miningPid = _pid;

        xTokenAddress = _tokenAddress;  // bxh xtoken address
        dexSwapAddress =  _swapAddress;

        paths[BXH] = [BXH, busd];
    }

    // set min claim interest
    function setMinClaim(uint256 _min) external onlyOwner{
        minClaim = _min;
    }

    // set max deposit limit
    function setMaxLimit(uint256 _max) external onlyOwner{
        maxLimit = _max;
    }

    // set SwapAddress
    function setSwapAddress(address _address) external onlyOwner{
        require(_address!=address(0),"invalid address");
        dexSwapAddress = _address;
    }

    // set dao contract address
    function setDaoAddress(address _address) external onlyOwner{
        daoAddress = _address;
    }

    // set miningAddress
    function setMiningAddress(address _address) external onlyOwner{
        require(_address!=address(0),"invalid address");
        miningAddress = _address;
    }

    // set miningPid
    function setPid(uint256 _pid) external onlyOwner{
        miningPid = _pid;
    }

    function setTeamAddress(address _address) public onlyOwner{
        require(_address!=address(0),"invalid address");
        teamAddress = _address;
    }

    function setDexSwappaths(address _address, address[] memory _paths) public onlyOwner {
        require(_address != address(0), "invalid address!");
        paths[_address] = _paths;
    }

    function bxhTokenMining(uint256 amount) internal {
        require(amount>0, "invalid amount");
        IERC20(xTokenAddress).safeApprove(miningAddress, amount);
        IMining(miningAddress).deposit(miningPid, amount);
    }

    //deposit busd usdt ....
    function deposit(uint256 _amount) external whenNotPaused payable {
        require(_amount>0, "invalid amount");

        if (msg.value != 0 && want == WBNB) {
            require(_amount == msg.value, "_amount != msg.value");
            IWBNB(WBNB).deposit{value:msg.value}();
        } else {
            IERC20(want).safeTransferFrom(msg.sender, address(this), _amount);
        }

        IERC20(want).safeApprove(xTokenAddress, _amount);
        Ixbxh(xTokenAddress).stake(_amount);
        bxhTokenMining(_amount);

        balance=balance.add(_amount);
        _mint(msg.sender, _amount);

        emit Deposit(msg.sender, _amount);
    }

    //withdraw busd usdt bnb....
    function withdraw(uint256 _amount) external {
        require(_amount>0, "invalid amount");
        _burn(msg.sender, _amount);

        IMining(miningAddress).withdraw(miningPid,_amount);
        Ixbxh(xTokenAddress).withdraw(_amount);

        if (want==WBNB){
            IWBNB(WBNB).withdraw(_amount);
            payable(msg.sender).transfer(_amount);
        }else{
            IERC20(want).safeTransfer(msg.sender, _amount);
        }
        balance=balance.sub(_amount);
        emit Withdraw(msg.sender, _amount);
    }

    function harvest() public {
        // get bxh token
        IMining(miningAddress).deposit(miningPid,0);

        uint256 abalance = IERC20(BXH).balanceOf(address(this));
        if (abalance > 0) {
            address[] memory path = paths[BXH];
            IERC20(BXH).safeApprove(dexSwapAddress, abalance);
            ISwapRouter(dexSwapAddress).swapExactTokensForTokens(abalance, 0, path, address(this), block.timestamp.add(1800));
        }

        //donate bxh token to dao
        uint256 _earnTokenBalance = IERC20(earnToken).balanceOf(address(this));
        if (_earnTokenBalance>0){
            if (daoAddress!=address(0)){
                IERC20(earnToken).safeApprove(daoAddress,_earnTokenBalance);
                IDao(daoAddress).donateHUSD(_earnTokenBalance);
            }else{
                IERC20(earnToken).safeTransfer(teamAddress,_earnTokenBalance);
            }
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function decimals() public view override returns (uint8) {
        return ERC20(want).decimals();
    }

    /// @dev Fallback function to accept BNB.
    receive() external payable {}

}
