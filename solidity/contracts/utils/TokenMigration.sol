// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";



contract TokenMigration is Ownable {

    address public immutable inToken;
    address public immutable outToken;
    uint256 public immutable createAt;

    event Convert(address indexed _user, uint256 _data);
    event Exit(address indexed _to, uint256 _data);
    constructor(address _inToken, address _outToken ) public  {
        inToken  = _inToken;
        outToken = _outToken;
        createAt = block.timestamp;
    }

    function convertAll() public {
        convert(IERC20(inToken).balanceOf(msg.sender));
    }

    /**
     * convert All inToken to outToken
     */
    function convert(uint256 _amount) public {
        require(IERC20(inToken).allowance(msg.sender, address(this)) >= _amount, "Approve required");

        safeTransferFrom(inToken, msg.sender, 0x0000000000000000000000000000000000000001, _amount);
        safeTransfer(outToken, msg.sender, _amount);
        emit Convert(msg.sender, _amount);
    }

    /**
     * exit
     */
    function exit() public onlyOwner() {

        require(block.timestamp - createAt > 128 days, "Exit allowed after half-year");

        uint256 _balance = IERC20(outToken).balanceOf(address(this));
        address _exitTo = owner();

        safeTransfer(outToken, _exitTo, _balance);
        emit Exit(_exitTo, _balance);
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'MasterTransfer: TRANSFER_FROM_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'MasterTransfer: TRANSFER_FAILED');
    }
}