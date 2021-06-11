// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";

//common configuration
contract SohConfig is Ownable {

    uint256 public constant VERSION = 1;

    address public sohMaker;
    // 1000-based
    uint256 public gatlingFeeRate;

    function setSohMaker(address _sohMaker) external onlyOwner {
        sohMaker = _sohMaker;
    }

    function setGatlingFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate < 1000, "SohConfig: Fee rate out of range");
        gatlingFeeRate = _feeRate;
    }
}
