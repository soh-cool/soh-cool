pragma solidity 0.6.12;

/**
 * mine SUSHI via SUSHIswap.MasterChef
 * will transferOnwership to stakeGatling
 */
contract StrategyCakeStorage {

    //Sushi MasterChef
    // address public constant stakeRewards = 0x83607165e6b5bD8415209815f2d332B2f4b1263b; //test
    address public constant stakeRewards = 0x73feaa1eE314F8c655E354234017bE2193C9E24E;// BSC-mainnet: CakeChef
    // UniLP ([usdt-eth].part)
    address public  stakeLpPair;
    //earnToken
    // address public constant earnTokenAddr = 0xFFE752d1e648BEfF96E7F3ff4eaA115a71E7615F; //test
    address public constant earnTokenAddr = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82; // BSC-mainnet: Cake
    address public stakeGatling;
    address public admin;
    uint256 public pid;

    event AdminChanged(address previousAdmin, address newAdmin); 

}