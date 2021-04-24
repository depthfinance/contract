pragma solidity 0.8.3;

interface StableSwap {
    function commit_transfer_ownership(address _owner) external;
    function apply_transfer_ownership() external;
    function withdraw_admin_fees() external;
    function coins(uint256 _index) external view returns (address);
    function handle_lend_contract_address() external view returns (address);
    function underlying_coins(uint256 _index) external view returns (address);
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
}

interface ERC20 {
    function balanceOf(address add) external view returns (uint256);
    function transfer(address _to, uint256 _value) external returns (bool);
    function approve(address _spender, uint256 _value) external returns (bool);
}

interface cERC20 is ERC20 {
    function redeem(uint256 redeemTokens) external returns (uint256);
}
    

// Do not change this contract
// Contract that inherits from this contract can set the owner of StableSwap if itself is the owner of StableSwap
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

contract AutoOwner is StableSwapOwnerSettable {
    
    address public daoAddress;
    
    cERC20 private cHUSD;
    
    cERC20 private cUSDT;
    
    ERC20 private HUSD;
    
    constructor(address _stableSwap, address _daoAddress) public {
        admin = msg.sender;
        stableSwap = _stableSwap;
        daoAddress = _daoAddress;
        cHUSD = cERC20(StableSwap(_stableSwap).coins(0));
        cUSDT = cERC20(StableSwap(_stableSwap).coins(1));
        HUSD = ERC20(StableSwap(_stableSwap).coins(1));
    }
    
    function withdrawAdminFee() public {
        StableSwap con = StableSwap(stableSwap);
        require(msg.sender == con.handle_lend_contract_address());
        con.withdraw_admin_fees();
        uint256 cUSDTBalance = cERC20(con.coins(1)).balanceOf(address(this));
        cERC20(con.coins(1)).approve(stableSwap, cUSDTBalance);
        con.exchange(1, 0, cUSDTBalance, 0);
        cERC20 cHUSD = cERC20(con.coins(0));
        uint256 HUSDReddemed = cHUSD.redeem(cHUSD.balanceOf(address(this)));
        ERC20(con.underlying_coins(0)).transfer(daoAddress, HUSDReddemed);
    }
    
}
