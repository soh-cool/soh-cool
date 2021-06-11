pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./SohToken.sol";
import "./interfaces/IMatchPair.sol";
import './interfaces/IWETH.sol';
import './interfaces/IMintRegulator.sol';
import "./interfaces/IProxyRegistry.sol";
import './TrustList.sol';
import './PausePool.sol';





// SohMaster is the master of Soh. He can make Soh and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SOH is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract SohMaster is TrustList, IProxyRegistry, PausePool{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // using Address for address;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 buff;       // if not `0`,1000-based, allow NFT Manager adjust the value of buff 

        uint256 totalDeposit;
        uint256 totalWithdraw;
    }

    // Info of each pool.
    struct PoolInfo {
        IMatchPair matchPair;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SOHs to distribute per block.

        uint256 lastRewardBlock;  // Last block number that SOHs distribution occurs by token0.

        uint256 totalDeposit0;  // totol deposit token0
        uint256 totalDeposit1;  // totol deposit token0

        uint256 accSohPerShare0; // Accumulated SOHs per share, times 1e12. See below.
        uint256 accSohPerShare1; // Accumulated SOHs per share, times 1e12. See below.
    }

    uint256 constant public VERSION = 2;
    bool private initialized;
    // The SOH TOKEN!
    SohToken public soh;
    // Dev address.
    address public devaddr;
    // 10% is the community reserve, which is used by voting through governance contracts
    address public ecosysaddr;
    // 0.5% fee will be collect , then repurchase Soh and distribute to depositor
    address public repurchaseaddr;
    // NFT will be published in future, for a interesting mining mode  
    address public nftProphet;

    address public WETH;
    //IMintRegulator 
    address public mintRegulator;
    // Block number when bonus SOH period ends.
    uint256 public bonusEndBlock;
    // SOH tokens created per block.
    uint256 public baseSohPerBlock;
    uint256 public sohPerBlock;
    // Bonus muliplier for early soh makers.
    uint256 public bonus_multiplier;
    uint256 public maxAcceptMultiple;
    uint256 public maxAcceptMultipleDenominator;

    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when SOH mining starts.
    uint256 public startBlock;
    // Fee repurchase SOH and redistribution
    uint256 public periodFinish;
    uint256 public feeRewardRate;
    // Prevent the invasion of giant whales
    bool public whaleSpear;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP(token0/token1) tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo0;
    mapping (uint256 => mapping (address => UserInfo)) public userInfo1;
    // MatchPair delegatecall implmention
    mapping (uint256 => address) public matchPairRegistry;
    mapping (uint256 => bool) public matchPairPause;
    
    event Deposit(address indexed user, uint256 indexed pid, uint256 indexed index, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 indexed index, uint256 amount);
    event SohPerBlockUpdated(address indexed user, uint256 _molecular, uint256 _denominator);
    event WithdrawSohToken(address indexed user, uint256 indexed pid, uint256 sohAmount0, uint256 sohAmount1);

    function initialize(
            SohToken _soh,
            address _devaddr,
            address _ecosysaddr,
            address _repurchaseaddr,
            address _weth,
            address _owner
        ) public {
        require(!initialized, "Contract instance has already been initialized");
        initialized = true;

        soh = _soh;
        devaddr = _devaddr;
        ecosysaddr = _ecosysaddr;
        repurchaseaddr = _repurchaseaddr;
        WETH = _weth;
        initOwner(_owner);
    }

    function initSetting(
        uint256 _sohPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _bonus_multiplier)
        external
        onlyOwner()
    {
        require(initialized, "Not initialized");
        require(startBlock == 0, "Init only once");
        sohPerBlock = _sohPerBlock;
        bonusEndBlock = _bonusEndBlock;
        startBlock = _startBlock;
        baseSohPerBlock = _sohPerBlock;
        bonus_multiplier = _bonus_multiplier;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }
    /**
     * @dev adjust mint number by regulater.getScale()
     */
    function setMintRegulator(address _regulator) external onlyOwner() {
        mintRegulator = _regulator;
    }
    /**
     * @notice register delegate implementation
     */
    function matchPairRegister(uint256 _index, address _implementation) external onlyOwner() {
        matchPairRegistry[_index] = _implementation;
    }
    /**
     * @dev setting max accept multiple. must > 1
     * maxDepositAmount = pool.lp.tokenAmount * multiple - pool.pendingAmount
     */
    function setWhaleSpearRange(uint _maxAcceptMultiple, uint _maxAcceptMultipleDenominator) external onlyOwner() {
        maxAcceptMultiple = _maxAcceptMultiple;
        maxAcceptMultipleDenominator = _maxAcceptMultipleDenominator;
    }

    //@notice Prevent unilateral mining of large amounts of funds
    function holdWhaleSpear(bool _hold) external onlyOwner {
        require(maxAcceptMultiple > 0 && maxAcceptMultipleDenominator >0, "require call setWhaleSpearRange() first");
        whaleSpear = _hold;
    }
    
    function setNFTProphet(address _nftProphet) external onlyOwner()  {
        nftProphet = _nftProphet;
    }
    
    function updateSohPerBlock() public {
        require(mintRegulator != address(0), "IMintRegulator not setting");

        (uint256 _molecular, uint256 _denominator)  = IMintRegulator(mintRegulator).getScale();
        uint256 sohPerBlockNew = baseSohPerBlock.mul(_molecular).div(_denominator);
        if(sohPerBlock != sohPerBlockNew) {
             massUpdatePools();
             sohPerBlock = sohPerBlockNew;
        }
    
        emit SohPerBlockUpdated(msg.sender, _molecular, _denominator);
    }
    //Reserve shares for cross-chain
    function reduceSoh(uint256 _reduceAmount) external onlyOwner() {

        baseSohPerBlock = baseSohPerBlock.sub(baseSohPerBlock.mul(_reduceAmount).div(soh.maxMint()));
        soh.reduce(_reduceAmount);
        //update Pool
        massUpdatePools();
        //update sohPerBlock
        if(mintRegulator != address(0)) {
            updateSohPerBlock();
        }else {
            sohPerBlock = baseSohPerBlock;
        }

    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IMatchPair _matchPair) external onlyOwner {

        massUpdatePools();
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            matchPair: _matchPair,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            totalDeposit0: 0,
            totalDeposit1: 0,
            accSohPerShare0: 0,
            accSohPerShare1: 0
            }));
    }
   
    //@notice Update the given pool's SOH allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) external onlyOwner {

        massUpdatePools();
        
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {

        if(_from < startBlock) {
            _from = startBlock;
        }

        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(bonus_multiplier);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return bonusEndBlock.sub(_from).mul(bonus_multiplier).add(
                _to.sub(bonusEndBlock)
            );
        }
    }

    // View function to see pending SOHs on frontend.
    function pendingSoh(uint256 _pid, uint256 _index, address _user) external view   returns (uint256) {
        //if over limit pending is burn
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = _index == 0? userInfo0[_pid][_user] : userInfo1[_pid][_user];

        uint256 accSohPerShare = _index == 0? pool.accSohPerShare0 : pool.accSohPerShare1;
        uint256 lpSupply = _index == 0? pool.totalDeposit0 : pool.totalDeposit1;


        if (block.number > pool.lastRewardBlock && lpSupply != 0) {            
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            
            uint256 sohReward = multiplier.mul(sohPerBlock).mul(pool.allocPoint).div(totalAllocPoint);//
            uint256 totalMint = soh.totalSupply();
            if(soh.maxMint()< totalMint.add(sohReward)) {
                sohReward = soh.maxMint().sub(totalMint);
            }
            sohReward = getFeeRewardAmount(pool.allocPoint, pool.lastRewardBlock).add(sohReward);
            accSohPerShare = accSohPerShare.add(sohReward.mul(1e12).div(lpSupply).div(2));
        } 
        return  amountBuffed(user.amount, user.buff).mul(accSohPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {

        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 totalDeposit0 = pool.totalDeposit0;
        uint256 totalDeposit1 = pool.totalDeposit1;

        if(totalDeposit0.add(totalDeposit1) > 0 ) {
            uint256 sohReward;
            if(!soh.mintOver()) {
                uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
                sohReward = multiplier.mul(sohPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            }
            //add fee Reward if exist
            sohReward = getFeeRewardAmount(pool.allocPoint, pool.lastRewardBlock).add(sohReward);
            // token0 side
            if(totalDeposit0 > 0) {
                pool.accSohPerShare0 = pool.accSohPerShare0.add(sohReward.mul(1e12).div(totalDeposit0).div(2));
            }
            // token1 side
            if(totalDeposit1 > 0) {
                pool.accSohPerShare1 = pool.accSohPerShare1.add(sohReward.mul(1e12).div(totalDeposit1).div(2));
            }
            if(totalDeposit0 ==0 || totalDeposit1==0) {
                sohReward = sohReward.div(2);
            }



            if(sohReward > 0){        
                soh.mint(devaddr, sohReward.mul(17).div(68)); // 17%
                soh.mint(ecosysaddr, sohReward.mul(15).div(68)); // 15%
                soh.mint(address(this), sohReward); // 68%
            }
        }
        
        pool.lastRewardBlock = block.number;
    }

    function getFeeRewardAmount(uint allocPoint, uint256 lastRewardBlock ) private view returns (uint256 feeReward) {
        if(feeRewardRate > 0) {

            uint256 endPoint = block.number < periodFinish ? block.number : periodFinish;
            if(endPoint > lastRewardBlock) {
                feeReward = endPoint.sub(lastRewardBlock).mul(feeRewardRate).mul(allocPoint).div(totalAllocPoint);
            }
        }
    }

    function batchGrantBuff(uint256[] calldata _pid, uint256[] calldata _index, uint256[] calldata _value, address[] calldata _user) public {
        require(msg.sender == nftProphet, "Grant buff: Prophet allowed");
        require(_pid.length > 0 , "_pid.length is zore");
        require(_pid.length ==  _index.length ,   "Require length equal: pid, index");
        require(_index.length ==  _value.length , "Require length equal: index, _value");
        require(_value.length ==  _user.length ,  "Require length equal: _value, _user");
        
        uint256 length = _pid.length;

        for (uint256 i = 0; i < length; i++) {
           grantBuff(_pid[i], _index[i], _value[i], _user[i]);
        }
    }

    function grantBuff(uint256 _pid, uint256 _index, uint256 _value, address _user) public {
        require(msg.sender == nftProphet, "Grant buff: Prophet allowed");
        require(_index < 2, "Index must 0 or 1" );

        UserInfo storage user = _index == 0  ? userInfo0[_pid][_user] : userInfo1[_pid][_user];
        // if user.amount == 0, just set `buff` value
        if (user.amount > 0) { // && !soh.mintOver()
            updatePool(_pid);

            PoolInfo storage pool = poolInfo[_pid];
            uint256 accPreShare;
            if(_index == 0) {
               accPreShare = pool.accSohPerShare0;
               pool.totalDeposit0 = pool.totalDeposit0
                                    .sub(amountBuffed(user.amount, user.buff))
                                    .add(amountBuffed(user.amount, _value));
            }else {
               accPreShare = pool.accSohPerShare1;
               pool.totalDeposit1 = pool.totalDeposit1
                                    .sub(amountBuffed(user.amount, user.buff))
                                    .add(amountBuffed(user.amount, _value));
            }

            uint256 pending = amountBuffed(user.amount, user.buff).mul(accPreShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeSohTransfer(_user, pending);
            }
            user.rewardDebt = amountBuffed(user.amount, _value).mul(accPreShare).div(1e12);
        }
        user.buff = _value;
    }

    function depositEth(uint256 _pid, uint256 _index ) external payable {
        uint256 _amount = msg.value;
        uint256 acceptAmount;
        PoolInfo storage pool = poolInfo[_pid];
        if(whaleSpear) {
            acceptAmount = pool.matchPair.maxAcceptAmount(_index, maxAcceptMultiple, maxAcceptMultipleDenominator, _amount);
        }else {
            acceptAmount = _amount;
        }
        require(pool.matchPair.token(_index) == WETH, "DepositEth: Index incorrect");
        IWETH(WETH).deposit{value: acceptAmount}();
        deposit(_pid, _index, acceptAmount);
        //chargeback
        if(_amount > acceptAmount) {
            safeTransferETH(msg.sender , _amount.sub(acceptAmount));
        }
    }

    // Deposit LP tokens to SohMaster.
    function deposit(uint256 _pid, uint256 _index,  uint256 _amount) whenNotPaused(_pid) public  {
        require(_index < 2, "Index must 0 or 1" );
        //check account (normalAccount || trustable)
        checkAccount(msg.sender);
        bool _index0 = _index == 0;
        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = _index0 ? userInfo0[_pid][msg.sender] : userInfo1[_pid][msg.sender];
        updatePool(_pid);
        if(whaleSpear) {

            _amount = pool.matchPair.maxAcceptAmount(_index, maxAcceptMultiple, maxAcceptMultipleDenominator, _amount);

        }
        
        uint256 accPreShare = _index0 ? pool.accSohPerShare0 : pool.accSohPerShare1;
       
        if (user.amount > 0) {//&& !soh.mintOver()
            uint256 pending = amountBuffed(user.amount, user.buff).mul(accPreShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeSohTransfer(msg.sender, pending);
            }
        }

        if(_amount > 0) {
            address tokenTarget = pool.matchPair.token(_index);
            if(tokenTarget == WETH) {
                safeTransfer(WETH, address(pool.matchPair), _amount);
            }else{
                safeTransferFrom( pool.matchPair.token(_index), msg.sender,  address(pool.matchPair), _amount);
            }
            //stake to MatchPair
            pool.matchPair.stake(_index, msg.sender, _amount);
            user.amount = user.amount.add(_amount);
            user.totalDeposit = user.totalDeposit.add(_amount); 
            if(_index0) {
                pool.totalDeposit0 = pool.totalDeposit0.add(amountBuffed(_amount, user.buff));
            }else {
                pool.totalDeposit1 = pool.totalDeposit1.add(amountBuffed(_amount, user.buff));
            }
        }


        user.rewardDebt = amountBuffed(user.amount, user.buff).mul(accPreShare).div(1e12);
        emit Deposit(msg.sender, _pid, _index, _amount);
    }

    function withdrawToken(uint256 _pid, uint256 _index, uint256 _amount) external {
        require(_index < 2, "Index must 0 or 1" );
        address _user = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];

        //withdrawToken from MatchPair
        (uint256 untakeTokenAmount, uint256 leftAmount) = pool.matchPair.untakeToken(_index, _user, _amount);
        address targetToken = pool.matchPair.token(_index);


        uint256 userAmount = untakeTokenAmount.mul(995).div(1000);

        withdraw(_pid, _index, _user, untakeTokenAmount, leftAmount);
        if(targetToken == WETH) {

            IWETH(WETH).withdraw(untakeTokenAmount);

            safeTransferETH(_user, userAmount);
            safeTransferETH(repurchaseaddr, untakeTokenAmount.sub(userAmount) );
        }else {
            safeTransfer(pool.matchPair.token(_index),  _user, userAmount);
            safeTransfer(pool.matchPair.token(_index),  repurchaseaddr, untakeTokenAmount.sub(userAmount));
        }
    }
    // Withdraw LP tokens from SohMaster.
    function withdraw( uint256 _pid, uint256 _index, address _user, uint256 _amount, uint256 _leftAmount) whenNotPaused(_pid)  private {
        
        bool _index0 = _index == 0;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = _index0? userInfo0[_pid][_user] :  userInfo1[_pid][_user];
        //record withdraw origin Amount
        user.totalWithdraw = user.totalWithdraw.add(_amount);

        updatePool(_pid);

        uint256 accPreShare = _index0 ? pool.accSohPerShare0 : pool.accSohPerShare1;
        uint256 pending = amountBuffed(user.amount, user.buff).mul(accPreShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeSohTransfer(_user, pending);
        }

        if(_index0) {
            pool.totalDeposit0 = pool.totalDeposit0
                                .add(amountBuffed(_leftAmount, user.buff))
                                .sub(amountBuffed(user.amount, user.buff));
        }else {
             pool.totalDeposit1 = pool.totalDeposit1
                                .add(amountBuffed(_leftAmount, user.buff))
                                .sub(amountBuffed(user.amount, user.buff));
        }
        user.amount = _leftAmount;
        user.rewardDebt = amountBuffed(user.amount, user.buff).mul(accPreShare).div(1e12);
        emit Withdraw(_user, _pid, _index, _amount);
    }
    /**
     * @dev withdraw SOHToken mint by deposit token0 & token1
     */
    function withdrawSoh(uint256 _pid) external {

        updatePool(_pid);

        uint256 sohAmount0 = withdrawSohCalcu(_pid, 0, msg.sender);
        uint256 sohAmount1 = withdrawSohCalcu(_pid, 1, msg.sender);

        safeSohTransfer(msg.sender, sohAmount0.add(sohAmount1));
        
        emit WithdrawSohToken(msg.sender, _pid, sohAmount0, sohAmount1);
    }

    function withdrawSohCalcu(uint256 _pid, uint256 _index,  address _user) private returns (uint256 sohAmount) {
        bool _index0 = _index == 0;
        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = _index0 ? userInfo0[_pid][_user] : userInfo1[_pid][_user];
        
        uint256 accPreShare = _index0 ? pool.accSohPerShare0 : pool.accSohPerShare1;

        if (user.amount > 0) {
            sohAmount = amountBuffed(user.amount, user.buff).mul(accPreShare).div(1e12).sub(user.rewardDebt);
        }
        user.rewardDebt = amountBuffed(user.amount, user.buff).mul(accPreShare).div(1e12);
    }

    // Safe soh transfer function, just in case if rounding error causes pool to not have enough SOHs.
    function safeSohTransfer(address _to, uint256 _amount) internal {
        uint256 sohBal = soh.balanceOf(address(this));
        if (_amount > sohBal) {
            require(soh.transfer(_to, sohBal),'SafeSohTransfer: transfer failed');
            // soh.transfer(_to, sohBal);
        } else {
            require(soh.transfer(_to, _amount),'SafeSohTransfer: transfer failed');
            // soh.transfer(_to, _amount);
        }
    }

    function amountBuffed(uint256 amount, uint256 buff) private pure returns (uint256) {
        if(buff == 0) {
            return amount;
        }else {
            return amount.mul(buff).div(1000);
        }
    }

    function mintableAmount(uint256 _pid, uint256 _index, address _user) external view returns (uint256) {

        UserInfo storage user = _index == 0? userInfo0[_pid][_user] :  userInfo1[_pid][msg.sender];
        return user.amount;
    }


    function getProxy(uint256 _index) external  view override returns(address) {
        require(!matchPairPause[_index], "Proxy paused, waiting upgrade via governance");
        return matchPairRegistry[_index];
    }

    /**
     * @notice to protect fund of users, 
     * allow developers to pause then upgrade via community governor
     */
    function pauseProxy(uint256 _pid, bool _paused) external {
        require(msg.sender == devaddr, "dev sender required");
        matchPairPause[_pid] = _paused;
    }

    function pause(uint256 _pid, bool _paused) external {
        require(msg.sender == devaddr, "dev sender required");
        pausePoolViaPid(_pid, _paused);
    }
    // Update dev address by the previous dev.
    function dev(address _devaddr) external {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function ecosys(address _ecosysaddraddr) external {
        require(msg.sender == ecosysaddr, "ecosys: wut?");
        ecosysaddr = _ecosysaddraddr;
    }
    
    function repurchase(address _repurchaseaddr) external {
        require(msg.sender == repurchaseaddr, "repurchase: wut?");
        repurchaseaddr = _repurchaseaddr;
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

    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'MasterTransfer: ETH_TRANSFER_FAILED');
    }

    function notifyRewardAmount(uint256 reward, uint256 duration)
        onlyOwner
        external
    {
        //update all poll first
        massUpdatePools();
        if (block.number >= periodFinish) {
            feeRewardRate = reward.div(duration);
        } else {
            uint256 remaining = periodFinish.sub(block.number);
            uint256 leftover = remaining.mul(feeRewardRate);
            feeRewardRate = reward.add(leftover).div(duration);
        }
        periodFinish = block.number.add(duration);

    }

    function checkAccount(address _account) private {
        require(_account == tx.origin || trustable(_account) , "High risk account");
    }

    receive() external payable {
        require(msg.sender == WETH, "only accept from WETH"); // only accept ETH via fallback from the WETH contract
    }
}