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

interface ClaimCan {
    function claimCan(address holder) external;
}

interface UniswapRouter {
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function getAmountsOut(uint amountIn, address[] calldata path) external returns (uint256[] memory);
}

interface DAOPool {
    function donateHUSD(uint256 amount) external;
}

contract SellLendPlatformToken{

    UniswapRouter constant uniswap          = UniswapRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    ERC20         constant can              = ERC20(0xdE9a73272BC2F28189CE3c243e36FaFDA2485212);
    ERC20         constant busd             = ERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    ERC20         constant wbnb             = ERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    ClaimCan      constant claimCANContract = ClaimCan(0x8Cd2449Ed0469D90a7C4321DF585e7913dd6E715);

    function claim_lending_platform_token() external {
        // This method calim CAN token for main contract.
        // Since this contract is replaceable, we can rewrite this method if we have to.
        claimCANContract.claimCan(msg.sender);
    }

    function sell_lending_platform_token(uint256 amount) external returns (bool){
        require(can.transferFrom(msg.sender, address(this), amount));

        address[] memory path1 = new address[](3);
        path1[0] = address(can);
        path1[1] = address(wbnb);
        path1[2] = address(busd);
        uint256 amount1 = uniswap.getAmountsOut(amount, path1)[2];

        address[] memory path2 = new address[](2);
        path2[0] = address(can);
        path2[1] = address(busd);
        uint256 amount2 = uniswap.getAmountsOut(amount, path2)[1];

        address[] memory path;
        
        if (amount1 > amount2) {
            path = path1;
        } else {
            path = path2;
        }
        
        can.approve(address(uniswap), amount);
        try uniswap.swapExactTokensForTokens(amount, 0, path, address(this), now) returns (uint256[] memory amounts) {
            uint256 busdBalance = busd.balanceOf(address(this));
            if(busdBalance == 0)
                return true;
            busd.transfer(msg.sender, busdBalance);
            return true;
        } catch (bytes memory) {
            // swap failed, return token back to main contract
            can.transfer(msg.sender, amount);
            return true;
        }
    }
}
