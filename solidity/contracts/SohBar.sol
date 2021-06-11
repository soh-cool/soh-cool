// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


// SohBar is the coolest bar in town. You come in with some Soh, and leave with more! The longer you stay, the more Soh you get.
//
// This contract handles swapping to and from xSoh, SohSwap's staking token.
contract SohBar is ERC20("SohBar", "xSoh"), Ownable {
    using SafeMath for uint256;
    IERC20 public soh;

    uint256 public constant REST_GAP = 7 days;
    mapping (address => uint256 ) restTo;
    

    // Define the soh token contract
    constructor(IERC20 _soh) public {
        soh = _soh;
    }

    // Enter the bar. Pay some SOHs. Earn some shares.
    // Locks Soh and mints xSoh

    function enterDelegate(uint256 _amount, address _receiver) external onlyOwner {
        // rest 7 days,when landed from cross chain space
        restTo[_receiver] = block.timestamp + REST_GAP;
        _enter(_amount, _receiver);
        // Lock the Soh in the contract
        soh.transferFrom(msg.sender, address(this), _amount);
    }

    function enter(uint256 _amount) external {
        _enter(_amount, msg.sender);
        // Lock the Soh in the contract
        soh.transferFrom(msg.sender, address(this), _amount);
    }
    function _enter(uint256 _amount, address account) private {
        // Gets the amount of Soh locked in the contract
        uint256 totalSoh = soh.balanceOf(address(this));
        // Gets the amount of xSoh in existence
        uint256 totalShares = totalSupply();
        // If no xSoh exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalSoh == 0) {
            _mint(account, _amount);
        } 
        // Calculate and mint the amount of xSoh the Soh is worth. The ratio will change overtime, as xSoh is burned/minted and Soh deposited + gained from fees / withdrawn.
        else {
            uint256 what = _amount.mul(totalShares).div(totalSoh);
            _mint(account, what);
        }
    }

    // Leave the bar. Claim back your SOHs.
    // Unclocks the staked + gained Soh and burns xSoh
    function leave(uint256 _share) public {
        require(block.timestamp > restTo[msg.sender], "Bar:: Account still in rest state");
        // Gets the amount of xSoh in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of Soh the xSoh is worth
        uint256 what = _share.mul(soh.balanceOf(address(this))).div(totalShares);
        _burn(msg.sender, _share);
        soh.transfer(msg.sender, what);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override virtual {
        require(block.timestamp > restTo[msg.sender], "Bar:: Account still in rest state");
        super._transfer(sender, recipient, amount);
    }
}