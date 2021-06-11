// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;


import "./storage/MatchPairStorageStableV3.sol";
import "./MatchPairDelegator.sol";

contract MatchPairStableV3 is MatchPairStorageStableV3, MatchPairDelegator {

    modifier onlyAdmin() {
        require(admin == msg.sender, "Admin: caller is not the admin");
        _;
    }

    constructor(address _lpToken) public {
        lpToken =  IUniswapV2Pair(_lpToken);
        admin = msg.sender;
    }

     /**  From Library  */
    function token(uint256 _index) public view override returns (address) {
        return _index == 0 ? lpToken.token0() : lpToken.token1();
    }

    function setPriceSafeChecker(address _priceChecker) public onlyOwner() {
        priceChecker = IPriceSafeChecker(_priceChecker);
    }
    
    function setStakeGatling(address _gatlinAddress) public onlyOwner() {
        stakeGatling = IStakeGatling(_gatlinAddress);
    }

    function setMintLimit(uint256 _minMintToken0, uint256 _minMintToken1) public onlyAdmin() {
        minMintToken0 = _minMintToken0;
        minMintToken1 = _minMintToken1;
    }

    /**
     * Actively call by admin
     */
    function rebasePoolExec() external onlyAdmin() {
        delegateToImplementation(
            abi.encodeWithSignature("rebasePoolExec()",
              ''
             ));
    }

    function setAdmin(address _owner) external onlyAdmin() {
        require(_owner != address(0), "New admin empty!");
        admin = _owner;
    }

    function implementation() public view override returns (address) {
        return IProxyRegistry(masterCaller()).getProxy(PROXY_INDEX);
    }
}
