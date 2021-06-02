pragma solidity ^0.8.0;

import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface UsdtSwapRouter {
    function exchange_underlying(int128, int128, uint256, uint256) external;
}
interface HusdSwapRouter {
    function getAmountsOut(uint amountIn, address[] calldata path) external returns (uint256[] memory);
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}
/**depth.fi vault***/
contract husdSwap is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public husd =0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047;
    address public usdt =0xa71EdC38d189767582C38A3145b5873052c3e47a;
    address public wht = 0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F;
    address public usdtSwapAddress=0x07c8689FfC95caf92DA7Cc2A55bCbE7dAFCf0A47; //DEP swap usdt to husd
    address public husdSwapAddress=0xED7d5F38C79115ca12fe6C0041abb22F0A06C300;//swap compound token to husd
    constructor () public {

    }

    // set usdt swap contract address
    function setUsdtSwapAddress(address _address)   external onlyOwner{
        usdtSwapAddress = _address;
    }
    // set husd swap contract address
    function setHusdSwapAddress(address _address)   external onlyOwner{
        husdSwapAddress = _address;
    }


    function swapTokensToHusd(address _token,uint256 _amount) external{
        if (_amount==0){
            return;
        }
        uint256 _beforeHusdBalance = IERC20(husd).balanceOf(address(this));
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

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
        uint256 _afterHusdBalance = IERC20(husd).balanceOf(address(this)).sub(_beforeHusdBalance);
        if(_afterHusdBalance>0){
            IERC20(husd).safeTransfer(msg.sender, _afterHusdBalance);
        }
    }


}
