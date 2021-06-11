pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// File @openzeppelin/contracts/cryptography/MerkleProof.sol@v3.4.0
/**
 * @dev These functions deal with verification of Merkle trees (hash trees),
 */
library MerkleProof {
    /**
     * @dev Returns true if a `leaf` can be proved to be a part of a Merkle tree
     * defined by `root`. For this, a `proof` must be provided, containing
     * sibling hashes on the branch from the leaf to the root of the tree. Each
     * pair of leaves and each pair of pre-images are assumed to be sorted.
     */
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                // Hash(current computed hash + current element of the proof)
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Hash(current element of the proof + current computed hash)
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        // Check if the computed hash (root) is equal to the provided root
        return computedHash == root;
    }
}

contract MerkleDistributor is  Ownable {
    address public immutable token;
    bytes32 public merkleRoot;
    uint32 public month;
    bool public frozen;

    // This is a packed array of booleans.
    mapping( uint256 => mapping(uint256 => bool) ) private claimedBitMap;

    event Claimed(uint256 index, uint256 amount, address indexed account, uint256 indexed month);
    event MerkleRootUpdated(bytes32 indexed merkleRoot, uint32 indexed month);

    constructor(address token_, bytes32 merkleRoot_) public {
        token = token_;
        merkleRoot = merkleRoot_;
        month = 0;
        frozen = false;
    }

    function isClaimed(uint256 index) public view returns (bool) {
        
        return claimedBitMap[month][index];
    }

    function _setClaimed(uint256 index) private {
       
        claimedBitMap[month][index] = true;
    }

    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external {
        require(!frozen, 'MerkleDistributor: Claiming is frozen.');
        require(!isClaimed(index), 'MerkleDistributor: Drop already claimed.');

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        
        require(MerkleProof.verify(merkleProof, merkleRoot, node), 'MerkleDistributor: Invalid proof.');

        // Mark it claimed and send the token.
        _setClaimed(index);
        require(IERC20(token).transfer(account, amount), 'MerkleDistributor: Transfer failed.');

        emit Claimed(index, amount, account, month);
    }

    function freeze() public onlyOwner {
        frozen = true;
    }

    function unfreeze() public onlyOwner {
        frozen = false;
    }

    function updateMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
        require(frozen, 'MerkleDistributor: Contract not frozen.');

        // Increment the month (simulates the clearing of the claimedBitMap)
        month = month + 1;
        // Set the new merkle root
        merkleRoot = _merkleRoot;
        emit MerkleRootUpdated(merkleRoot, month);
    }

    function emergencyExit(address _to) public onlyOwner {
        IERC20(token).transfer(_to, IERC20(token).balanceOf(address(this)));
    }
}