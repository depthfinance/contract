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
    function claimComp(address holder, address[] memory cTokens) external;
}

interface MDexRouter {
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}

contract HandleLendPlatformToken{

    address internal _mainContractAddress;

    MDexRouter constant mdex             = MDexRouter(0xED7d5F38C79115ca12fe6C0041abb22F0A06C300);
    ERC20      constant lhb              = ERC20(0x8F67854497218043E1f72908FFE38D0Ed7F24721);
    ERC20      constant eth              = ERC20(0x64FF637fB478863B7468bc97D30a5bF3A428a1fD);
    ERC20      constant beth             = ERC20(0xB6F4c418514dd4680F76d5caa3bB42dB4A893aCb);
    ERC20      constant wht              = ERC20(0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F);
    CERC20     constant leth             = CERC20(0x505Bdd86108E7d9d662234F6a5F8A4CBAeCE81AB);
    CERC20     constant lbeth            = CERC20(0xEf4bBD27C75674A7c562d0d02E79415587c1595C);
    ERC20      constant husd             = ERC20(0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047);
    ERC20      constant usdt             = ERC20(0xa71EdC38d189767582C38A3145b5873052c3e47a);
    ClaimComp  constant claimLHBContract = ClaimComp(0x6537d6307ca40231939985BCF7D83096Dd1B4C09);

    constructor(address mainContractAddress) public {
        _mainContractAddress = mainContractAddress;
    }

    function claim_lending_platform_token() external {
        assert(msg.sender == _mainContractAddress);
        // This method calim LHB token for main contract.
        // Since this contract is replaceable, we can rewrite this method if we have to.
        address[] memory cTokens = new address[](2);
        cTokens[0] = 0x505Bdd86108E7d9d662234F6a5F8A4CBAeCE81AB; // Add lETH
        cTokens[1] = 0xEf4bBD27C75674A7c562d0d02E79415587c1595C; // Add lBETH
        claimLHBContract.claimComp(msg.sender, cTokens);
    }

    function sell_lending_platform_token(bool isCoin1, uint256 lhbAmount) external returns (uint256){
        assert(msg.sender == _mainContractAddress);
        require(lhb.transferFrom(msg.sender, address(this), lhbAmount));
        // Sell lhb for eth even the amount of eth is larger than beth's 
        // because mdex does not support beth currently.
        address[] memory path;
        path = new address[](4);
        path[0] = address(lhb);
        path[1] = address(usdt);
        path[2] = address(husd);
        path[3] = address(eth);
        lhb.approve(address(mdex), lhbAmount);
        // This action may fail beacuse lack of liqudility.
        try mdex.swapExactTokensForTokens(lhbAmount, 0, path, address(this), now) returns (uint256[] memory amounts) {
            if(amounts[1] == 0)
                return 0;
            eth.approve(address(leth),amounts[1]);
            leth.mint(amounts[1]);
            uint256 balance = leth.balanceOf(address(this));
            leth.approve(msg.sender, balance);
            return balance;
        } catch (bytes memory) {
            // Swap failed, return token back to main contract
            lhb.transfer(msg.sender, lhbAmount);
            return 0;
        }
    }
}
