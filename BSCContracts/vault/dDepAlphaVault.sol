pragma solidity ^0.8.0;

import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./openzeppelin/contracts/security/Pausable.sol";

interface IAlpha {

    function token()  external view returns (address);

    function totalToken() external view returns (uint256);
    function totalSupply() external view returns (uint256);

    function deposit(uint256 amount) payable external;
    function withdraw(uint256 amount) external;

    function balanceOf(address) external view returns (uint256);
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

    function deposit(address _for, uint256 _pid, uint256 _amount) external;

    function withdraw(address _for, uint256 _pid, uint256 _amount) external;

    function harvest(uint256 _pid) external;
}

contract dDepAlphaVault is ERC20,Ownable,Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public want;

    address public constant busd = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;  //BUSD ADDRESS
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant ALPACA = 0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F; // AlpacaToken (ALPACA)

    address public daoAddress;              //DEP DAO ADDRESS
    address public teamAddress=0x01D61BE40bFF0c48A617F79e6FAC6d09D7a52aAF;
    address public earnToken =0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;

    address public busdSwapAddress;
    address public ibTokenAddress;          // ib token address such as： Interest Bearing BUSD (ibBUSD)
    address public tokenAddress;            // address of the token to be deposited in this pool
    address public miningAddress;           // ibToken mining address
    uint256 public miningPid;               // mining pool pid

    uint256 public balance;                 // total token balance
    uint256 public minClaim=1;              // min interest to claim
    uint256 public maxLimit;                // max balance limit

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    constructor (address _want, address _ibTokenAddress, address _swapAddress, address _miningAddress, uint256 _pid) ERC20(
        string(abi.encodePacked("Depth.Fi Vault Alpha", ERC20(_want).symbol())),
        string(abi.encodePacked("da", ERC20(_want).symbol()))
    ) {
        require(_want != address(0), "INVALID _want ADDRESS");
        require(_ibTokenAddress != address(0), "INVALID _ibTokenAddress ADDRESS");
        require(_swapAddress != address(0), "INVALID _swapAddress ADDRESS");
        require(_miningAddress != address(0), "INVALID _miningAddress ADDRESS");

        want = _want;
        ibTokenAddress = _ibTokenAddress;
        miningAddress = _miningAddress;
        miningPid = _pid;

        address _tokenAddress = IAlpha(_ibTokenAddress).token(); // BUSD USDT WBNB...
        tokenAddress = _tokenAddress;
        require(want == tokenAddress, "invalid constructor param");

        busdSwapAddress =  _swapAddress;
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
        busdSwapAddress = _address;
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

    function getShare(uint256 _amount) internal view returns (uint256) {
        require(_amount>0, "invalid amount");

        uint256 totalToken = IAlpha(ibTokenAddress).totalToken();
        uint256 total = totalToken.sub(_amount);
        uint256 totalSupply = IAlpha(ibTokenAddress).totalSupply();
        uint256 share = total == 0 ? _amount : _amount.mul(totalSupply).div(totalToken);
        return share;
    }

    function ibTokenMining(uint256 share) internal {
        require(share>0, "invalid share");
        IERC20(ibTokenAddress).safeApprove(miningAddress, share);
        IMining(miningAddress).deposit(address(this), miningPid, share);
    }

    //deposit busd usdt ....
    function deposit(uint256 _amount) external whenNotPaused payable {
        require(_amount>0, "invalid amount");

        if (msg.value != 0) {
            require(tokenAddress == WBNB, "invalid address");
            require(_amount == msg.value, "_amount != msg.value");
            IAlpha(ibTokenAddress).deposit{value: _amount}(_amount);

            // ibtoken mining
            uint256 share = getShare(_amount);
            ibTokenMining(share);
        } else {
            IERC20(want).safeTransferFrom(msg.sender, address(this), _amount);
            IERC20(want).safeApprove(ibTokenAddress, _amount); //deposit token to alpha pool
            IAlpha(ibTokenAddress).deposit(_amount);

            // ibtoken mining
            uint256 share = getShare(_amount);
            ibTokenMining(share);
        }

        balance=balance.add(_amount);
        _mint(msg.sender, _amount);

        emit Deposit(msg.sender, _amount);
    }

    //withdraw busd usdt ....
    function withdraw(uint256 _amount) external {
        require(_amount>0, "invalid amount");
        _burn(msg.sender, _amount);

        uint256 share = getShare(_amount);
        IMining(miningAddress).withdraw(address(this), miningPid, share);

        uint256 _before = IERC20(want).balanceOf(address(this));
        IAlpha(ibTokenAddress).withdraw(share);
        uint256 _after = IERC20(want).balanceOf(address(this));
        require(_after.sub(_before)>=_amount, "sub flow!");

        if (tokenAddress == WBNB) {
            payable(msg.sender).transfer(_amount);
        } else {
            IERC20(want).safeTransfer(msg.sender, _amount);
        }

        balance=balance.sub(_amount);

        emit Withdraw(msg.sender, _amount);
    }

    function swapTokensToBusd(address _token) internal{
        require(busdSwapAddress!=address(0),"not set husd swap address!");
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        if (_amount==0){
            return;
        }
        IERC20(_token).safeApprove(busdSwapAddress, _amount);
        ISwap(busdSwapAddress).swapTokensToEarnToken(_token, _amount);
    }

    //get underlying amount in compound pool
    function getSelfUnderlying() public view returns (uint256) {

        uint256 ibAmount = IAlpha(ibTokenAddress).balanceOf(address(this));
        uint256 _totalToken = IAlpha(ibTokenAddress).totalToken();
        uint256 _totalSupply =  IAlpha(ibTokenAddress).totalSupply();
        uint256 amount = ibAmount.mul(_totalToken).div(_totalSupply);
        return amount;
    }

    function harvest() public {

        uint256 _selfUnderlying = getSelfUnderlying();
        uint256 _interest = _selfUnderlying.sub(balance);

        if (_interest>=minClaim){

            uint256 _totalToken = IAlpha(ibTokenAddress).totalToken();
            uint256 _claimAmount = _interest<_totalToken?_interest:_totalToken;

            uint256 _totalSupply =  IAlpha(ibTokenAddress).totalSupply();
            uint256 share = _claimAmount.mul(_totalSupply).div(_totalToken);

            if (tokenAddress == WBNB) {
                IAlpha(ibTokenAddress).withdraw(share);
                IWBNB(WBNB).deposit{value: address(this).balance}();
            } else {
                uint256 _before = IERC20(want).balanceOf(address(this));
                IAlpha(ibTokenAddress).withdraw(share);
                uint256 _after = IERC20(want).balanceOf(address(this));
                require(_after.sub(_before)>=_claimAmount, "sub flow!");
            }

            if (want!= busd){
                swapTokensToBusd(want);
            }

            uint256 abalance = IERC20(ALPACA).balanceOf(address(this));
            if (abalance > 0) {
                swapTokensToBusd(ALPACA);
            }
        }

        //donate earnToken to dao
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

    function claimAlpaca() external {
        IMining(miningAddress).harvest(miningPid);
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
