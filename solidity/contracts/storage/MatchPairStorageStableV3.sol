// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;


import "../interfaces/IStakeGatling.sol";
import "../interfaces/IPriceSafeChecker.sol";
import "../uniswapv2/interfaces/IUniswapV2Pair.sol";

// Storage layer implementation of MatchPairStableV2
contract MatchPairStorageStableV3 {
    
    uint256 public constant PROXY_INDEX = 4;
    IUniswapV2Pair public lpToken;
    IStakeGatling public stakeGatling;
    IPriceSafeChecker public priceChecker;

    address public admin;

    struct UserInfo{
        address user;
        //actual fund point
        uint256 tokenPoint;
    }
    // had profited via impermanence loss
    bool public tokenProfit0;
    bool public tokenProfit1;
    // cover impermanence loss P/L value
    uint256 public tokenPL0;
    uint256 public tokenPL1;
    // retrieve LP priced value via tokenReserve0/totalSupply
    uint256 public tokenReserve0;
    uint256 public tokenReserve1;
    uint256 public totalSupply;

    uint256 public pendingToken0;
    uint256 public pendingToken1;
    uint256 public totalTokenPoint0;
    uint256 public totalTokenPoint1;

    // in UniswapV2.burn() call ,small LP cause Exception('UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED')
    uint256 public sentinelAmount = 500;
    // filter too small asset, saving gas
    uint256 public minMintToken0;
    uint256 public minMintToken1;

    mapping(address => UserInfo) public userInfo0;
    mapping(address => UserInfo) public userInfo1;

    event Stake(bool _index0, address _user, uint256 _amount);
}