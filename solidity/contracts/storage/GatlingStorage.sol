pragma solidity 0.6.12;


interface ISohConfig {
    function sohMaker() external returns (address);
    // 1000-based
    function gatlingFeeRate() external returns (uint256);
}

contract GatlingStorage {
    // UniLP ([usdt-eth].part)
    address public  stakeLpPair;

    address public profitStrategy;

    address public sohConfig;

    // MatchPair.address
    address public matchPair;
    // Uniswsap V2Router
    address public v2Router;

    uint256 public totalAmount;
    uint256 public _presentRate = 1e18;

    uint256 public reprofitCountTotal;
    uint256 public createAt;
    //Update every half day by default
    uint256 public updatesPerDay = 4;
    uint256 public updatesMin;
    uint256 profitRateUpdateTime;

    address[] public routerPath0;
    address[] public routerPath1;

    struct ProfitRateHis {
        uint256 day;
        uint256 profitRateHis;
    }
    ProfitRateHis[] public profitRateHis;
    mapping(uint256 => uint256) public reprofitCount;

    event ProfitStrategyEvent(address _profitStrategy);
    event UpdatesRuleEvent(uint256 _updatesPerDay, uint256  _updatesMin);
    event SetRouter(address _router);
    event ExecUpdateProfitEvent(address indexed _origin, uint256 _amount);
}