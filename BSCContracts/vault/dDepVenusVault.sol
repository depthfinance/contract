pragma solidity ^0.8.3;

import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./openzeppelin/contracts/security/Pausable.sol";

interface VToken {
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function balanceOfUnderlying(address owner) external returns (uint256);
    function mint(uint256 mintAmount) external returns (uint256);
    function getAccountSnapshot(address account) external view returns (uint256, uint256, uint256, uint256);
    function underlying() external view returns (address);
    function comptroller() external view returns (address);
    function getCash() external view returns (uint256);
}

interface ISwap {
    function swapTokensToEarnToken(address _token,uint256 _amount) external;
}

interface IVenusComptroller {
    // Claim all the COMP accrued by holder in specific markets
    function claimVenus(address holder) external;
    function getXVSAddress() external view returns (address);
}

interface IDao {
    function donateHUSD(uint256 amount) external;
}

interface IComptroller {
    /*** Treasury Data ***/
    function treasuryAddress() external view returns (address);
    function treasuryPercent() external view returns (uint);
}

contract dDepVenusVault is ERC20, Ownable, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public want;
    address public vTokenAddress;   // VBep20Delegator
    address public constant busd = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;  //BUSD ADDRESS
    address public constant WBNB= 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    address public daoAddress;     // DEP DAO ADDRESS
    address public teamAddress = 0x01D61BE40bFF0c48A617F79e6FAC6d09D7a52aAF;
    address public earnToken = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;

    address public busdSwapAddress; //  swap compound token to usdt
    uint256 public maxLimit;        //  max balance limit
    uint256 public balance;         //  total token balance
    uint256 public minClaim=1;      //  min interest to claim default 1

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    constructor (address _vTokenAddress, address _swapAddress) ERC20(
        string(abi.encodePacked("Depth.Fi Vault Venus", ERC20(_vTokenAddress).symbol())),
        string(abi.encodePacked("dv", ERC20(_vTokenAddress).symbol()))
    ) {

        require(_vTokenAddress != address(0), "INVALID VTOKEN ADDRESS");
        want  = VToken(_vTokenAddress).underlying();
        vTokenAddress = _vTokenAddress;

        busdSwapAddress = _swapAddress;
    }

    // set min claim interest
    function setMinClaim(uint256 _min) external onlyOwner {
        minClaim = _min;
    }

    // set max deposit limit
    function setMaxLimit(uint256 _max)   external onlyOwner{
        maxLimit = _max;
    }

    // set SwapAddress
    function setSwapAddress(address _address)   external onlyOwner{
        require(_address!=address(0),"invalid address");
        busdSwapAddress = _address;
    }

    // set dao contract address
    function setDaoAddress(address _address)   external onlyOwner{
        daoAddress = _address;
    }

    function setTeamAddress(address _address) public onlyOwner{
        require(_address!=address(0),"invalid address");
        teamAddress = _address;
    }

    //deposit
    function deposit(uint256 _amount) external whenNotPaused {

        require(_amount>0, "invalid amount");
        require(maxLimit==0 || balance.add(_amount)<=maxLimit, "exceed max deposit limit");
        IERC20(want).safeTransferFrom(msg.sender, address(this), _amount);
        //deposit token to compound
        IERC20(want).safeApprove(vTokenAddress, _amount);
        require(VToken(vTokenAddress).mint(_amount) == 0, "!deposit");
        balance = balance.add(_amount);
        _mint(msg.sender, _amount);

        emit Deposit(msg.sender, _amount);
    }

    //withdraw
    function withdraw(uint256 _amount) external {
        require(_amount>0, "invalid amount");
        _burn(msg.sender, _amount);

        //redeemUnderlying
        uint256 beforeVaule = IERC20(want).balanceOf(address(this));
        require(VToken(vTokenAddress).redeemUnderlying(_amount) == 0, "!withdraw");
        uint256 afterVaule = IERC20(want).balanceOf(address(this));
        uint256 getValue = afterVaule.sub(beforeVaule);
        require(getValue>0, "invalid amount, !withdraw");

        IERC20(want).safeTransfer(msg.sender, getValue);
        balance = balance.sub(_amount);

        emit Withdraw(msg.sender, _amount);
    }

    function swapTokensToBusd(address _token) internal{
        require(busdSwapAddress!=address(0),  "not set husd swap address!");
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        if (_amount==0){
            return;
        }
        IERC20(_token).safeApprove(busdSwapAddress, _amount);
        ISwap(busdSwapAddress).swapTokensToEarnToken(_token, _amount);
    }

    //get underlying amount in compound pool
    function getSelfUnderlying() public view returns (uint256) {
        (, uint256 vTokenBalance, , uint256 exchangeRate) =  VToken(vTokenAddress).getAccountSnapshot(address(this));
        return vTokenBalance.mul(exchangeRate).div(1e18);
    }

    function harvest() public{
        harvest(true);
    }

    function harvest(bool claimCompToken) public {
        //claim interest
        uint256 _selfUnderlying = getSelfUnderlying();
        uint256 _compUnderlyingBalance = VToken(vTokenAddress).getCash();
        uint256 _interest = _selfUnderlying.sub(balance);
        if (_interest>=minClaim) {
            uint256 _claimAmount = _interest<_compUnderlyingBalance?_interest:_compUnderlyingBalance;
            require(VToken(vTokenAddress).redeemUnderlying(_claimAmount) == 0, "!redeem");
            if (want!= busd){
                swapTokensToBusd(want);
            }
        }

        if (claimCompToken) {
            //claim mining token
            address _comptrollerAddress = VToken(vTokenAddress).comptroller();
            address _compTokenAddress;

            IVenusComptroller(_comptrollerAddress).claimVenus(address(this));
            _compTokenAddress = IVenusComptroller(_comptrollerAddress).getXVSAddress();

            swapTokensToBusd(_compTokenAddress);
        }

        //donate earnToken to dao
        uint256 _earnTokenBalance = IERC20(earnToken).balanceOf(address(this));
        if (_earnTokenBalance>0) {
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
}
