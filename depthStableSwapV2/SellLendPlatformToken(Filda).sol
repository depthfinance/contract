pragma solidity 0.6.12;

library SafeMath {

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0)
            return 0;
        uint256 c = a * b;
        require(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0);
        uint256 c = a / b;
        return c;
    }

    function divCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0);
        uint256 c = a / b;
        if(a % b != 0)
            c = c + 1;
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;
        return c;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);
        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }

    int256 constant private INT256_MIN = -2^255;

    function mul(int256 a, int256 b) internal pure returns (int256) {
        if (a == 0)
            return 0;
        int256 c = a * b;
        require(c / a == b && (a != -1 || b != INT256_MIN));
        return c;
    }

    function div(int256 a, int256 b) internal pure returns (int256) {
        require(b != 0 && (b != -1 || a != INT256_MIN));
        int256 c = a / b;
        return c;
    }

    function sub(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a - b;
        require((b >= 0 && c <= a) || (b < 0 && c > a));
        return c;
    }

    function add(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a + b;
        require((b >= 0 && c >= a) || (b < 0 && c < a));
        return c;
    }

    function sqrt(int256 x) internal pure returns (int256) {
        int256 z = add(x / 2, 1);
        int256 y = x;
        while (z < y)
        {
            y = z;
            z = ((add((x / z), z)) / 2);
        }
        return y;
    }
}

interface ERC20 {
    using SafeMath for uint256;

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(address from, address to, uint256 value) external returns (bool);

}

interface CERC20 is ERC20 {
    function mint(uint256) external returns (uint256);
}

interface ClaimComp is ERC20 {
    function claimComp(address holder) external;
}

interface MDexRouter {
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function getAmountsOut(uint amountIn, address[] calldata path) external returns (uint256[] memory);
}

contract SellLendPlatformToken{

    MDexRouter constant mdex             = MDexRouter(0xED7d5F38C79115ca12fe6C0041abb22F0A06C300);
    ERC20      constant filda = ERC20(0xE36FFD17B2661EB57144cEaEf942D95295E637F0);
    ERC20      constant husd             = ERC20(0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047);
    ERC20      constant usdt             = ERC20(0xa71EdC38d189767582C38A3145b5873052c3e47a);
    ERC20      constant wht              = ERC20(0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F);
    CERC20     constant lhusd            = CERC20(0x1C478D5d1823D51c4c4b196652912A89D9b46c30);
    CERC20     constant lusdt            = CERC20(0xc502F3f6f1b71CB7d856E70B574D27d942C2993C);
    ClaimComp  constant claimFILDAContract = ClaimComp(0xb74633f2022452f377403B638167b0A135DB096d);

    function claim_lending_platform_token() external {
        claimFILDAContract.claimComp(msg.sender);
    }

    function sell_lending_platform_token(uint256 amount) external returns (bool){
        require(filda.transferFrom(msg.sender, address(this), amount));
        address[] memory path;
        path = new address[](2);
        path[0] = address(filda);
        path[1] = address(husd);
        filda.approve(address(mdex), amount);
        // Try to swap FILDA for fHUSD or fUSDT. This action may fail beacuse lack of liqudility.
        try mdex.swapExactTokensForTokens(amount, 0, path, address(this), now) returns (uint256[] memory amounts) {
            uint256 husdBalance = husd.balanceOf(address(this));
            if(husdBalance == 0) 
                return true;
            husd.transfer(msg.sender, husdBalance);
            return true;
        } catch (bytes memory) {
            // swap failed, return token back to sender
            filda.transfer(msg.sender, amount);
            return true;
        }
    }
}
