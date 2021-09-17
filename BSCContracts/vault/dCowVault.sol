pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
interface IEarnTokenSwap {
    function swapTokensToEarnToken(address _token,uint256 _amount) external;
}
interface IDao {
    function donateHUSD(uint256 amount) external;
}
interface ICow{
    function poolLength() external view returns(uint256);
    function deposit(address _token, uint256 _amount) external;
    function withdraw(address _token, uint256 _amount) external;
    function pending(uint256 _poolId,address _userAddress) external view returns(uint256,uint256,uint256);
    function pendingCow(uint256 _poolId,address _userAddress) external view returns(uint256);
    function poolInfo(uint256 _poolId) external view returns(address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256);
}
interface IWbnb{
    function deposit() external payable;
    function withdraw(uint256 _amount) external;
}
/**depth.fi vault***/
contract dCowVault is ERC20,Ownable,Pausable {
    using SafeMath for uint256;

    address public want;
    address public earnToken =0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address public teamAddress=0x01D61BE40bFF0c48A617F79e6FAC6d09D7a52aAF;
    address public daoAddress;
    address public earnTokenSwapAddress;
    address public mdxAddress = 0x9C65AB58d8d978DB963e63f2bfB7121627e3a739;
    address public cowAddress = 0x422E3aF98bC1dE5a1838BE31A56f75DB4Ad43730;
    address public cowCtrlAddress = 0x52d22F040dEE3027422e837312320b42e1fD737f;
    address public wbnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    uint256 public balance;//total token balance
    uint256 public minClaim=1;//min interest to claim
    uint256 public maxLimit;// max balance limit
    uint256 public cowPoolId;
    constructor (address _want,address _earnTokenSwapAddress) ERC20(
        string(abi.encodePacked("Depth.Fi Vault Cow", ERC20(_want).symbol())),
        string(abi.encodePacked("dcow", ERC20(_want).symbol()))
    ) {

        require(_want != address(0), "INVALID TOKEN ADDRESS");
        want  = _want;
        ICow cow=ICow(cowCtrlAddress);
        uint256 _poolLength=cow.poolLength();
        bool bFound=false;
        for(uint256 i=0;i<_poolLength;i++){
            (address _token,,,,,,,,,,)=cow.poolInfo(i);
            if (want==_token){
                bFound=true;
                cowPoolId = i;
                break;
            }
        }
        require(bFound,"not supported want token!");
        earnTokenSwapAddress = _earnTokenSwapAddress;

    }
    function setTeamAddress(address _address) public onlyOwner{
        require(_address!=address(0),"invalid address");
        teamAddress = _address;
    }

    function setDaoAddress(address _address) public onlyOwner{
        require(_address!=address(0),"invalid address");
        daoAddress = _address;
    }

    // set min claim interest
    function setMinClaim(uint256 _min)   external onlyOwner{
        minClaim = _min;
    }
    // set max deposit limit
    function setMaxLimit(uint256 _max)   external onlyOwner{
        maxLimit = _max;
    }
    // set earnToken swap contract address
    function setEarnTokenSwapAddress(address _address)   external onlyOwner{
        require(_address!=address(0),"no address!");
        earnTokenSwapAddress = _address;
    }

    // set dao contract address
    function setEarnAddress(address _address)   external onlyOwner{
        require(_address!=address(0),"no address!");
        earnAddress = _address;
    }

    function swapTokensToEarnToken(address _token) internal{
        require(earnTokenSwapAddress!=address(0),"not set earnToken swap address!");
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        if (_amount==0){
            return;
        }
        IERC20(_token).approve(earnTokenSwapAddress,_amount);
        IEarnTokenSwap(earnTokenSwapAddress).swapTokensToEarnToken(_token,_amount);
    }
    function getMdxAmount() public view returns(uint256){
        (uint256 _mdxAmount,,) = ICow(cowCtrlAddress).pending(cowPoolId,address(this));
        return _mdxAmount;
    }
    function getCowAmount() public view returns(uint256){
        return ICow(cowCtrlAddress).pendingCow(cowPoolId,address(this));
    }
    function getRemaining() public view returns(uint256){
        ICow cow=ICow(cowCtrlAddress);
        (,,,,,uint256 _totalAmount,uint256 _totalAmountLimit,,,,)=cow.poolInfo(cowPoolId);
        uint256 _remaining = _totalAmountLimit.sub(_totalAmount);
        if(maxLimit>0){
            if (maxLimit<=balance){
                _remaining =0;
            }else{
                _remaining = _remaining>maxLimit.sub(balance)?maxLimit.sub(balance):_remaining;
            }
        }
        return _remaining;
    }
    function harvest() public{
        //claim interest

        uint256 _mdxAmount = getMdxAmount();
        uint256 _cowAmount = getCowAmount();
        if (_mdxAmount>=minClaim||_cowAmount>=minClaim){
            ICow(cowCtrlAddress).withdraw(want,0);
            swapTokensToEarnToken(mdxAddress);
            swapTokensToEarnToken(cowAddress);
        }
        //donate earnToken to dao
        uint256 _earnTokenBalance = IERC20(earnToken).balanceOf(address(this));
        if (_earnTokenBalance>0){
            if (daoAddress!=address(0)){
                IDao(daoAddress).donateHUSD(_earnTokenBalance);
            }else{
                IERC20(earnToken).transfer(teamAddress,_earnTokenBalance);
            }
        }


    }
    //deposit
    function deposit(uint256 _amount) external payable whenNotPaused {
        require(_amount>0,"invalid amount");
        require(getRemaining()>=_amount,"exceed max deposit limit");
        //if want is wbnb,need user to deposit bnb
        if (want==wbnb){
            require(msg.value==_amount,"invalid amount!");
            IWbnb(wbnb).deposit{value:msg.value}();
        }else{
            IERC20(want).transferFrom(msg.sender, address(this), _amount);
        }
        //deposit token to compound
        IERC20(want).approve(cowCtrlAddress, _amount);
        ICow(cowCtrlAddress).deposit(want,_amount);
        balance=balance.add(_amount);
        _mint(msg.sender, _amount);
    }
    //withdraw
    function withdraw(uint256 _amount) external {
        require(_amount>0,"invalid amount");
        _burn(msg.sender, _amount);
        ICow(cowCtrlAddress).withdraw(want,_amount);
        if (want==wbnb){
            IWbnb(wbnb).withdraw(_amount);
            payable(msg.sender).transfer(_amount);
        }else{
            IERC20(want).transfer(msg.sender, _amount);
        }
        balance=balance.sub(_amount);

    }

    function pause() external onlyOwner {
        _pause();
    }
    function decimals() public view override returns (uint8) {
        return ERC20(want).decimals();
    }


    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}
}
