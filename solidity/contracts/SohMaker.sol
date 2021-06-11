// SPDX-License-Identifier: MIT
// P1 - P3: OK
pragma solidity 0.6.12;
import "./libraries/BoringMath.sol";
import "./libraries/BoringERC20.sol";

import "./uniswapv2/interfaces/IUniswapV2ERC20.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ISwapRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

// SohMultiRocket:: Carry Token convert to SOH, may through multiple layers of swap galaxies
// Feed soh to who sojourning in SOH Planet 

// T1 - T4: OK
contract SohMaker is Ownable {
    using BoringMath for uint256;
    using BoringERC20 for IERC20;

    // V1 - V5: OK
    address public immutable bar;

    address private immutable soh;
    // 
    mapping(address => address) internal _factories;
    mapping(address => address[]) internal _routerPaths;

    // E1: OK
    event LogBridgeSet(address indexed token, address indexed bridge);
    // E1: OK
    event LogConvert(address indexed server, address indexed token, uint256 amount, uint256 amountSOH);


    constructor (address _bar, address _soh) public {
       bar = _bar;
       soh = _soh;
    }

    function setRouterAndPath(address _startToken, address _router, address[] calldata paths ) external onlyOwner {
        _factories[_startToken] = _router;
        delete _routerPaths[_startToken];

        safeApprove(_startToken, _router, ~uint256(0));
        _routerPaths[_startToken] = paths;
    }

    function router(address _token) external returns(address) {
        return _factories[_token];
    }

    function pathLength(address _token) external returns(uint256) {
        return _routerPaths[_token].length;
    }

    function path(address _token, uint256 _index) external returns(address) {
        return _routerPaths[_token][_index];
    }

    function convertMultiple(address[] calldata _tokens) external {
        uint256 len = _tokens.length;
        for(uint256 i=0; i < len; i++) {
            convertToken(_tokens[i]);
        }
    }

    function convertToken(address _startToken) public onlyEOA {
        uint256 inputAmount = IERC20(_startToken).balanceOf(address(this));

        emit LogConvert(msg.sender, _startToken, inputAmount, _convert(_startToken));
    }

    function _convert(address _startToken) internal returns (uint256 sohOut) {
        address _router =  _factories[_startToken];

        require(_router != address(0), "SohMaker: no router found");

        address[] memory _pathes =  _routerPaths[_startToken];
        require(_pathes.length > 1, "SohMaker: no paths found");

        uint256 len = _pathes.length;
        
        bool isSOH = (_pathes[len -1] == soh);
        uint256[] memory amounts = ISwapRouter(_router).swapExactTokensForTokens(
            IERC20(_startToken).balanceOf(address(this)),
            0,
            _pathes,
            isSOH ? bar : address(this),
            block.timestamp
        );
        
        if (isSOH) {
            sohOut = amounts[amounts.length - 1];
        }else {
            sohOut = _convert(_pathes[len -1]);
        }
    }

    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    // M1 - M5: OK
    // C1 - C24: OK
    // C6: It's not a fool proof solution, but it prevents flash loans, so here it's ok to use tx.origin
    modifier onlyEOA() {
        // Try to make flash-loan exploit harder to do by only allowing externally owned addresses.
        require(msg.sender == tx.origin, "SushiMaker: must use EOA");
        _;
    }
}
