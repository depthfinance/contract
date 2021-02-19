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

interface ClaimCan is ERC20 {
    function claimCan(address holder) external;
}

interface MDexRouter {
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}

contract HandleCan{

    address internal _mainContractAddress;

    MDexRouter constant mdex = MDexRouter(0xED7d5F38C79115ca12fe6C0041abb22F0A06C300);
    ERC20      constant can = ERC20(0x1e6395E6B059fc97a4ddA925b6c5ebf19E05c69f);
    ERC20      constant husd = ERC20(0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047);
    ERC20      constant usdt = ERC20(0xa71EdC38d189767582C38A3145b5873052c3e47a);
    ERC20      constant wht = ERC20(0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F);
    CERC20     constant chusd = CERC20(0x9a57eAB16d371048c56cbE0c4D608096aEC5b405);
    CERC20     constant cusdt = CERC20(0x3dA74C09ccb8faBa3153b7f6189dDA9d7F28156A);
    ClaimCan   constant claimCanContract = ClaimCan(0x8955aeC67f06875Ee98d69e6fe5BDEA7B60e9770);

    constructor(address mainContractAddress) public {
        _mainContractAddress = mainContractAddress;
    }

    function claim_CAN() external {
        assert(msg.sender == _mainContractAddress);
        // This method calim CAN token for main contract.
        // Since this contract is replaceable, we can rewrite this method if we have to.
        claimCanContract.claimCan(msg.sender);
    }

    function swap_CAN_to_cToken(bool is_HUSD, uint256 canAmount) external returns (uint256){
        assert(msg.sender == _mainContractAddress);
        require(can.transferFrom(msg.sender, address(this), canAmount));
        address[] memory path = new address[](3);
        path[0] = address(can);
        path[1] = address(wht);
        path[2] = is_HUSD ? address(husd) : address(usdt);
        can.approve(address(mdex), canAmount);
        // Try to swap CAN for cHUSD or cUSDT. This action may fail beacuse lack of liqudility.
        try mdex.swapExactTokensForTokens(canAmount, 0, path, address(this), now) returns (uint256[] memory amounts) {
            if(amounts[2]==0)
                return 0;
            if (is_HUSD) {
                husd.approve(address(chusd),amounts[2]);
                uint256 minted= chusd.mint(amounts[2]);
                chusd.approve(msg.sender, minted);
                return minted;
            } else{
                usdt.approve(address(cusdt),amounts[2]);
                uint256 minted= cusdt.mint(amounts[2]);
                cusdt.approve(msg.sender, minted);
                return minted;
            }
        } catch (bytes memory) {
            // swap failed, return token back to main contract
            can.transfer(msg.sender, canAmount);
            return 0;
        }
    }
}
