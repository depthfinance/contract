
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IOtcV1.sol";

/**
 * @title OtcV1: Simple otc swap v1
 * @notice https://www.depth.fi/
 */
contract DepthOtcV1 is IOtcV1, Ownable {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  struct FeeInfo{
	uint256 stakeAmount;
	uint256 feeRate;
  }
  bool public isPaused;
  FeeInfo[] public feeInfo;
 

  bytes32 public constant DOMAIN_TYPEHASH =
    keccak256(
      abi.encodePacked(
        "EIP712Domain(",
        "string name,",
        "string version,",
        "uint256 chainId,",
        "address verifyingContract",
        ")"
      )
    );

  bytes32 public constant OTC_ORDER_TYPEHASH =
    keccak256(
      abi.encodePacked(
        "OtcOrder(",
        "uint256 nonce,",
        "uint256 expiry,",
        "address makerAddress,",
        "address makerToken,",
        "uint256 makerAmount,",
        "address takerAddress,",
        "address takerToken,",
        "uint256 takerAmount",
        ")"
      )
    );

  bytes32 public constant DOMAIN_NAME = keccak256("DepthOtcV1");
  bytes32 public constant DOMAIN_VERSION = keccak256("3");
  uint256 public immutable DOMAIN_CHAIN_ID;
  bytes32 public immutable DOMAIN_SEPARATOR;

  uint256 public constant FEE_DIVISOR = 100000;
  uint256 public stakeTokenDecimal = 10**18;
  
  address public husd ;
  address public usdt ;
  
 
  mapping(address => mapping(uint256 => uint256)) internal _nonceGroups;

  mapping(address => address) public override authorized;

  address public stakeTokenAddress;//xdep address
  address public usdtSwapAddress; //convert usdt to husd
  address public storageContractAddress;
  address public husdSwapAddress;//neet to convert taker token to husd
  address public daoAddress;

  constructor(address _stakeTokenAddress, address _storageContractAddress,address _usdtToken,address _husdToken,address _usdtSwapAddress,address _husdSwapAddress,address _daoAddress) public {
    // Ensure the fee wallet is not null
    require(_usdtToken != address(0), "INVALID_USDT_Token_address");
    require(_husdToken != address(0), "invalid husd token address");
    require(_usdtSwapAddress != address(0), "INVALID_USDT_swap_address");
    require(_husdSwapAddress != address(0), "INVALID_husd_swap_address");
    require(_daoAddress != address(0), "INVALID_dao_address");
    uint256 currentChainId = getChainId();
    DOMAIN_CHAIN_ID = currentChainId;
    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        DOMAIN_TYPEHASH,
        DOMAIN_NAME,
        DOMAIN_VERSION,
        currentChainId,
        this
      )
    );
    husd=_husdToken;
    usdt=_usdtToken;
    stakeTokenAddress = _stakeTokenAddress;
    storageContractAddress= _storageContractAddress;
    usdtSwapAddress = _usdtSwapAddress;
    husdSwapAddress = _husdSwapAddress;
    daoAddress = _daoAddress;
  }
    
  

  /**
   * @notice Atomic Token Swap with Recipient
   * @param nonce uint256 Unique and should be sequential
   * @param expiry uint256 Expiry in seconds since 1 January 1970
   * @param makerAddress address Wallet of the signer
   * @param makerToken address ERC20 token transferred from the signer
   * @param makerAmount uint256 Amount transferred from the signer
   * @param takerAddress Wallet of the sender
   * @param takerToken address ERC20 token transferred from the sender
   * @param takerAmount uint256 Amount transferred from the sender
   * @param v uint8 "v" value of the ECDSA signature
   * @param r bytes32 "r" value of the ECDSA signature
   * @param s bytes32 "s" value of the ECDSA signature
   */
  function swap(
    uint256 nonce,
    uint256 expiry,
    address makerAddress,
    IERC20 makerToken,
    uint256 makerAmount,
    address takerAddress,
    IERC20 takerToken,
    uint256 takerAmount,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public override {
      require(isPaused==false, "contract is paused");
    require(DOMAIN_CHAIN_ID == getChainId(), "CHAIN_ID_CHANGED");

    // Ensure the expiry is not passed
    require(expiry > block.timestamp, "EXPIRY_PASSED");
    //if takerAddress is not zero.check the taker address
    if (takerAddress!=address(0)) {
        require(msg.sender == takerAddress, "invalid taker address");
    }
    bytes32 hashed =
      _getOrderHash(
        nonce,
        expiry,
        makerAddress,
        makerToken,
        makerAmount,
        takerAddress,
        takerToken,
        takerAmount
      );

    // Recover the signatory from the hash and signature
    address signatory = _getSignatory(hashed, v, r, s);

    // Ensure the nonce is not yet used and if not mark it used
    require(_markNonceAsUsed(signatory, nonce), "NONCE_ALREADY_USED");

    // Ensure the signatory is authorized by the signer wallet
    if (makerAddress != signatory) {
      require(authorized[makerAddress] == signatory, "UNAUTHORIZED");
    }

    // Transfer token from taker to maker
    takerToken.safeTransferFrom(msg.sender, makerAddress, takerAmount);
    //transfer token from taker to contract.
    makerToken.safeTransfer(address(this), makerAmount);
    uint256 _feeAmount=_dealFee(makerAddress,makerToken,makerAmount,takerToken);
    

    // Emit a Swap event
    emit Swap(
      nonce,
      block.timestamp,
      makerAddress,
      makerToken,
      makerAmount,
      msg.sender,
      takerToken,
      takerAmount,
      _feeAmount
    );
  }
  //deal fee and return taker amount fee
  function _dealFee(address makerAddress,IERC20 makerToken,uint256 makerAmount,IERC20 takerToken) internal returns(uint256){
       //cal taker fee rate
    uint256 _feeRate =getFeeRate(msg.sender);
    uint256 _feeAmout = _feeRate.div(FEE_DIVISOR).mul(makerAmount);
    
    // Transfer left token from maker to taker
    makerToken.safeTransferFrom(address(this), msg.sender, makerAmount.sub(_feeAmout));
    //cal husd fee
    uint256 husdFee = 0;
    uint256 husdAmount = 0;
    //if fee token is husd
    if (address(makerToken)==husd){
        husdFee = _feeAmout;
    }else{
        //husd balance before swap
        uint256 _beforeBalance = IERC20(husd).balanceOf(address(this));
        if(address(makerToken)==usdt){
            //swap usdt to husd
            UsdtSwapRouter(usdtSwapAddress).exchange_underlying(1,0,_feeAmout,0);
        }else{
            //swap other token to husd
            //first transfer left amount to contract
            makerToken.safeTransferFrom(makerAddress, address(this), _feeAmout);
            
            
            address[] memory path = new address[](2);
            path[0] = address(makerToken);
            path[1] = husd;
    
            makerToken.approve(address(husdSwapAddress), _feeAmout);
            
            HusdSwapRouter(husdSwapAddress).swapExactTokensForTokens(_feeAmout, 0, path, address(this), block.timestamp);
        }
        //husd fee = current husd balance - before
        husdFee = IERC20(husd).balanceOf(address(this)).sub(_beforeBalance);
        
    }
    //call storage contract to save data and send husd fee to dao
    if (husdFee>0){
        husdAmount = husdFee.mul(FEE_DIVISOR).div(_feeRate);
        //save trade info to storage contract
        IStorage(storageContractAddress).saveTradeInfo(makerAddress,msg.sender,address(makerToken),address(takerToken),husdAmount,husdFee );
        IERC20(husd).approve(daoAddress,husdFee);
        //call dao address donate husd
        IDao(daoAddress).donateHUSD(husdFee);
    }
    return _feeAmout;
    
  }


// set contract paused or not    
  function setPaused(bool b)   external onlyOwner{
      isPaused = b ;
  }
  
  // set stake token address
  function setStakeTokenAddress(address _address)   external onlyOwner{
      stakeTokenAddress = _address;
  }
  
  // set storage contract address
  function setStorageContractAddress(address _address)   external onlyOwner{
      storageContractAddress = _address;
  }
  // set usdt swap contract address
  function setUsdtSwapAddress(address _address)   external onlyOwner{
      usdtSwapAddress = _address;
  }
  // set husd swap contract address
  function setHusdSwapAddress(address _address)   external onlyOwner{
      husdSwapAddress = _address;
  }

  //set taker fee feeRate
  function setFeeRate(uint256 index,uint256 stakeAmount,uint256 rate) external onlyOwner{
      // Ensure the fee is less than divisor
    require(rate < FEE_DIVISOR, "INVALID_FEE");
    uint256 len = feeInfo.length;
    require(index <= len, "INVALID_INDEX");
    
    FeeInfo memory _new = FeeInfo({
        stakeAmount : stakeAmount,
        feeRate : rate
    });
    if (len==0||index==len){
  
        feeInfo.push(_new);
    }else{
        feeInfo[index] = _new;
    }
    
    
  }
  //claim token fee
  //if token can not convert to husd.the fee will stay at contract address.and owner can claim them.
  function claimFee(IERC20 token) external onlyOwner{
      uint256 balance = token.balanceOf(address(this));
      if (balance>0){
          token.safeTransfer(msg.sender, balance);
      }
  }
  
  //return address swap fee
  function getFeeRate(address _address) public view returns (uint256){
      require(_address != address(0), "INVALID_ADDRESS");
      uint256 balance = IERC20(stakeTokenAddress).balanceOf(_address);
      //loop the fee rate array
      uint256 lastAmount = 0;
      uint256 feeRate = 0;
      for(uint i = 0; i < feeInfo.length; i++) {
          if (balance>=feeInfo[i].stakeAmount.mul(stakeTokenDecimal)&&(lastAmount==0||feeInfo[i].stakeAmount>lastAmount)){
              feeRate = feeInfo[i].feeRate;
              lastAmount = feeInfo[i].stakeAmount;
          }
      }
      return feeRate;
  }

  /**
   * @notice Authorize a signer
   * @param signer address Wallet of the signer to authorize
   * @dev Emits an Authorize event
   */
  function authorize(address signer) external override {
    authorized[msg.sender] = signer;
    emit Authorize(signer, msg.sender);
  }

  /**
   * @notice Revoke authorization of a signer
   * @dev Emits a Revoke event
   */
  function revoke() external override {
    address tmp = authorized[msg.sender];
    delete authorized[msg.sender];
    emit Revoke(tmp, msg.sender);
  }

  /**
   * @notice Cancel one or more nonces
   * @dev Cancelled nonces are marked as used
   * @dev Emits a Cancel event
   * @dev Out of gas may occur in arrays of length > 400
   * @param nonces uint256[] List of nonces to cancel
   */
  function cancel(uint256[] calldata nonces) external override {
    for (uint256 i = 0; i < nonces.length; i++) {
      uint256 nonce = nonces[i];
      if (_markNonceAsUsed(msg.sender, nonce)) {
        emit Cancel(nonce, msg.sender);
      }
    }
  }

  /**
   * @notice Returns true if the nonce has been used
   * @param signer address Address of the signer
   * @param nonce uint256 Nonce being checked
   */
  function nonceUsed(address signer, uint256 nonce)
    public
    view
    override
    returns (bool)
  {
    uint256 groupKey = nonce / 256;
    uint256 indexInGroup = nonce % 256;
    return (_nonceGroups[signer][groupKey] >> indexInGroup) & 1 == 1;
  }

  /**
   * @notice Returns the current chainId using the chainid opcode
   * @return id uint256 The chain id
   */
  function getChainId() public view returns (uint256 id) {
    // no-inline-assembly
    assembly {
      id := chainid()
    }
  }

  /**
   * @notice Marks a nonce as used for the given signer
   * @param signer address Address of the signer for which to mark the nonce as used
   * @param nonce uint256 Nonce to be marked as used
   * @return bool True if the nonce was not marked as used already
   */
  function _markNonceAsUsed(address signer, uint256 nonce)
    internal
    returns (bool)
  {
    uint256 groupKey = nonce / 256;
    uint256 indexInGroup = nonce % 256;
    uint256 group = _nonceGroups[signer][groupKey];

    // If it is already used, return false
    if ((group >> indexInGroup) & 1 == 1) {
      return false;
    }

    _nonceGroups[signer][groupKey] = group | (uint256(1) << indexInGroup);

    return true;
  }

  /**
   * @notice Hash order parameters
   * @param nonce uint256
   * @param expiry uint256
   * @param makerAddress address
   * @param makerToken address
   * @param makerAmount uint256
   * @param takerToken address
   * @param takerAmount uint256
   * @return bytes32
   */
  function _getOrderHash(
    uint256 nonce,
    uint256 expiry,
    address makerAddress,
    IERC20 makerToken,
    uint256 makerAmount,
    address takerAddress,
    IERC20 takerToken,
    uint256 takerAmount
  ) internal view returns (bytes32) {
    return
      keccak256(
        abi.encode(
          OTC_ORDER_TYPEHASH,
          nonce,
          expiry,
          makerAddress,
          makerToken,
          makerAmount,
          takerAddress,
          takerToken,
          takerAmount
        )
      );
  }

  /**
   * @notice Recover the signatory from a signature
   * @param hash bytes32
   * @param v uint8
   * @param r bytes32
   * @param s bytes32
   */
  function _getSignatory(
    bytes32 hash,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) internal view returns (address) {
    bytes32 digest =
      keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hash));
    address signatory = ecrecover(digest, v, r, s);
    // Ensure the signatory is not null
    require(signatory != address(0), "INVALID_SIG");
    return signatory;
  }
}
