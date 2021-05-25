pragma solidity ^0.8.0;

import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IVault.sol";
/**depth.fi vault***/
contract dCompVault is ERC20,Ownable,Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public want;
    address public husd =0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047;
    address public usdt =0xa71EdC38d189767582C38A3145b5873052c3e47a;
    address public wht = 0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F;
    address public daoAddress=0xfbaC8c66D9B7461EEfa7d8601568887c7b6f96AD;   //DEP DAO ADDRESS
    address public usdtSwapAddress=0x07c8689FfC95caf92DA7Cc2A55bCbE7dAFCf0A47; //DEP swap usdt to husd
    address public husdSwapAddress=0xED7d5F38C79115ca12fe6C0041abb22F0A06C300;//swap compound token to husd
    address public cTokenAddress;
    uint256 public balance;//total token balance
    uint256 public minClaim=10**8;//min interest to claim default 1
    constructor (address _cTokenAddress) ERC20(
        string(abi.encodePacked("Depth.Fi Vault ", ERC20(_cTokenAddress).symbol())),
        string(abi.encodePacked("d", ERC20(_cTokenAddress).symbol()))
    ) {

        require(_cTokenAddress != address(0), "INVALID CTOKEN ADDRESS");
        want  = CToken(_cTokenAddress).underlying();
        cTokenAddress=_cTokenAddress;

    }
    // set min claim interest
    function setMinClaim(uint256 _min)   external onlyOwner{
        minClaim = _min;
    }
    // set usdt swap contract address
    function setUsdtSwapAddress(address _address)   external onlyOwner{
        usdtSwapAddress = _address;
    }
    // set husd swap contract address
    function setHusdSwapAddress(address _address)   external onlyOwner{
        husdSwapAddress = _address;
    }

    // set dao contract address
    function setDaoAddress(address _address)   external onlyOwner{
        daoAddress = _address;
    }

    function swapTokensToHusd(address _token) internal{
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        if (_amount==0){
            return;
        }
        if (_token==usdt){
            IERC20(usdt).safeApprove(usdtSwapAddress,_amount);
            UsdtSwapRouter(usdtSwapAddress).exchange_underlying(1,0,_amount,0);
        }else if(_token!=husd){
            HusdSwapRouter swap = HusdSwapRouter(husdSwapAddress);
            address[] memory path1 = new address[](2);
            path1[0] = _token;
            path1[1] = husd;
            uint256 amount1 = swap.getAmountsOut(_amount, path1)[1];
            uint256 amount2 = 0;
            address[] memory path2 = new address[](3);
            path2[0] = _token;
            path2[1] = wht;
            path2[2] = husd;
            if (_token!=wht){

                amount2 = swap.getAmountsOut(_amount, path2)[2];
            }
            address[] memory path3 = new address[](3);
            path3[0] = _token;
            path3[1] = usdt;
            path3[2] = husd;
            uint256 amount3 = swap.getAmountsOut(_amount, path3)[2];

            address[] memory path;
            if (amount1 >= amount2 && amount1 >= amount3) {
                path = path1;
            } else if (amount2 >= amount1 && amount2 >= amount3) {
                path = path2;
            } else {
                path = path3;
            }

            IERC20(_token).safeApprove(husdSwapAddress, _amount);
            swap.swapExactTokensForTokens(_amount, 0, path, address(this), block.timestamp.add(1800));
        }
    }

    function harvest() public{
        //claim interest
        uint256 _selfUnderlying = getSelfUnderlying();
        uint256 _compUnderlyingBalance = IERC20(want).balanceOf(cTokenAddress);
        uint256 _interest = _selfUnderlying.sub(balance);
        if (_interest>=minClaim){
            uint256 _claimAmount = _interest<_compUnderlyingBalance?_interest:_compUnderlyingBalance;
            require(CToken(cTokenAddress).redeemUnderlying(_claimAmount) == 0, "!redeem");
            swapTokensToHusd(want);
        }

        //claim mining token
        address[] memory markets = new address[](1);
        markets[0] = cTokenAddress;
        address _compControlAddress = CToken(cTokenAddress).comptroller();
        CompControl(_compControlAddress).claimComp(address(this), markets);
        address _compTokenAddress = CompControl(_compControlAddress).getCompAddress();
        swapTokensToHusd(_compTokenAddress);

        //donate husd to dao
        uint256 _husdBalance = IERC20(husd).balanceOf(address(this));
        IERC20(husd).approve(daoAddress,_husdBalance);
        //call dao address donate husd
        IDao(daoAddress).donateHUSD(_husdBalance);


    }
    //get underlying amount in compound pool
    function getSelfUnderlying() public view returns (uint256) {
        (, uint256 cTokenBal, , uint256 exchangeRate) =
        CToken(cTokenAddress).getAccountSnapshot(address(this));

        return cTokenBal.mul(exchangeRate).div(1e18);
    }

    //deposit
    function deposit(uint256 _amount) external whenNotPaused {
        require(_amount>0,"invalid amount");

        IERC20(want).safeTransferFrom(msg.sender, address(this), _amount);
        //deposit token to compound
        IERC20(want).safeApprove(cTokenAddress, _amount);
        require(CToken(cTokenAddress).mint(_amount) == 0, "!deposit");
        balance=balance.add(_amount);
        _mint(msg.sender, _amount);
    }
    //withdraw
    function withdraw(uint256 _amount) external {
        require(_amount>0,"invalid amount");
        _burn(msg.sender, _amount);

        //uint256 _before = IERC20(want).balanceOf(address(this));
        //redeemUnderlying

        require(CToken(cTokenAddress).redeemUnderlying(_amount) == 0, "!withdraw");
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

}
