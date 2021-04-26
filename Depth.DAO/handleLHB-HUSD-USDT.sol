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
    function redeem(uint256 redeemTokens) external returns (uint256);
    
}

interface ClaimComp is ERC20 {
    function claimComp(address holder, address[] memory cTokens) external;
}

interface MDexRouter {
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}

interface DAOPool {
    function donateHUSD(uint256 amount) external;
}

interface StableSwap {
    function owner() external view returns (address);
    function commit_transfer_ownership(address _owner) external;
    function apply_transfer_ownership() external;
    function withdraw_admin_fees() external;
    function coins(int128) external pure returns (address);
    function get_dy(int128 a, int128 b, uint256 c) external view returns (uint256);
    function handle_lend_contract_address() external view returns (address);
    function underlying_coins(int128) external view returns (address);
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
}

contract StableSwapOwnerSettable {
    
    address public admin;
    
    address public stableSwap;
    
    function setStableSwapOwnerStep1(address onwer) public {
        require(msg.sender == admin);
        StableSwap(stableSwap).commit_transfer_ownership(onwer);
    }
    
    function setStableSwapOwnerStep2() public {
        require(msg.sender == admin);
        StableSwap(stableSwap).apply_transfer_ownership();
    }
    
}

contract HandleLendPlatformToken is StableSwapOwnerSettable{

    address public mainContractAddress;
    
    address public daoPoolAddress;

    MDexRouter constant mdex             = MDexRouter(0xED7d5F38C79115ca12fe6C0041abb22F0A06C300);
    ERC20      constant lhb              = ERC20(0x8F67854497218043E1f72908FFE38D0Ed7F24721);
    ERC20      constant HUSD             = ERC20(0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047);
    ERC20      constant usdt             = ERC20(0xa71EdC38d189767582C38A3145b5873052c3e47a);
    ERC20      constant wht              = ERC20(0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F);
    ClaimComp  constant claimLHBContract = ClaimComp(0x6537d6307ca40231939985BCF7D83096Dd1B4C09);
    
    CERC20     private cHUSD;
    CERC20     private cUSDT;

    constructor(address _mainContractAddress, address _daoPoolAddress) public {
        admin = msg.sender;
        
        mainContractAddress = _mainContractAddress;
        daoPoolAddress = _daoPoolAddress;
        cHUSD = CERC20(StableSwap(_mainContractAddress).coins(0));
        cUSDT = CERC20(StableSwap(_mainContractAddress).coins(1));
    }
    
    function setDaoPoolAddress(address _daoPoolAddress) public {
        require(msg.sender == admin, "Not Admin");
        daoPoolAddress = _daoPoolAddress;
    }

    function claim_lending_platform_token() external {
        assert(msg.sender == mainContractAddress);
        // This method calim LHB token for main contract.
        // Since this contract is replaceable, we can rewrite this method if we have to.
        address[] memory cTokens = new address[](2);
        cTokens[0] = 0x1C478D5d1823D51c4c4b196652912A89D9b46c30; // Add lHUSD
        cTokens[1] = 0xc502F3f6f1b71CB7d856E70B574D27d942C2993C; // Add lUSDT
        claimLHBContract.claimComp(msg.sender, cTokens);
    }
    
    function _convert_lending_platform_token_for_HUSD(uint256 lhbAmount) private {
        assert(msg.sender == mainContractAddress);
        require(lhb.transferFrom(msg.sender, address(this), lhbAmount));
        address[] memory path = new address[](2);
        path[0] = address(lhb);
        path[1] = address(HUSD);
        lhb.approve(address(mdex), lhbAmount);
        // Try to swap LHB for HUSD. This action may fail beacuse lack of liqudility.
        try mdex.swapExactTokensForTokens(lhbAmount, 0, path, address(this), now) {} 
        catch (bytes memory) {
            // swap failed, return token back to main contract
            lhb.transfer(msg.sender, lhbAmount);
        }
    }

    function sell_lending_platform_token(bool is_HUSD, uint256 lhbAmount) external returns (uint256){
        assert(msg.sender == mainContractAddress);
        _convert_lending_platform_token_for_HUSD(lhbAmount);
        
        StableSwap con = StableSwap(mainContractAddress);
        con.withdraw_admin_fees();
        uint256 cUSDTBalance = cUSDT.balanceOf(address(this));
        if (con.get_dy(1, 0, cUSDTBalance) > 0) {
            cUSDT.approve(mainContractAddress, cUSDTBalance);
            con.exchange(1, 0, cUSDTBalance, 0);
        }
        uint256 cHUSDBalance = cUSDT.balanceOf(address(this));
        if (cHUSDBalance > 0) {
            cHUSD.approve(address(cHUSD), cUSDTBalance);
            cHUSD.redeem(cHUSDBalance);
        }
        uint256 HUSDBalance = HUSD.balanceOf(address(this));
        HUSD.approve(daoPoolAddress, HUSDBalance);
        DAOPool(daoPoolAddress).donateHUSD(HUSDBalance);
        return 0;
    }
}
