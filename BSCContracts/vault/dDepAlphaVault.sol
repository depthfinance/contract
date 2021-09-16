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

contract dDepAlphaVault is ERC20,Ownable,Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public want;

    address public daoAddress = 0xfbaC8c66D9B7461EEfa7d8601568887c7b6f96AD;     //DEP DAO ADDRESS
    address public constant busd = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;  //BUSD ADDRESS
    address public constant WBNB= 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    address public busdSwapAddress;
    address public ibTokenAddress;          // ib token address such as： Interest Bearing BUSD (ibBUSD)
    address public tokenAddress;            // address of the token to be deposited in this pool
    address public debtTokenAddress;        // just a simple ERC20 token for staking with FairLaunch

    uint256 public balance;                 //total token balance
    uint256 public minClaim=1;              //min interest to claim
    uint256 public maxLimit;                // max balance limit

    constructor (address _want, address _ibTokenAddress, address _swapAddress) ERC20(
        string(abi.encodePacked("Depth.Fi Vault Alpha", ERC20(_want).symbol())),
        string(abi.encodePacked("bDep", ERC20(_want).symbol()))
    ) {

        require(_want != address(0), "INVALID _want ADDRESS");
        require(_ibTokenAddress != address(0), "INVALID _ibTokenAddress ADDRESS");

        want = _want;
        ibTokenAddress = _ibTokenAddress;

        address _tokenAddress = IAlpha(_ibTokenAddress).token(); // BUSD USDT WBNB...
        tokenAddress = _tokenAddress;
        require(want == tokenAddress, "invalid constructor param");

        busdSwapAddress =  _swapAddress;
    }

    // set min claim interest
    function setMinClaim(uint256 _min)   external onlyOwner{
        minClaim = _min;
    }
    // set max deposit limit
    function setMaxLimit(uint256 _max)   external onlyOwner{
        maxLimit = _max;
    }

    // set busd swap contract address
    function setBusdSwapAddress(address _address)   external onlyOwner{
        require(_address!=address(0), "invalid address!");
        busdSwapAddress = _address;
    }

    // set dao contract address
    function setDaoAddress(address _address)   external onlyOwner{
        require(_address!=address(0),"no address!");
        daoAddress = _address;
    }

    //deposit busd usdt ....
    function deposit(uint256 _amount) external whenNotPaused payable {
        require(_amount>0, "invalid amount");

        if (msg.value != 0) {
            require(tokenAddress == WBNB, "invalid address");
            require(_amount == msg.value, "_amount != msg.value");
            IAlpha(ibTokenAddress).deposit{value: _amount}(_amount);
        } else {
            IERC20(want).transferFrom(msg.sender, address(this), _amount);
            IERC20(want).approve(ibTokenAddress, _amount); //deposit token to alpha pool
            IAlpha(ibTokenAddress).deposit(_amount);
        }

        balance=balance.add(_amount);
        _mint(msg.sender, _amount);
    }

    //withdraw busd usdt ....
    function withdraw(uint256 _amount) external {
        require(_amount>0, "invalid amount");
        _burn(msg.sender, _amount);

        uint256 totalToken = IAlpha(ibTokenAddress).totalToken();
        uint256 totalSupply = IAlpha(ibTokenAddress).totalSupply();
        uint256 share = _amount.mul(totalSupply).div(totalToken);

        if (tokenAddress == WBNB) {
            IAlpha(ibTokenAddress).withdraw(share);
            payable(msg.sender).transfer(_amount);
        } else {
            uint256 _before = IERC20(want).balanceOf(address(this));
            IAlpha(ibTokenAddress).withdraw(share);
            uint256 _after = IERC20(want).balanceOf(address(this));
            require(_after.sub(_before)>=_amount, "sub flow!");
            IERC20(want).transfer(msg.sender, _amount);
        }

        balance=balance.sub(_amount);
    }

    function swapTokensToBusd(address _token) internal{
        require(busdSwapAddress!=address(0),"not set husd swap address!");
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        if (_amount==0){
            return;
        }
        IERC20(_token).approve(busdSwapAddress, _amount);
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
            } else {
                uint256 _before = IERC20(want).balanceOf(address(this));
                IAlpha(ibTokenAddress).withdraw(share);
                uint256 _after = IERC20(want).balanceOf(address(this));
                require(_after.sub(_before)>=_claimAmount, "sub flow!");

            }

            if (want!= busd){
                swapTokensToBusd(want);
            }
        }

        //donate husd to dao
        uint256 _busdBalance = IERC20(busd).balanceOf(address(this));
        IERC20(busd).safeApprove(daoAddress,_busdBalance);
        //call dao address donate husd
        IDao(daoAddress).donateHUSD(_busdBalance);
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
