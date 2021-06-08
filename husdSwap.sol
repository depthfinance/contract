pragma solidity ^0.8.0;

import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
interface depthRouter {
    function exchange_underlying(int128, int128, uint256, uint256) external;
    function get_dy_underlying( int128, int128,  uint256) external view returns(uint256);
}
interface uniRouter {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory);
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}
/**depth.fi vault***/
contract husdSwap is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public husd =0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047;
    address public usdt =0xa71EdC38d189767582C38A3145b5873052c3e47a;
    address public wht = 0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F;
    address public depth=0x1D1cF3b43bC54B7D8e0F763B6b8957F480367834;//depth swap address .convert usdt to husd
    address public mdex=0xED7d5F38C79115ca12fe6C0041abb22F0A06C300;//other token swap.default is mdex swap
    mapping(string=>address) public dexs;
    uint256 public dexLength;
    mapping(uint256=>string) public dexIndex;
    mapping(string=>mapping(address=>address[][])) public paths;

    constructor () public {

    }
    function addPaths(string memory _dex,address _token,address[][] memory _paths) external onlyOwner{
        paths[_dex][_token]=_paths;
    }
    function deletePaths(string memory _dex,address _token) external onlyOwner{
        delete paths[_dex][_token];
    }
    function getPaths(string memory _dex,address _token) public view returns(address[][] memory){

        return paths[_dex][_token];
    }
    function getUniAmountOut(string memory _dex,uint _amountIn, address[] memory _path) public view returns(uint256){
        try uniRouter(dexs[_dex]).getAmountsOut(_amountIn, _path) returns(uint256[] memory _amount){
            return _amount[_path.length-1];
        }catch{
            return 0;
        }
    }
    function setUniSwapAddress(string memory _dexName,address _address)   external onlyOwner{
        if (dexs[_dexName]==address(0)){
            dexIndex[dexLength] = _dexName;
            dexLength+=1;
        }
        dexs[_dexName] = _address;

    }
    function getDefaultPaths(address _token) public view returns(address[][] memory){
        address[][] memory _paths = new address[][](4);
        _paths[0] = new address[](2);
        _paths[0][0] = _token;
        _paths[0][1] = husd;
        _paths[1] = new address[](2);
        _paths[1][0] = _token;
        _paths[1][1] = usdt;
        _paths[2] = new address[](3);
        _paths[2][0] = _token;
        _paths[2][1] = wht;
        _paths[2][2] = husd;
        _paths[3] = new address[](3);
        _paths[3][0] = _token;
        _paths[3][1] = wht;
        _paths[3][2] = usdt;
        return _paths;
    }
    function getBestSellPath(address _token,uint256 _amount) public view returns(address dex,uint256 bestAmount,address[] memory sellPath){
        bestAmount = 0;
        for(uint256 i=0;i<dexLength;i++){
            string memory _dexName = dexIndex[i];
            address _uniAddress = dexs[_dexName];
            address[][] memory _paths = getPaths(_dexName,_token);
            if (_paths.length==0&&_uniAddress==mdex){
                //create default paths. token->husd token->usdt token->wht->husd token->wht->usdt
                _paths = getDefaultPaths(_token);
            }
            if (_paths.length==0){
                continue;
            }
            for(uint256 j=0;j<_paths.length;j++){
                //only support sell to usdt or husd
                address sellToToken = _paths[j][_paths[j].length-1];
                if (sellToToken!=usdt&&sellToToken!=husd){
                    continue;
                }
                (uint256 outAmount)=getUniAmountOut(_dexName,_amount,_paths[j]);
                if (sellToToken==usdt){
                    outAmount =outAmount.div(10**10);
                }
                if (outAmount>bestAmount){
                    dex = _uniAddress;
                    bestAmount = outAmount;
                    sellPath = _paths[j];
                }
            }
        }
    }
    // set husd swap contract address
    function setDepthSwapAddress(address _address)   external onlyOwner{
        depth = _address;
    }


    function swapTokensToHusd(address _token,uint256 _amount) external{
        if (_amount==0){
            return;
        }
        uint256 _beforeHusdBalance = IERC20(husd).balanceOf(address(this));
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        if (_token==usdt){
            IERC20(usdt).safeApprove(depth,_amount);
            depthRouter(depth).exchange_underlying(1,0,_amount,0);
        }else if(_token!=husd){
            (address dex,uint256 bestAmount,address[] memory sellPath)=getBestSellPath(_token,_amount);
            if (bestAmount ==0||sellPath.length==0){
                return;
            }

            IERC20(_token).safeApprove(dex, _amount);
            uniRouter(dex).swapExactTokensForTokens(_amount, 0, sellPath, address(this), block.timestamp.add(1800));
            //if last sellPath is usdt.convert it to husd;
            if (sellPath[sellPath.length-1]==usdt){
                uint256 usdBalance = IERC20(usdt).balanceOf(address(this));
                IERC20(usdt).safeApprove(depth,usdBalance);
                depthRouter(depth).exchange_underlying(1,0,usdBalance,0);
            }
        }
        uint256 _afterHusdBalance = IERC20(husd).balanceOf(address(this)).sub(_beforeHusdBalance);
        if(_afterHusdBalance>0){
            IERC20(husd).safeTransfer(msg.sender, _afterHusdBalance);
        }
    }

    function claimToken(IERC20 token) external onlyOwner{
        uint256 balance = token.balanceOf(address(this));
        if (balance>0){
            token.safeTransfer(msg.sender, balance);
        }
    }
}
