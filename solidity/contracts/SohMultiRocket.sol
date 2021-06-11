// SPDX-License-Identifier: MIT
// P1 - P3: OK
pragma solidity 0.6.12;
import "./libraries/BoringMath.sol";
import "./libraries/BoringERC20.sol";

import "./uniswapv2/interfaces/IUniswapV2ERC20.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import "./uniswapv2/interfaces/IUniswapV2Factory.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";

// SohMultiRocket:: Carry Token convert to SOH, may through multiple layers of swap galaxies
// Feed soh to who sojourning in SOH Planet 

// T1 - T4: OK
contract SohMultiRocket is Ownable {
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

    function setFactoryAndPath(address _startToken, address _factory, address[] calldata paths ) external onlyOwner {
        _factories[_startToken] = _factory;
        delete _routerPaths[_startToken];

        _routerPaths[_startToken] = paths;
    }

    function factory(address _token) external returns(address) {
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
        address _factory =  _factories[_startToken];

        require(_factory != address(0), "SohMaker: no factory found");

        address[] memory _pathes =  _routerPaths[_startToken];
        require(_pathes.length > 1, "SohMaker: no paths found");

        uint256 len = _pathes.length;
        for(uint256 i=0; i < len - 1; i++) {
            (address input, address output) = (_pathes[i], _pathes[i + 1]);
            if(output == soh) {
                sohOut = _swap(_factory, input, output, IERC20(input).balanceOf(address(this)), bar);
            } else {
                _swap(_factory, input, output, IERC20(input).balanceOf(address(this)), address(this));
            }
        }

        address endToken = _pathes[len -1];
        if (endToken != soh) {
           sohOut = _convert(endToken);
        }
    }

    function _swap(address _factory, address fromToken, address toToken, uint256 amountIn, address to) internal returns (uint256 amountOut) {
        IUniswapV2Factory factory = IUniswapV2Factory(_factory);
        // Checks
        // X1 - X5: OK
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(fromToken, toToken));
        require(address(pair) != address(0), "SushiMaker: Cannot convert");

        // Interactions
        // X1 - X5: OK
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        uint256 amountInWithFee = amountIn.mul(997);
        if (fromToken == pair.token0()) {
            amountOut = amountIn.mul(997).mul(reserve1) / reserve0.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(0, amountOut, to, new bytes(0));
            // TODO: Add maximum slippage?
        } else {
            amountOut = amountIn.mul(997).mul(reserve0) / reserve1.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(amountOut, 0, to, new bytes(0));
            // TODO: Add maximum slippage?
        }
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
