pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FundingManager is Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct FundingHolderInfo {
        uint256 ratio;
        string name;
        address addr;
    }

    IERC20 public depToken;

    // Info of each funding.
    FundingHolderInfo[] public fundingHolders;

    constructor(IERC20 _address) public {
        depToken = _address;
    }


    //Update funding pool
    function addFunding(string memory _name, address _addr, uint256 _ratio) public onlyOwner {

        fundingHolders.push(FundingHolderInfo({
        name : _name,
        addr : _addr,
        ratio : _ratio
        }));

    }

    //Update funding pool
    function setFunding(uint256 pid, string memory _name, address _addr, uint256 _ratio) public onlyOwner {

        FundingHolderInfo storage fhi = fundingHolders[pid];

        fhi.name = _name;
        fhi.addr = _addr;
        fhi.ratio = _ratio;
    }

    // Return the pool pending balance.
    function getPendingBalance(uint256 pid) public view returns (uint256){
        FundingHolderInfo storage fhi = fundingHolders[pid];
        uint256 _balance = depToken.balanceOf(address(this));
        uint _amount = _balance.mul(fhi.ratio).div(100);
        return _amount;
    }

    function claim() public {
        uint256 _balance = depToken.balanceOf(address(this));
        for (uint256 i = 0; i < fundingHolders.length; i++) {
            FundingHolderInfo storage fhi = fundingHolders[i];
            uint _amount = _balance.mul(fhi.ratio).div(100);
            depToken.safeTransfer(fhi.addr, _amount);
        }

    }

}
