
pragma solidity ^0.8.0;

import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IOtcV2.sol";

/**
 * @title OtcV2: Simple otc swap v2.support partial transaction

 * @notice https://www.depth.fi/
 */
contract DepthOtcV2 is IOtcV2, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    struct FeeInfo{
        uint256 stakeAmount;
        uint256 feeRate;
    }
    struct MakerOrderInfo{
        uint256 nonce;
        uint256 expiry;
        address makerAddress;
        address makerToken;
        uint256 makerAmount;
        address wantAddress;
        address wantToken;
        uint256 wantAmount;
        bool canSplit;
        uint256 takerAmount;
        uint8 v;
        bytes32 r;
        bytes32 s;

    }
    bool public isPaused;
    FeeInfo[] public feeInfo;


    bytes32 public constant DOMAIN_TYPEHASH =keccak256(
      abi.encodePacked(
        "EIP712Domain(",
        "string name,",
        "string version,",
        "uint256 chainId,",
        "address verifyingContract",
        ")"
      )
    );

    bytes32 public constant OTC_ORDER_TYPEHASH =keccak256(
      abi.encodePacked(
        "OtcOrder(",
        "uint256 nonce,",
        "uint256 expiry,",
        "address makerAddress,",
        "address makerToken,",
        "uint256 makerAmount,",
        "address wantAddress,",
        "address wantToken,",
        "uint256 wantAmount,",
        "bool canSplit"
        ")"
      )
    );

    bytes32 public constant DOMAIN_NAME = keccak256("DepthOtcV2");
    bytes32 public constant DOMAIN_VERSION = keccak256("3");
    uint256 public immutable DOMAIN_CHAIN_ID;
    bytes32 public immutable DOMAIN_SEPARATOR;

    uint256 public constant FEE_DIVISOR = 100000;
    uint256 public makerReturnFeeRate = 0;

    address public husd =0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047;
    address public usdt =0xa71EdC38d189767582C38A3145b5873052c3e47a;
    address public wht = 0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F;
 // mapping(byte32=>)
    mapping(address => mapping(uint256 => uint256)) internal _nonceGroups;

    address public storageContractAddress;
    address public husdSwapAddress =0x85D1c15d5D6fa92a584243Da16c16F60e564B9F2;//neet to convert taker token to husd
    address public daoAddress = 0xfbaC8c66D9B7461EEfa7d8601568887c7b6f96AD;
    address public xdepAddress = 0xDeEfD50FE964Cd03694EF7AbFB4147Cb1dd41c9B;
    mapping (address=>bool) blackTokens;//if in black tokens.can not trade
    mapping (address=>mapping(uint256=>uint256)) public userOrderTraded;
    constructor(address _storageContractAddress) public {

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

        storageContractAddress= _storageContractAddress;
    }



    function swap(MakerOrderInfo memory order) public {
        require(isPaused==false, "contract is paused");
        require(DOMAIN_CHAIN_ID == getChainId(), "CHAIN_ID_CHANGED");
        require(!blackTokens[address(order.makerToken)]&&!blackTokens[address(order.wantToken)],"black token address!");
        // Ensure the expiry is not passed
        require(order.expiry > block.timestamp, "EXPIRY_PASSED");
    //if takerAddress is not zero.check the taker address
        if (order.wantAddress!=address(0)) {
            require(msg.sender == order.wantAddress, "invalid taker address");
        }
        require(order.takerAmount>0,"invalid taker amount");
        bytes32 hashed = _getOrderHash(
            order.nonce,
            order.expiry,
            order.makerAddress,
            order.makerToken,
            order.makerAmount,
            order.wantAddress,
            order.wantToken,
            order.wantAmount,
            order.canSplit
        );

        // Recover the signatory from the hash and signature
        address signatory = _getSignatory(hashed, order.v, order.r, order.s);

        // Ensure the nonce is not yet used and if not mark it used
        require(nonceUsed(signatory, order.nonce)==false, "NONCE_ALREADY_USED");

        // Ensure the signatory is authorized by the signer wallet

        require(order.makerAddress == signatory, "UNAUTHORIZED");

        uint256 _tradedAmount = userOrderTraded[order.makerAddress][order.nonce];
        if (!order.canSplit){
            require(order.wantAmount==order.takerAmount,"this order can not be split");
        }else{
            //compare total trade amount with taker amount

            require(order.wantAmount>=_tradedAmount.add(order.takerAmount),"exceed order amount!");
        }
        userOrderTraded[order.makerAddress][order.nonce] = _tradedAmount.add(order.takerAmount);
        if (order.wantAmount==userOrderTraded[order.makerAddress][order.nonce]){
            require(_markNonceAsUsed(signatory, order.nonce), "NONCE_ALREADY_USED");
            delete userOrderTraded[order.makerAddress][order.nonce];
        }
        // Transfer token from taker to maker
        IERC20(order.wantToken).safeTransferFrom(msg.sender, order.makerAddress, order.takerAmount);
        //calculate how many maker amount transfer
        uint256 tradeMakerAmount = order.makerAmount.mul(order.takerAmount).div(order.wantAmount);
        //transfer token from maker to contract.
        IERC20(order.makerToken).safeTransferFrom(order.makerAddress,address(this), tradeMakerAmount);
        uint256 _feeAmount=_dealFee(order.makerAddress,order.makerToken,tradeMakerAmount);


        // Emit a Swap event
        emit Swap(
            order.nonce,
            block.timestamp,
            order.makerAddress,
            order.makerToken,
            order.makerAmount,
            msg.sender,
            order.wantToken,
            order.takerAmount,
            _feeAmount
        );
    }


  //deal fee and return taker amount fee
  function _dealFee(address makerAddress,address makerToken,uint256 makerAmount) internal returns(uint256){
       //cal taker fee rate
    uint256 _feeRate =getFeeRate(msg.sender);
    uint256 _feeAmount = _feeRate.mul(makerAmount).div(FEE_DIVISOR);
    uint256 _makerReturnFee = makerReturnFeeRate.mul(makerAmount).div(FEE_DIVISOR);
    require(_feeAmount>=_makerReturnFee,"maker return fee over fee amount");


    // Transfer left token from contract to taker
    IERC20(makerToken).safeTransfer(msg.sender, makerAmount.sub(_feeAmount));
    //transfer _makerReturnFee to maker
    if (_makerReturnFee>0){
        IERC20(makerToken).safeTransfer(makerAddress, _makerReturnFee);
        _feeAmount = _feeAmount.sub(_makerReturnFee);
    }
    //cal husd fee
    uint256 husdFee = 0;
    uint256 husdAmount = 0;
    //if fee token is husd
    if (makerToken==husd){
        husdFee = _feeAmount;
    }else{
        //husd balance before swap
        if (_feeAmount>0){
            uint256 _beforeBalance = IERC20(husd).balanceOf(address(this));

            IERC20(makerToken).safeApprove(husdSwapAddress,_feeAmount);
            try IHusdSwap(husdSwapAddress).swapTokensToHusd(makerToken,_feeAmount){}catch{}

            //husd fee = current husd balance - before
            husdFee = IERC20(husd).balanceOf(address(this)).sub(_beforeBalance);
        }
    }
    //call storage contract to save data and send husd fee to dao
    if (husdFee>0){
        husdAmount = husdFee.mul(FEE_DIVISOR).div(_feeRate.sub(_makerReturnFee));
        //save trade info to storage contract
        IStorage(storageContractAddress).saveTradeInfo(husdAmount,husdFee);
        IERC20(husd).approve(daoAddress,husdFee);
        //call dao address donate husd
        IDao(daoAddress).donateHUSD(husdFee);
    }
    return _feeAmount;

  }


// set contract paused or not
  function setPaused(bool b)   external onlyOwner{
      isPaused = b ;
  }

    // set maker return fee
    function setMakerReturnFeeRate(uint256 _feeRate)   external onlyOwner{
        makerReturnFeeRate = _feeRate ;
    }

  // set stake token address
  function setXdepAddress(address _address)   external onlyOwner{
      xdepAddress = _address;
  }

  // set storage contract address
  function setStorageContractAddress(address _address)   external onlyOwner{
      storageContractAddress = _address;
  }

  // set husd swap contract address
  function setHusdSwapAddress(address _address)   external onlyOwner{
      husdSwapAddress = _address;
  }
  // set dao contract address
  function setDaoAddress(address _address)   external onlyOwner{
      daoAddress = _address;
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
      uint256 balance = IERC20(xdepAddress).balanceOf(_address);
      //loop the fee rate array
      uint256 lastAmount = 0;
      uint256 feeRate = 0;
      uint256 stakeTokenDecimal = ERC20(xdepAddress).decimals();
      for(uint i = 0; i < feeInfo.length; i++) {
          if (balance>=feeInfo[i].stakeAmount.mul(stakeTokenDecimal)&&(lastAmount==0||feeInfo[i].stakeAmount>lastAmount)){
              feeRate = feeInfo[i].feeRate;
              lastAmount = feeInfo[i].stakeAmount;
          }
      }
      return feeRate;
  }

  /**
   * @notice Cancel one or more nonces
   * @dev Cancelled nonces are marked as used
   * @dev Emits a Cancel event
   * @dev Out of gas may occur in arrays of length > 400
   * @param nonces uint256[] List of nonces to cancel
   */
  function cancel(uint256[] calldata nonces) external {
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
   * @param wantToken address
   * @param wantAmount uint256
   * @return bytes32
   */
  function _getOrderHash(
    uint256 nonce,
    uint256 expiry,
    address makerAddress,
    address makerToken,
    uint256 makerAmount,
    address wantAddress,
    address wantToken,
    uint256 wantAmount,
    bool canSplit
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
          wantAddress,
          wantToken,
          wantAmount,
          canSplit
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

  function addBlackToken(address _address) external onlyOwner {
    blackTokens[_address] = true;
  }

  function removeBlackToken(address _address) external onlyOwner {
    if (blackTokens[_address] ){
        delete blackTokens[_address];
    }
  }


    //claim exchange token like mdx to contract address.then can use claimFee to withdraw tokens to owner.
    function claimExchangeMiningToken(address _address) external{
        ISwapMining(_address).takerWithdraw();

    }

}
