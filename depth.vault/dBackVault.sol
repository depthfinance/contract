pragma solidity ^0.8.0;

import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IVault.sol";
/**depth.fi vault***/
contract dBackVault is ERC20,Ownable,Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public want;
    address public husd =0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047;
    address public daoAddress=0xfbaC8c66D9B7461EEfa7d8601568887c7b6f96AD;   //DEP DAO ADDRESS
    //address public usdtSwapAddress=0x07c8689FfC95caf92DA7Cc2A55bCbE7dAFCf0A47; //DEP swap usdt to husd
    address public husdSwapAddress;//swap compound token to husd
    uint256 public maxLimit;// max balance limit
    address public cTokenAddress;
    uint256 public balance;//total token balance
    uint256 public minClaim=1;//min interest to claim default 1
    address public blackPlatform = 0x9c5dDcD6825413c52e7DA2ADBCFD30638D3B7A0d;
    constructor (address _cTokenAddress,address _husdSwapAddress) ERC20(
        string(abi.encodePacked("Depth.Fi Vault ", ERC20(_cTokenAddress).symbol())),
        string(abi.encodePacked("d", ERC20(_cTokenAddress).symbol()))
    ) {

        require(_cTokenAddress != address(0), "INVALID CTOKEN ADDRESS");
        want  = IBack(_cTokenAddress).supplyToken();
        cTokenAddress=_cTokenAddress;
        husdSwapAddress = _husdSwapAddress;

    }
    // set min claim interest
    function setMinClaim(uint256 _min)   external onlyOwner{
        minClaim = _min;
    }

    // set husd swap contract address
    function setHusdSwapAddress(address _address)   external onlyOwner{
        husdSwapAddress = _address;
    }

    // set dao contract address
    function setDaoAddress(address _address)   external onlyOwner{
        daoAddress = _address;
    }

    // set max deposit limit
    function setMaxLimit(uint256 _max)   external onlyOwner{
        maxLimit = _max;
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

    function isCan() internal view returns(bool){
        if (cTokenAddress==0x9a57eAB16d371048c56cbE0c4D608096aEC5b405||cTokenAddress==0x3dA74C09ccb8faBa3153b7f6189dDA9d7F28156A){
            return true;
        }else{
            return false;
        }
    }

    function harvest() public{
        IBack backPool = IBack(cTokenAddress);
        //claim interest
        uint256 _selfUnderlying = getSelfUnderlying();
        uint256 _compUnderlyingBalance = backPool.getTotalShare().sub(backPool.totalBorrow()).sub(backPool.totalInterestToPay()).sub(backPool.poolReserve());
        uint256 _interest = _selfUnderlying.sub(balance);
        if (_interest>=minClaim){
            uint256 _claimAmount = _interest<_compUnderlyingBalance?_interest:_compUnderlyingBalance;
            IBack(blackPlatform).withdraw(want,_claimAmount);
            if (want!=husd){
                swapTokensToHusd(want);
            }
        }

        address _compTokenAddress = 0x6474bc11F512DfE6A5162b2167e3f94b61471d05;
        swapTokensToHusd(_compTokenAddress);

        //donate husd to dao
        uint256 _husdBalance = IERC20(husd).balanceOf(address(this));
        if (_husdBalance>0){
            IERC20(husd).approve(daoAddress,_husdBalance);
            //call dao address donate husd
            IDao(daoAddress).donateHUSD(_husdBalance);
        }


    }
    //get underlying amount in back pool
    function getSelfUnderlying() public view returns (uint256) {
        IBack backPool = IBack(cTokenAddress);
        uint256 _totalSupply = backPool.totalSupply();
        if (_totalSupply==0){
            return 0;
        }
        return IERC20(cTokenAddress).balanceOf(address(this)).mul(backPool.getTotalShare()).div(backPool.totalSupply());
    }

    //deposit
    function deposit(uint256 _amount) external whenNotPaused {
        require(_amount>0,"invalid amount");
        require(maxLimit==0||balance.add(_amount)<=maxLimit,"exceed max deposit limit");
        IERC20(want).safeTransferFrom(msg.sender, address(this), _amount);
        //deposit token to compound
        IERC20(want).safeApprove(blackPlatform, _amount);
        IBack(blackPlatform).deposit(want,_amount);
        balance=balance.add(_amount);
        _mint(msg.sender, _amount);
    }
    //withdraw
    function withdraw(uint256 _amount) external {
        require(_amount>0,"invalid amount");
        _burn(msg.sender, _amount);

        //uint256 _before = IERC20(want).balanceOf(address(this));
        //redeemUnderlying

        IBack(blackPlatform).withdraw(want,_amount) ;
        IERC20(want).safeTransfer(msg.sender, _amount);
        balance=balance.sub(_amount);

    }
    //claim exchange token like mdx to owner.
    function claimExchangeMiningToken(address _swapAddress,address _miningToken) external onlyOwner{
        require(_swapAddress!=address(0),"invalid swap address");
        require(_miningToken!=address(0),"invalid mining token address");
        ISwapMining(_swapAddress).takerWithdraw();
        require(_miningToken!=cTokenAddress,"can not claim ctoken");
        IERC20(_miningToken).safeTransfer(msg.sender,IERC20(_miningToken).balanceOf(address(this)));

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
