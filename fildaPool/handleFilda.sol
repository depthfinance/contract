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
}

contract HandleFILDA{

    address internal _mainContractAddress;

    MDexRouter constant mdex = MDexRouter(0xED7d5F38C79115ca12fe6C0041abb22F0A06C300);
    ERC20      constant filda = ERC20(0xE36FFD17B2661EB57144cEaEf942D95295E637F0);
    ERC20      constant husd = ERC20(0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047);
    ERC20      constant usdt = ERC20(0xa71EdC38d189767582C38A3145b5873052c3e47a);
    ERC20      constant wht = ERC20(0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F);
    CERC20     constant fhusd = CERC20(0xB16Df14C53C4bcfF220F4314ebCe70183dD804c0);
    CERC20     constant fusdt = CERC20(0xAab0C9561D5703e84867670Ac78f6b5b4b40A7c1);
    ClaimComp  constant claimFILDAContract = ClaimComp(0xb74633f2022452f377403B638167b0A135DB096d);

    constructor(address mainContractAddress) public {
        _mainContractAddress = mainContractAddress;
    }

    function claim_FILDA() external {
        assert(msg.sender == _mainContractAddress);
        // This method calim FILDA token for main contract.
        // Since this contract is replaceable, we FILDA rewrite this method if we have to.
        claimFILDAContract.claimComp(msg.sender);
    }

    function swap_FILDA_to_fToken(bool is_HUSD, uint256 fildaAmount) external returns (uint256){
        assert(msg.sender == _mainContractAddress);
        require(filda.transferFrom(msg.sender, address(this), fildaAmount));
        address[] memory path;
        if (is_HUSD) {
            path = new address[](2);
            path[0] = address(filda);
            path[1] = address(husd);
        } else{
            path = new address[](3);
            path[0] = address(filda);
            path[1] = address(wht);
            path[2] = address(usdt);
        }
        filda.approve(address(mdex), fildaAmount);
        // Try to swap FILDA for fHUSD or fUSDT. This action may fail beacuse lack of liqudility.
        try mdex.swapExactTokensForTokens(fildaAmount, 0, path, address(this), now) returns (uint256[] memory amounts) {
            if (is_HUSD) {
                if(amounts[1] == 0)
                    return 0;
                husd.approve(address(fhusd),amounts[1]);
                fhusd.mint(amounts[1]);
                uint256 balance = fhusd.balanceOf(address(this));
                fhusd.approve(msg.sender, balance);
                return balance;
            } else{
                if(amounts[2] == 0)
                    return 0;
                usdt.approve(address(fusdt),amounts[2]);
                fusdt.mint(amounts[2]);
                uint256 balance = fusdt.balanceOf(address(this));
                fusdt.approve(msg.sender, balance);
                return balance;
            }
        } catch (bytes memory) {
            // swap failed, return token back to main contract
            filda.transfer(msg.sender, fildaAmount);
            return 0;
        }
    }
}
