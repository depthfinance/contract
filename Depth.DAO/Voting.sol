pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;



interface ERC20 {

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(address from, address to, uint256 value) external returns (bool);
    
    

}



abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract Voting is Ownable{
    
  event Vote(address indexed user, uint256 indexed index, uint16 option, uint256 votes);
    
  struct VotingInfo {
    uint256 startsAt;
    uint256 period;
    string title;
    string description;
    uint16 voteOptionsCount;
    string[] voteTitles;
    mapping (uint256 => uint256) votes;
  }

  struct UserVoting {
    uint256 index;
    uint16 voteOptionsCount;
    mapping (uint256 => uint256) votes;
  }

  mapping (uint256 => VotingInfo) public votingInfoMap;

  mapping (address => UserVoting) public userVotingMap;
  
  uint256 constant private maxPeriod = 5 minutes;
  
  uint256 public lastIndex = 0; 

  ERC20 private xDep;
  
  constructor(address tokenAddress) public{
      xDep = ERC20(tokenAddress);
  }

  function hasVotesToWithdraw(address user) public view returns (bool) {
    UserVoting memory userVoting = userVotingMap[user];
    return userVoting.index > 0 && (userVoting.index != lastIndex || !votingInProcess());
  }
  
  function votingInProcess() public view returns (bool) {
    VotingInfo memory info = votingInfoMap[lastIndex];
    return info.startsAt + info.period > now;
  }
  
  function userVoteCountForOption(address user, uint16 option) public view returns (uint256) {
    return userVotingMap[user].votes[option];
  }
  
  function voteCountForOption(uint256 round, uint16 option) public view returns (uint256) {
    return votingInfoMap[round].votes[option];
  }
  
  function voteTitleForOption(uint256 round, uint16 option) public view returns (string memory) {
    return votingInfoMap[round].voteTitles[option];
  }

  function withdrawPreviousVote() public {
    require(hasVotesToWithdraw(msg.sender), "No votes to withdraw");
    
    UserVoting storage userVoting = userVotingMap[msg.sender];
    uint256 totalVotes = 0;
    for (uint16 i = 0; i < userVoting.voteOptionsCount; i ++) {
      totalVotes += userVoting.votes[i];
      userVoting.votes[i] = 0;
    } 
    xDep.transfer(msg.sender, totalVotes);
    userVotingMap[msg.sender] = UserVoting(0, 0);
  }
  
  function vote(uint16 index, uint256 votes) public {
    // validation
    require(votingInProcess(), "No voting in process");
    require(!hasVotesToWithdraw(msg.sender), "Previous votes not withdrawed");
    VotingInfo storage info = votingInfoMap[lastIndex];
    require(info.voteOptionsCount - 1 >= index, "Out of options");
    
    // update
    UserVoting storage userVoting = userVotingMap[msg.sender];
    xDep.transferFrom(msg.sender, address(this), votes);
    if (userVoting.index != lastIndex) {
        userVoting.index = lastIndex;
        userVoting.voteOptionsCount = info.voteOptionsCount;
    }
    userVoting.votes[index] += votes;
    info.votes[index] += votes;
    
    emit Vote(msg.sender, lastIndex, index, votes);
  }

  function startNewVoting(uint256 period, string memory title, string memory description, string[] memory voteTitles, uint16 optionsCount) public onlyOwner {
    require(period <= maxPeriod, "Maximum period exceeded");
    require(period > 0, "Period must be larger than 0");
    require(!votingInProcess(), "There is a pending voting");
    require(optionsCount >= 1, "At least one options are needed");
    require(voteTitles.length == optionsCount, "Inconsistence");
    
    lastIndex += 1;
    VotingInfo memory info = VotingInfo(now, period, title, description, optionsCount, voteTitles);
    votingInfoMap[lastIndex] = info;
  }
  
}
