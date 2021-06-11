pragma solidity ^0.6.12;

import "../interfaces/IMintRegulator.sol";

contract MintReduceRegulator is IMintRegulator {

    function getScale() external view override returns (uint256 _molecular, uint256 _denominator) {
        return (2000, 16438);
    }
}