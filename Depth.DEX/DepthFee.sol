pragma solidity ^0.8.0;

import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


interface depthStableSwapRouter {
    function exchange_underlying(int128, int128, uint256, uint256) external;
    function get_dy_underlying( int128, int128,  uint256) external view returns(uint256);
}

interface dexSwapRouter {
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}

interface IDao {
    function donateHUSD(uint256 amount) external;
}

contract GetDepthFee is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address constant public husd =0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047;
    address constant public usdt =0xa71EdC38d189767582C38A3145b5873052c3e47a;
    address public daoAddress=0xfbaC8c66D9B7461EEfa7d8601568887c7b6f96AD;                       //dao address
    address public depthStableSwapAddress =0x1D1cF3b43bC54B7D8e0F763B6b8957F480367834;//usdt to husd
    address public dexAddress= 0xED7d5F38C79115ca12fe6C0041abb22F0A06C300; //swap other token fee to husd

    function swapTokensToUsd(address[] memory _tokens) public{
        for(uint i=0;i<_tokens.length;i++){
            if (_tokens[i]!=address(0)){
                swapTokenToHusd(_tokens[i]);
            }
        }
    }
    function swapTokenToHusd(address _token) public{
        require(_token != address(0), "INVALID ADDRESS");

        if (_token == usdt){ // swap usdt to husd
            uint256 usdtAmount = IERC20(usdt).balanceOf(address(this));
            IERC20(usdt).safeApprove(depthStableSwapAddress, usdtAmount);
            depthStableSwapRouter(depthStableSwapAddress).exchange_underlying(1, 0, usdtAmount, 0);
        }else if (_token != husd) {  // swap other token to husd

            uint256 _amountIn = IERC20(_token).balanceOf(address(this));
            address[] memory _sellPath = new address[](2);
            _sellPath[0]=_token;
            _sellPath[1]=husd;
            IERC20(_token).safeApprove(dexAddress, _amountIn);
            dexSwapRouter(dexAddress).swapExactTokensForTokens(_amountIn, 0, _sellPath, address(this), block.timestamp.add(1800));
        }

        uint256 feeHusdAmount = IERC20(husd).balanceOf(address(this));
        if (feeHusdAmount>0){
            IERC20(husd).safeApprove(daoAddress,feeHusdAmount);
            IDao(daoAddress).donateHUSD(feeHusdAmount);
        }
    }

    //withdraw
    function withdraw(address _token) public onlyOwner {
        require(_token != address(0), "INVALID ADDRESS");
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        require(_amount>0,"invalid amount");

        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function withdrawAmount(address _token, uint256 _amount) public onlyOwner {
        require(_token != address(0), "INVALID ADDRESS");
        uint256 _amountBalance = IERC20(_token).balanceOf(address(this));
        require(_amount>0,"invalid amount");
        require(_amountBalance>=_amount,"invalid amount");

        IERC20(_token).safeTransfer(msg.sender, _amount);
    }


    function setDaoAddress(address _address) public onlyOwner {
        require(_address != address(0), "INVALID ADDRESS");
        daoAddress = _address;
    }

    function setDexAddress(address _address) public onlyOwner {
        require(_address != address(0), "INVALID ADDRESS");
        dexAddress = _address;
    }

    function setdepthStableSwapAddress(address _address) public onlyOwner {
        require(_address != address(0), "INVALID ADDRESS");
        depthStableSwapAddress = _address;
    }
}
