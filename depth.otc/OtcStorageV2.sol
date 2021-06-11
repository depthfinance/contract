
pragma solidity ^0.8.0;
import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";



/**
 * @title OtcV1: Simple otc swap v2
 * @notice https://www.depth.fi/
 */
contract OtcStorageV2 is  Ownable {
  using SafeMath for uint256;

  bool public isPaused;
  mapping (address=>bool) public otcContracts;//ony in this list can call saveMoney function


  uint256 public totalTradeAmount;//total trade amount by husd
  uint256 public totalFeeAmount;//total fee amount by husd;




  constructor() public {

  }



  function addOtcContract(address _address) external onlyOwner {
    otcContracts[_address] = true;
  }

  function removeOtcContract(address _address) external onlyOwner {
    if (otcContracts[_address] ){
        delete otcContracts[_address];
    }
  }

    //save otc trade amount info
    function saveTradeInfo(uint256 _amount,uint256 _fee) external{
        require(!isPaused,"paused");
        //check the caller in otc contracts
        require(otcContracts[msg.sender],"invalid otc contract address");

        if(_amount<=0){
            return;
        }
        totalTradeAmount=totalTradeAmount.add(_amount);//add global trade amount;
        totalFeeAmount=totalFeeAmount.add(_fee);//add global fee amount


    }

    //return global trade datas
    function getTradeDatas() external view returns(uint256,uint256){
        return (totalTradeAmount,totalFeeAmount);

    }




}
