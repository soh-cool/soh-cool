// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../uniswapv2/interfaces/IUniswapV2Pair.sol";
import '../uniswapv2/libraries/UniswapV2Library.sol';
import '../uniswapv2/libraries/TransferHelper.sol';

import "../utils/MasterCaller.sol";
import "../interfaces/IStakeGatling.sol";
import "../interfaces/IMatchPair.sol";
import "../interfaces/IPriceSafeChecker.sol";
import "../storage/MatchPairStorageStableV3.sol";


// Logic layer implementation of MatchPairStableDelegateV3
// Diff with MatchPairDelegateV2.sol
// 1. add `_rebasePoolCalc()`, called before `stake(...)` & `untakeToken(...)`, calculate and record P/L amount of the whole pool ,compare with pre point
// 2. add `_rebasePoolExec()`, Swap profit assets for loss assets to reduce impermanence losses 
// 3. userPoint minted base on NO-IL amount in `stake(...)`
contract MatchPairStableDelegateV3 is MatchPairStorageStableV3, IMatchPair, Ownable, MasterCaller{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    constructor(address _lpAddress) public {
        lpToken = IUniswapV2Pair(_lpAddress);
    }
    function setStakeGatling(address _gatlinAddress) public onlyOwner() {
        stakeGatling = IStakeGatling(_gatlinAddress);
    }

    /**
     * @notice Just logic layer
     */
    function stake(uint256 _index, address _user,uint256 _amount) public  override {
        _checkPrice();
        // 1. updateLpAmount
        _updateLpProfit();
        _rebasePoolCalc();
        //
        uint256 totalAmount = totalTokenAmount(_index);
        uint256 totalPoint = _index == 0 ? totalTokenPoint0 : totalTokenPoint1;

        uint256 userPoint;
        {
            if(totalPoint == 0 || totalAmount == 0) {
                userPoint = _amount;
            }else {
                userPoint = _amount.mul(totalPoint).div(totalAmount);
            }
        }
        _addTotalPoint(_index, _user, userPoint);
        _addPendingAmount(_index, _amount);
        updatePool();
    }

    function _addTotalPoint(uint256 _index, address _user, uint256 _amount) private {
        UserInfo storage userInfo = _index == 0? userInfo0[_user] : userInfo1[_user];
        userInfo.tokenPoint = userInfo.tokenPoint.add(_amount);
        if(_index == 0) {
            totalTokenPoint0 = totalTokenPoint0.add(_amount);
        }else {
            totalTokenPoint1 = totalTokenPoint1.add(_amount);
        }
    }

    function rebasePoolExec() public  {
        _rebasePoolCalc();
        _rebasePoolExec();
    }
    function _rebasePoolExec() private {


        if (tokenProfit0 && tokenProfit1) {

            //both profit reset, happy :)
        } else if (tokenProfit0) {  //token0 profit, token1 loss

            uint256 sellAmount;

            uint256 pendingToken = pendingToken0;
            if(pendingToken < tokenPL0) {
                (uint reserve0, uint reserve1,) = lpToken.getReserves();
                //burnLp for winAmount then sell
                uint256 burnLp = tokenPL0.sub(pendingToken).mul(lpToken.totalSupply()).div(reserve0);

                (uint256 tokenCurrent, uint256 tokenPaired) = _burnLp(0, burnLp);

                sellAmount = tokenCurrent.add(pendingToken);
                pendingToken0 = pendingToken + tokenCurrent;
                pendingToken1 += tokenPaired;
            } else {
                sellAmount = tokenPL0;
            }
            uint256 amountOut = _execSwap(0, sellAmount);

            pendingToken0 = pendingToken0.sub(sellAmount);
            pendingToken1 = pendingToken1.add(amountOut);

        } else if (tokenProfit1) {
            
            uint256 sellAmount;

            uint256 pendingToken = pendingToken1;
            if(pendingToken < tokenPL1) {
                (uint reserve0, uint reserve1,) = lpToken.getReserves();
                //burnLp for winAmount then sell
                uint256 burnLp = tokenPL1.sub(pendingToken).mul(lpToken.totalSupply()).div(reserve1);

                (uint256 tokenCurrent, uint256 tokenPaired) = _burnLp(1, burnLp);

                sellAmount = tokenCurrent.add(pendingToken);
                pendingToken1 = pendingToken + tokenCurrent;
                pendingToken0 += tokenPaired;
            } else {
                sellAmount = tokenPL1;
            }
            uint256 amountOut = _execSwap(1, sellAmount);
            pendingToken1 = pendingToken1.sub(sellAmount);
            pendingToken0 = pendingToken0.add(amountOut);

        } else { // Unexpected, need attention

        }
        // reset
        if (tokenProfit0 != tokenProfit1) {
            tokenPL0 = 0;
            tokenPL1 = 0;
        }
        updateLpPrice();
    }

    function _rebasePoolCalc() internal {
        uint256 totalLp = stakeGatling.totalLPAmount();

        if(totalLp > sentinelAmount) {

            uint256 _expectAmount0 = totalLp.mul(tokenReserve0).div(totalSupply);
            uint256 _expectAmount1 = totalLp.mul(tokenReserve1).div(totalSupply);
            (uint256 _amount0, uint256 _amount1) = lp2TokenAmountActual(totalLp);
            bool win0 = _amount0 >= _expectAmount0;
            bool win1 = _amount1 >= _expectAmount1;

            uint256 plAmount0 = win0? _amount0 - _expectAmount0 : _expectAmount0 - _amount0 ;
            if(win0 == tokenProfit0) { // same P/L
                tokenPL0 = tokenPL0.add(plAmount0);
            } else {
                if (tokenPL0 >= plAmount0) {
                    tokenPL0 = tokenPL0 - plAmount0;
                } else {
                    tokenPL0 = plAmount0 - tokenPL0;
                    tokenProfit0 = win0;
                }
            }

            // Token1 calculate
            uint256 plAmount1 = win1? _amount1 - _expectAmount1 : _expectAmount1 - _amount1 ;

            if(win1 == tokenProfit1) {
                tokenPL1 = tokenPL1.add(plAmount1);
            } else {
                if (tokenPL1 >= plAmount1) {
                    tokenPL1 = tokenPL1 - plAmount1;
                } else {
                    tokenPL1 = plAmount1 - tokenPL1;
                    tokenProfit1 = win1;
                }
            }
        }
                updateLpPrice();
    }

    function updateLpPrice() private {

        (tokenReserve0, tokenReserve1, ) = lpToken.getReserves();

        totalSupply = lpToken.totalSupply();
    }

    function _getPendingAndPoint(uint256 _index) private returns (uint256 pendingAmount,uint256 totalPoint) {
        if(_index == 0) {
            return (pendingToken0, totalTokenPoint0);
        }else {
            return (pendingToken1, totalTokenPoint1);
        }
    }
    
    function updatePool() private {

        if( pendingToken0 > minMintToken0 && pendingToken1 > minMintToken1 ) {

            (uint amountA, uint amountB) = getPairAmount( pendingToken0, pendingToken1 ); 
            if( amountA > minMintToken0 && amountB > minMintToken1 ) {
                
                TransferHelper.safeTransfer(lpToken.token0(), address(lpToken), amountA);
                TransferHelper.safeTransfer(lpToken.token1(), address(lpToken), amountB);
                pendingToken0 = pendingToken0.sub(amountA);
                pendingToken1 = pendingToken1.sub(amountB);
                //mint LP
                uint liquidity = lpToken.mint(stakeGatling.lpStakeDst());
                //stake Token to Gatling
                stakeGatling.stake(liquidity);
            }
        }
    }

 
    function getPairAmount(
        uint amountADesired,
        uint amountBDesired  ) private returns ( uint amountA, uint amountB) {

        (uint reserveA, uint reserveB,) = lpToken.getReserves();

        uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
        if (amountBOptimal <= amountBDesired) {
            (amountA, amountB) = (amountADesired, amountBOptimal);
        } else {
            uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
            assert(amountAOptimal <= amountADesired);
            (amountA, amountB) = (amountAOptimal, amountBDesired);
        }
    }
    function untakeToken(uint256 _index, address _user, uint256 _amount) 
        public
        override
        returns (uint256 _withdrawAmount, uint256 _leftAmount) 
    {
        _checkPrice();
        _updateLpProfit();
        _rebasePoolCalc();

        address tokenCurrent = _index == 0 ? lpToken.token0() : lpToken.token1();

        (uint256 totalAmount, uint256 actualAmount ) = safeTotalTokenAmount(_index, _amount);
        
        (uint256 pendingAmount, uint256 totalPoint) = _getPendingAndPoint(_index);

        uint256 userAmount =  _userAmountByPoint( userPoint(_index, _user) , totalPoint, totalAmount);

        if(min(userAmount, _amount)  > actualAmount) {
            _rebasePoolExec();
            userAmount =  _userAmountByPoint( userPoint(_index, _user) , totalPoint, totalTokenAmount(_index));
        }

        if(_amount > userAmount) {
            _amount = userAmount;
        }

        {
            if(_amount <=  pendingAmount) {
                _withdrawAmount = _amount;
                _subPendingAmount(_index, _withdrawAmount);
            }else  {
                uint256 amountRequireViaLp =  _amount.sub(pendingAmount);

                if(_index == 0){
                    pendingToken0 = 0;
                }else {
                    pendingToken1 = 0;
                }

                uint256 amountBurned = burnFromLp(_index, amountRequireViaLp, tokenCurrent);
                _withdrawAmount = pendingAmount.add(amountBurned);
            }
        }

        uint256 pointAmount = _withdrawAmount.mul(totalPoint).div(totalAmount);
        _subUserPoint(_index, _user, pointAmount);

        _leftAmount = userAmount.sub(_withdrawAmount);

        // transfer to Master
        TransferHelper.safeTransfer(tokenCurrent, masterCaller(), _withdrawAmount);
    }

      /**
     * @notice Desire Token via burn LP
     */
    function burnFromLp(uint256 _index, uint256 amountRequireViaLp, address tokenCurrent) private returns(uint256) {

        uint256 requirLp = amountRequireViaLp.mul(lpToken.totalSupply()).div(IERC20(tokenCurrent).balanceOf(address(lpToken)));
        if(requirLp >  sentinelAmount) { // small amount lp cause Exception in UniswapV2.burn();

            (uint256 amountC, uint256 amountOther) = untakeLP(_index, requirLp);

            _addPendingAmount( (_index +1)%2 ,  amountOther);
            return amountC;
        }
    }

    function _execSwap(uint256 indexIn, uint256 amountIn ) private returns(uint256 amountOunt) {

        if(amountIn > 0) {
            amountOunt = _getAmountVoutIndexed( indexIn,  amountIn);


            address sellToken = indexIn == 0? lpToken.token0() : lpToken.token1();
            TransferHelper.safeTransfer(sellToken, address(lpToken), amountIn);
            uint256 zero;
            (uint256 amount0Out, uint256 amount1Out ) = indexIn == 0 ? ( zero , amountOunt ) : (amountOunt, zero);
            lpToken.swap(amount0Out, amount1Out, address(this), new bytes(0));
        }
    }

     function _getAmountVoutIndexed(uint256 _inIndex, uint256 _amountIn ) private returns(uint256 amountOut) {
        (uint256 _reserveIn, uint256 _reserveOut, ) = lpToken.getReserves();
        if(_inIndex == 1) {
            (_reserveIn, _reserveOut) = (_reserveOut, _reserveIn);
        }
        amountOut = _getAmountOut(_amountIn, _reserveIn, _reserveOut);
    }


    function _getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {

        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    function _burnLp(uint256 _index, uint256 _lpAmount) private returns (uint256 tokenCurrent, uint256 tokenPaired) {
        //no precheck before call this function
        if(_lpAmount > sentinelAmount) {
            (tokenCurrent, tokenPaired) = stakeGatling.burn(address(this), _lpAmount);
            if(_index == 1) {
                (tokenCurrent, tokenPaired) = (tokenPaired, tokenCurrent );
            }
        }
    }

    /**
     * @notice price feeded by  Oracle
     */
    function _checkPrice() private {
        if(address(priceChecker) != address(0) ) {
            (uint reserve0, uint reserve1,) = lpToken.getReserves();
            priceChecker.checkPrice(reserve0, reserve1);
        }
    }
    /**
     * @notice Compound interest calculation in Gatling layer
     */
    function _updateLpProfit() private {
        stakeGatling.withdraw(0);
    }

    function _subPendingAmount(uint256 _index, uint256 _amount) private {
        if(_index == 0) {
            pendingToken0 = pendingToken0.sub(_amount);
        }else {
            pendingToken1 = pendingToken1.sub(_amount);
        }
    }

    function _addPendingAmount(uint256 _index, uint256 _amount) private {
        if(_index == 0) {
            pendingToken0 = pendingToken0.add(_amount);
        }else {
            pendingToken1 = pendingToken1.add(_amount);
        }
    }

    function _subUserPoint(uint256 _index, address _user, uint256 _amount) private {
        UserInfo storage userInfo = _index == 0? userInfo0[_user] : userInfo1[_user];
        userInfo.tokenPoint = userInfo.tokenPoint.sub(_amount);

        if(_index == 0) {
            totalTokenPoint0 = totalTokenPoint0.sub(_amount);
        }else {
            totalTokenPoint1 = totalTokenPoint1.sub(_amount);
        }
    }

    function untakeLP(uint256 _index,uint256 _untakeLP) private returns (uint256 amountC, uint256 amountPaired) {
        
        (amountC, amountPaired) = stakeGatling.burn(address(this), _untakeLP);
        if(_index == 1) {
             (amountC , amountPaired) = (amountPaired, amountC);
        }
    }
    
    function token(uint256 _index) public view override returns (address) {
        return _index == 0 ? lpToken.token0() : lpToken.token1();
    }

    function lPAmount(uint256 _index, address _user) public view returns (uint256) {
        uint256 totalPoint = _index == 0? totalTokenPoint0 : totalTokenPoint1;
        return stakeGatling.totalLPAmount().mul(userPoint(_index, _user)).div(totalPoint);
    }

    function tokenAmount(uint256 _index, address _user) public view returns (uint256) {
        uint256 totalPoint = _index == 0? totalTokenPoint0 : totalTokenPoint1;
        // uint256 pendingAmount = _index == 0? pendingToken0 : pendingToken1;
        // todo mock:: both amount show via method.tokenAmount()
        uint256 pendingAmount = totalTokenAmount(_index);

        uint256 userPoint = userPoint(_index, _user);
        return _userAmountByPoint(userPoint, totalPoint, pendingAmount);
    }

    function userPoint(uint256 _index, address _user) public view returns (uint256) {
        UserInfo storage user = _index == 0? userInfo0[_user] : userInfo1[_user];
        return user.tokenPoint;
    }

    function _userAmountByPoint(uint256 _point, uint256 _totalPoint, uint256 _totalAmount ) 
        private pure returns (uint256) {
        if(_totalPoint == 0) {
            return 0;
        }
        return _point.mul(_totalAmount).div(_totalPoint);
    }

    function queueTokenAmount(uint256 _index) public view override  returns (uint256) {
        return _index == 0 ? pendingToken0: pendingToken1;
    }

    function safeTotalTokenAmount(uint256 _index, uint256 _withdrawAmount) private view returns (uint256 expectTotalAmount, uint256 actualTotalAmount ) {
        (uint256 amount0, uint256 amount1) = stakeGatling.totalToken();
        if(_index == 0) {
            actualTotalAmount = amount0.add(pendingToken0);
            expectTotalAmount = tokenProfit0 ? actualTotalAmount.sub(tokenPL0) : actualTotalAmount.add(tokenPL0);
        }else {
            actualTotalAmount = amount1.add(pendingToken1);
            expectTotalAmount = tokenProfit1 ? actualTotalAmount.sub(tokenPL1) : actualTotalAmount.add(tokenPL1);
        }
    }

    function totalTokenAmount(uint256 _index) private view  returns (uint256) {
        uint256 totalLp = stakeGatling.totalLPAmount();
        if(_index == 0) {
            uint256 _expectAmount0 = totalLp.mul(tokenReserve0).div(totalSupply);
            uint256 nativeAmount = _expectAmount0.add(pendingToken0);
            uint256 result = tokenProfit0 ? nativeAmount.sub(tokenPL0) : nativeAmount.add(tokenPL0);
            return result;
        
        }else {
            uint256 _expectAmount1 = totalLp.mul(tokenReserve1).div(totalSupply);
            uint256 nativeAmount = _expectAmount1.add(pendingToken1);
            uint256 result = tokenProfit1 ? nativeAmount.sub(tokenPL1) : nativeAmount.add(tokenPL1);
            return result;  
        }
    }

    /**
     *
     */
    function lp2TokenAmountActual(uint256 _liquidity) public view  returns (uint256 amount0, uint256 amount1) {
        uint256 _totalSupply = lpToken.totalSupply();
        (address _token0, address _token1) = (lpToken.token0(), lpToken.token1());

        uint balance0 = IERC20(_token0).balanceOf(address(lpToken));
        uint balance1 = IERC20(_token1).balanceOf(address(lpToken));
        amount0 = _liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = _liquidity.mul(balance1) / _totalSupply;
    }
    function lp2TokenAmount(uint256 _liquidity) public view  returns (uint256 amount0, uint256 amount1) {

        amount0 = _liquidity.mul(tokenReserve0) / totalSupply; // using balances ensures pro-rata distribution
        amount1 = _liquidity.mul(tokenReserve1) / totalSupply;
    }

    function maxAcceptAmount(uint256 _index, uint256 _molecular, uint256 _denominator, uint256 _inputAmount) public view override returns (uint256) {
        
        (uint256 amount0, uint256 amount1) = stakeGatling.totalToken();

        uint256 pendingTokenAmount = _index == 0 ? pendingToken0 : pendingToken1;
        uint256 lpTokenAmount =  _index == 0 ? amount0 : amount1;

        require(lpTokenAmount.mul(_molecular).div(_denominator) > pendingTokenAmount, "Amount in pool less than PendingAmount");
        uint256 maxAmount = lpTokenAmount.mul(_molecular).div(_denominator).sub(pendingTokenAmount);
        
        return _inputAmount > maxAmount ? maxAmount : _inputAmount ; 
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? b :a;
    }
}
