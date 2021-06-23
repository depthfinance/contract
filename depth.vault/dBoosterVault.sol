pragma solidity ^0.8.0;

import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IVault.sol";
/**depth.fi vault***/
contract dBoosterVault is ERC20,Ownable,Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public want;
    address public husd =0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047;
    address public daoAddress=0xfbaC8c66D9B7461EEfa7d8601568887c7b6f96AD;   //DEP DAO ADDRESS
    address public husdSwapAddress;
    address public boosterSafeBox;
    address public boosterTokenAddress=0xff96dccf2763D512B6038Dc60b7E96d1A9142507;
    address public boosterStakeAddress=0xBa92b862ac310D42A8a3DE613dcE917d0d63D98c;
    uint256 public balance;//total token balance
    uint256 public minClaim=1;//min interest to claim
    uint256 public maxLimit;// max balance limit
    constructor (address _boosterSafeBox,address _husdSwapAddress) ERC20(
        string(abi.encodePacked("Depth.Fi Vault ", ERC20(_boosterSafeBox).symbol())),
        string(abi.encodePacked("d", ERC20(_boosterSafeBox).symbol()))
    ) {

        require(_boosterSafeBox != address(0), "INVALID BOOSTER POOL ADDRESS");
        want  = IBooster(_boosterSafeBox).token();

        boosterSafeBox = _boosterSafeBox;
        husdSwapAddress = _husdSwapAddress;

    }
    function getBoosterStakePoolId() public view returns(uint256){
        return IBooster(boosterSafeBox).poolDepositId();
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

    //convert base token amount to bof lp token amount.
    function getBofTokenAmount(uint256 _amount) public view returns(uint256){
        return _amount.mul(10**18).div(IBooster(boosterSafeBox).getBaseTokenPerLPToken());
    }
    function harvest() public{
        //claim interest
        uint256 _selfUnderlying = getSelfUnderlying();

        uint256 _interest = _selfUnderlying.sub(balance);
        if (_interest>=minClaim){

            uint256 bofTokenAmount = getBofTokenAmount(_interest);
            IBoosterStakePool(boosterStakeAddress).withdraw(getBoosterStakePoolId(),bofTokenAmount);
            //withdraw base token

            IBooster(boosterSafeBox).withdraw(bofTokenAmount);

            require(getSelfUnderlying()>=balance,"not enough balance!");
            if (want!=husd){
                swapTokensToHusd(want);
            }

        }
        //claim boo
        IBoosterStakePool(boosterStakeAddress).claim(getBoosterStakePoolId());
        swapTokensToHusd(boosterTokenAddress);
        //donate husd to dao
        uint256 _husdBalance = IERC20(husd).balanceOf(address(this));
        IERC20(husd).safeApprove(daoAddress,_husdBalance);
        //call dao address donate husd
        IDao(daoAddress).donateHUSD(_husdBalance);


    }
    //get underlying amount in compound pool
    function getSelfUnderlying() public view returns (uint256) {
        uint256 bofTokenAmount = IBoosterStakePool(boosterStakeAddress).getATUserAmount(getBoosterStakePoolId(),address(this));
        uint256 amount = bofTokenAmount.mul(IBooster(boosterSafeBox).getBaseTokenPerLPToken()).div(10**18);

        return amount;
    }

    //deposit
    function deposit(uint256 _amount) external whenNotPaused {
        require(_amount>0,"invalid amount");
        require(maxLimit==0||balance.add(_amount)<=maxLimit,"exceed max deposit limit");
        IERC20(want).safeTransferFrom(msg.sender, address(this), _amount);
        //deposit token to compound
        IERC20(want).safeApprove(boosterSafeBox, _amount);
        IBooster(boosterSafeBox).deposit(_amount);
        //stake bofToken
        uint256 bofTokenAmount = IERC20(boosterSafeBox).balanceOf(address(this));
        IERC20(boosterSafeBox).safeApprove(boosterStakeAddress, bofTokenAmount);
        IBoosterStakePool(boosterStakeAddress).deposit(getBoosterStakePoolId(),bofTokenAmount);
        balance=balance.add(_amount);
        _mint(msg.sender, _amount);
    }
    //withdraw
    function withdraw(uint256 _amount) external {
        require(_amount>0,"invalid amount");
        _burn(msg.sender, _amount);
        uint256 bofTokenAmount = getBofTokenAmount(_amount);
        require(bofTokenAmount>0,"invalid amount");
        //unstake bof token
        IBoosterStakePool(boosterStakeAddress).withdraw(getBoosterStakePoolId(),bofTokenAmount);
        //withdraw base token
        uint256 _before = IERC20(want).balanceOf(address(this));
        //IERC20(pTokenAddress).safeIncreaseAllowance(pilotAddress, pAmount);
        IBooster(boosterSafeBox).withdraw(bofTokenAmount);
        uint256 _after = IERC20(want).balanceOf(address(this));

        require(_after.sub(_before)>=_amount,"sub flow!");

        IERC20(want).safeTransfer(msg.sender, _amount);
        balance=balance.sub(_amount);

    }
    //claim exchange token like mdx to owner.
    function claimExchangeMiningToken(address _swapAddress,address _miningToken) external onlyOwner{
        require(_swapAddress!=address(0),"invalid swap address");
        require(_miningToken!=address(0),"invalid mining token address");
        require(_miningToken!=boosterSafeBox,"can not claim bof token");
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
