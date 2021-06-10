pragma solidity ^0.8.0;

import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IVault.sol";
/**depth.fi vault***/
contract dPilotVault is ERC20,Ownable,Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public want;
    address public husd =0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047;
    address public daoAddress=0xfbaC8c66D9B7461EEfa7d8601568887c7b6f96AD;   //DEP DAO ADDRESS
    address public husdSwapAddress;
    address public pilotAddress =0xD42Ef222d33E3cB771DdA783f48885e15c9D5CeD;
    address public pTokenAddress;
    uint256 public balance;//total token balance
    uint256 public minClaim=1;//min interest to claim
    uint256 public maxLimit;// max balance limit
    constructor (address _want,address _husdSwapAddress) ERC20(
        string(abi.encodePacked("Depth.Fi Vault p", ERC20(_want).symbol())),
        string(abi.encodePacked("dp", ERC20(_want).symbol()))
    ) {

        require(_want != address(0), "INVALID TOKEN ADDRESS");
        want  = _want;
        (,
        address _pTokenAddr,
        ,
        ,
        ,
        ,
        ,
        ,
        ,
        ) = IPilot(pilotAddress).banks(_want);
        pTokenAddress = _pTokenAddr;
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
    function getPTokenAmount(uint256 _amount) public view returns(uint256){
        uint256 total =IPilot(pilotAddress).totalToken(want);
        uint256 pTotal = IERC20(pTokenAddress).totalSupply();
        uint256 pAmount = (total == 0 || pTotal == 0) ? _amount: _amount.mul(pTotal).div(total);
        return pAmount;
    }
    function harvest() public{
        //claim interest
        uint256 _selfUnderlying = getSelfUnderlying();
        (,
        ,
        ,
        ,
        ,
        uint256 _compUnderlyingBalance,
        ,
        ,
        ,
        ) = IPilot(pilotAddress).banks(want);

        uint256 _interest = _selfUnderlying.sub(balance);
        if (_interest>=minClaim){
            uint256 _claimAmount = _interest<_compUnderlyingBalance?_interest:_compUnderlyingBalance;
            uint256 pAmount = getPTokenAmount(_claimAmount);
            uint256 _before = IERC20(want).balanceOf(address(this));
            //IERC20(pTokenAddress).safeApprove(pilotAddress, pAmount);
            IPilot(pilotAddress).withdraw(want,pAmount);
            uint256 _after = IERC20(want).balanceOf(address(this));

            require(_after.sub(_before)>_claimAmount,"sub flow!");

            swapTokensToHusd(want);
        }

        //donate husd to dao
        uint256 _husdBalance = IERC20(husd).balanceOf(address(this));
        IERC20(husd).safeApprove(daoAddress,_husdBalance);
        //call dao address donate husd
        IDao(daoAddress).donateHUSD(_husdBalance);


    }
    //get underlying amount in compound pool
    function getSelfUnderlying() public view returns (uint256) {
        uint256 pAmount = IERC20(pTokenAddress).balanceOf(address(this));
        uint256 amount = pAmount.mul(IPilot(pilotAddress).totalToken(want)).div(IERC20(pTokenAddress).totalSupply());

        return amount;
    }

    //deposit
    function deposit(uint256 _amount) external whenNotPaused {
        require(_amount>0,"invalid amount");

        IERC20(want).safeTransferFrom(msg.sender, address(this), _amount);
        //deposit token to compound
        IERC20(want).safeApprove(pilotAddress, _amount);
        IPilot(pilotAddress).deposit(want,_amount);
        balance=balance.add(_amount);
        _mint(msg.sender, _amount);
    }
    //withdraw
    function withdraw(uint256 _amount) external {
        require(_amount>0,"invalid amount");
        _burn(msg.sender, _amount);
        uint256 pAmount = getPTokenAmount(_amount);
        require(pAmount>0,"invalid pAmount");
        uint256 _before = IERC20(want).balanceOf(address(this));
        //IERC20(pTokenAddress).safeIncreaseAllowance(pilotAddress, pAmount);
        IPilot(pilotAddress).withdraw(want,pAmount);
        uint256 _after = IERC20(want).balanceOf(address(this));

        require(_after.sub(_before)>_amount,"sub flow!");

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
