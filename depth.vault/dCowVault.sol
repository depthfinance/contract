pragma solidity ^0.8.0;

import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IVault.sol";
/**depth.fi vault***/
contract dCowVault is ERC20,Ownable,Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public want;
    address public husd =0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047;
    address public daoAddress=0xfbaC8c66D9B7461EEfa7d8601568887c7b6f96AD;   //DEP DAO ADDRESS
    address public husdSwapAddress;
    address public mdxAddress = 0x25D2e80cB6B86881Fd7e07dd263Fb79f4AbE033c;
    address public cowAddress = 0x80861A817106665bcA173DB6AC2ab628a738c737;
    address public cowCtrlAddress = 0x22F560e032b256e8C7Cb50253591B0850162cb74;
    uint256 public balance;//total token balance
    uint256 public minClaim=1;//min interest to claim
    uint256 public maxLimit;// max balance limit
    uint256 public cowPoolId;
    constructor (address _want,address _husdSwapAddress) ERC20(
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
        husdSwapAddress = _husdSwapAddress;

    }
    // set min claim interest
    function setMinClaim(uint256 _min)   external onlyOwner{
        minClaim = _min;
    }
    // set max deposit limit
    function setMaxLimit(uint256 _max)   external onlyOwner{
        maxLimit = _max;
    }
    // set husd swap contract address
    function setHusdSwapAddress(address _address)   external onlyOwner{
        require(_address!=address(0),"no address!");
        husdSwapAddress = _address;
    }

    // set dao contract address
    function setDaoAddress(address _address)   external onlyOwner{
        require(_address!=address(0),"no address!");
        daoAddress = _address;
    }

    function swapTokensToHusd(address _token) internal{
        require(husdSwapAddress!=address(0),"not set husd swap address!");
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        if (_amount==0){
            return;
        }
        IERC20(_token).safeApprove(husdSwapAddress,_amount);
        IHusdSwap(husdSwapAddress).swapTokensToHusd(_token,_amount);
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
        return _totalAmountLimit.sub(_totalAmount);
    }
    function harvest() public{
        //claim interest

        uint256 _mdxAmount = getMdxAmount();
        if (_mdxAmount>=minClaim){
            ICow(cowCtrlAddress).withdraw(mdxAddress,_mdxAmount);
            swapTokensToHusd(mdxAddress);
        }
        uint256 _cowAmount = getCowAmount();
        if (_cowAmount>=minClaim){
            ICow(cowCtrlAddress).withdraw(cowAddress,_cowAmount);
            swapTokensToHusd(cowAddress);
        }
        //donate husd to dao
        uint256 _husdBalance = IERC20(husd).balanceOf(address(this));
        IERC20(husd).safeApprove(daoAddress,_husdBalance);
        //call dao address donate husd
        IDao(daoAddress).donateHUSD(_husdBalance);


    }
    //deposit
    function deposit(uint256 _amount) external whenNotPaused {
        require(_amount>0,"invalid amount");

        IERC20(want).safeTransferFrom(msg.sender, address(this), _amount);
        //deposit token to compound
        IERC20(want).safeApprove(cowCtrlAddress, _amount);
        ICow(cowCtrlAddress).deposit(want,_amount);
        balance=balance.add(_amount);
        _mint(msg.sender, _amount);
    }
    //withdraw
    function withdraw(uint256 _amount) external {
        require(_amount>0,"invalid amount");
        _burn(msg.sender, _amount);
        ICow(cowCtrlAddress).withdraw(want,_amount);

        IERC20(want).safeTransfer(msg.sender, _amount);
        balance=balance.sub(_amount);

    }
    //claim exchange token like mdx to owner.
    function claimExchangeMiningToken(address _swapAddress,address _miningToken) external onlyOwner{
        require(_swapAddress!=address(0),"invalid swap address");
        require(_miningToken!=address(0),"invalid mining token address");
        ISwapMining(_swapAddress).takerWithdraw();
        IERC20(_miningToken).safeTransfer(msg.sender,IERC20(_miningToken).balanceOf(address(this)));

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
}
