// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../library/SafeTransfer.sol";
import "../interface/IDebtToken.sol";
import "./AddressPrivileges.sol";
import "./ImportOracle.sol";
import "../interface/IUniswapV2Router02.sol";

contract PledgePool is ReentrancyGuard, AddressPrivileges, ImportOracle, SafeTransfer{

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    uint256 constant internal calDecimal = 1e18;
    uint256 constant internal feeDecimal = 1e8;

    bool public paused = false;
    // Token Address
    address public stakeToken;
    address public swapRouter;
    address payable public feeAddress;
    // FEE
    uint256 public lendFee;
    uint256 public borrowFee;
    uint256 public liquidationFee;

    uint256 public liquidateThreshold;

    // Information for each pool
    struct PoolInfo{
        uint256 startTime;
        uint256 matchTime;
        uint256 endTime;
        uint256  interestRate;      // Pool fixed interest  (1e8)
        uint256 maxSupply;         // Pool max supply
        uint256 totalSupply;       // Pool actual supply
        uint256 utilization;       // Judging whether the match is successful (1e8)
        uint256 state;             // Pool state, '0'-preparation,'1'-fail,'2'-success,'3'-end,'4'-liquidation
        uint256 pledgeRate;        // Pledge rate (1e8)
        address borrowToken;       // Deposit collateral address
        IDebtToken spCoin;         // sp_token address
        IDebtToken jpCoin;         // jp_token address
        uint256 borrowSupply;      // Total Margin
    }

    // total pool.
    PoolInfo[] public poolInfo;

    // Actual total amount of each pool
    struct TotalAmount {
        uint256 actualTotal0;
        uint256 actualTotal1;
    }
    // Info of pool actual
    TotalAmount[] public totalInfo;

    // Borrow User Info
    struct UserInfo {
        uint256 stakeAmount;
        bool state;
    }
    // Info of each user that stakes tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;

    // event
    event Deposit(address indexed from,address indexed token,uint256 amount,uint256 mintAmount);
    event Withdraw(address indexed from,address indexed token,uint256 amount,uint256 burnAmount);
    event Stake(address indexed from,address indexed token,uint256 amount,uint256 mintAmount);
    event Unstake(address indexed from,address indexed token,uint256 amount,uint256 burnAmount);
    event Swap(address indexed fromCoin,address indexed toCoin,uint256 fromValue,uint256 toValue);
    event Claim(address indexed from,address indexed toCoin,uint256 amount);


     // init info
    constructor(
        address oracle,
        address _stakeToken,
        address _swapRouter,
        address payable _feeAddress
    ) public {
        stakeToken = _stakeToken;
        swapRouter = _swapRouter;
        _oracle = IBscPledgeOracle(oracle);
        feeAddress = _feeAddress;
        lendFee = 0;
        borrowFee = 0;
        liquidationFee = 0;
        liquidateThreshold = 1e7;
    }

    /**
     * @dev Function to set commission
     * @notice The handling fee cannot exceed 10%
     */
    function setFee(uint256 _lendFee,uint256 _borrowFee,uint256 _liquidationFee) onlyOwner external{
        require(_lendFee<1e7 && _borrowFee<1e7 && _liquidationFee<1e7, "fee is beyond the limit");
        lendFee = _lendFee;
        borrowFee = _borrowFee;
        liquidationFee = _liquidationFee;
    }

    /**
     * @dev Function to set swap router address
     */
    function setSwapRouterAddress(address _swapRouter)public onlyOwner{
        require(swapRouter != _swapRouter,"swapRouter : same address");
        swapRouter = _swapRouter;
    }

    /**
     * @dev Function to set fee address
     */
    function setFeeAddress(address payable _addrFee) onlyOwner external {
        feeAddress = _addrFee;
    }

    /**
     * @dev Set the pool matching success condition
     * @notice Pool status must be '0'
     */
    function setUtilization(uint256 _pid,  uint64 _utilization) public onlyOwner {
        // update info
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.state == 0) {
            pool.utilization = _utilization;
        }
    }

     /**
     * @dev Query pool length
     */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @dev Add new pool information, Can only be called by the owner.
     */
    function addPoolInfo(uint256 _startTime,  uint256 _matchTime,  uint256 _endTime, uint64 _interestRate,
                        uint256 _maxSupply, uint256 _utilization, uint256 _pledgeRate,
                        address _borrowToken, address _spToken, address _jpToken) public onlyOwner{
        // check if token has been set ...
        poolInfo.push(PoolInfo({
            startTime: _startTime,
            matchTime: _matchTime,
            endTime: _endTime,
            interestRate: _interestRate,
            maxSupply: _maxSupply,
            totalSupply:0,
            utilization: _utilization,
            state: 0,
            pledgeRate: _pledgeRate,
            borrowToken:_borrowToken,
            spCoin: IDebtToken(_spToken),
            jpCoin: IDebtToken(_jpToken),
            borrowSupply: 0
        }));
        // tatol info init
        totalInfo.push(TotalAmount({
            actualTotal0:0,
            actualTotal1:0
        }));
    }

    /**
     * @dev Update pool information, Can only be called by the owner.
     */
    function updatePoolInfo(uint256 _pid, uint64 _interestRate, uint256 _maxSupply, uint256 _utilization, uint256 _pledgeRate) public onlyOwner{
        // Update pool information based on _pid
        PoolInfo storage pool = poolInfo[_pid];
        pool.interestRate = _interestRate;
        pool.maxSupply = _maxSupply;
        pool.utilization = _utilization;
        pool.pledgeRate = _pledgeRate;
    }

    /**
     * @dev Update pool state
     */
    function updateState(uint256 _pid, uint256 _state) public onlyOwner {
        require(_state == 0 && _state == 1 && _state == 2 && _state == 3 && _state == 4, "Not within the specified range");
        PoolInfo storage pool = poolInfo[_pid];
        pool.state = _state;
    }

    /**
     * @dev Sp_token and actual deposit ratio
     */
    function tokenNetworth(uint256 _pid) public view returns (uint256){
        PoolInfo storage pool = poolInfo[_pid];
        TotalAmount storage total = totalInfo[_pid];
        // sp token num
        uint256 tokenNum = pool.spCoin.totalSupply();
        uint256 totalSupply = total.actualTotal0;
        return (tokenNum > 0 ) ? totalSupply.mul(calDecimal)/tokenNum : calDecimal;
    }


    /**
     * @dev The depositor performs the deposit operation
     * @notice pool state muste be '0'
     */
    function deposit(uint256 _pid, uint256 _stakeAmount) external payable nonReentrant notPause limit(_pid){
        // Time limit
        PoolInfo storage pool = poolInfo[_pid];
        TotalAmount storage total = totalInfo[_pid];
        // Boundary conditions
        require(_stakeAmount <= (pool.maxSupply).sub(pool.totalSupply), "The quantity exceeds the limit");
        require(pool.state == 0, "pool state is not 0");
        uint256 amount = getPayableAmount(stakeToken,_stakeAmount);
        require(amount > 0, "stake amount is zero");
        uint256 netWorth = tokenNetworth(_pid);
        uint256 mintAmount = amount.mul(calDecimal)/netWorth;
        pool.totalSupply = pool.totalSupply.add(_stakeAmount);
        total.actualTotal0 = total.actualTotal0.add(_stakeAmount);
        pool.spCoin.mint(msg.sender, mintAmount);
        emit Deposit(msg.sender, stakeToken, _stakeAmount, mintAmount);
    }

    /**
     * @dev Depositor withdrawal operation
     * @notice pool state muste be '1' or '3', '1' is match fail, '3' is successfully due withdrawal
     */
    function withdraw(uint256 _pid, uint256 _spAmount)  external nonReentrant notPause {
        PoolInfo storage pool = poolInfo[_pid];
        TotalAmount storage total = totalInfo[_pid];
        require(_spAmount > 0, 'unstake amount is zero');
        require(block.timestamp > pool.matchTime, "It's not time to withdraw");
        require(pool.state == 1 || pool.state == 3, "pool state not in 1 or 3");
        if (pool.state == 1 ) {
            // Match failure
            uint256 netWorth = tokenNetworth(_pid);
            uint256 redeemAmount = netWorth.mul(_spAmount)/calDecimal;
            require(redeemAmount <= total.actualTotal0 ,"Available pool liquidity is unsufficient");
            // burn sp_token
            pool.spCoin.burn(msg.sender,_spAmount);
            total.actualTotal0 = total.actualTotal0.sub(redeemAmount);
            // Refund of deposit
            _redeem(msg.sender,stakeToken,redeemAmount);
            emit Withdraw(msg.sender,stakeToken,redeemAmount,_spAmount);
        }
        if (pool.state == 3) {
            // Match success, take out after expiration
            require(block.timestamp > pool.endTime, "Withdraw before the end time");
            uint256 netWorth = tokenNetworth(_pid);
            uint256 redeemAmount = netWorth.mul(_spAmount)/calDecimal;
            require(redeemAmount <= total.actualTotal0,"Available pool liquidity is unsufficient");
            // burn sp_token
            pool.spCoin.burn(msg.sender,_spAmount);
            total.actualTotal0 = total.actualTotal0.sub(redeemAmount);
            // fee
            uint256 userPayback = redeemFees(lendFee,stakeToken,redeemAmount);
             _redeem(msg.sender,stakeToken,userPayback);
            emit Withdraw(msg.sender,stakeToken,userPayback,_spAmount);
        }
    }

    /**
     * @dev Fee calculation
     */
    function redeemFees(uint256 feeRatio,address token,uint256 amount) internal returns (uint256){
        uint256 fee = amount.mul(feeRatio)/feeDecimal;
        if (fee>0){
            _redeem(feeAddress,token, fee);
        }
        return amount.sub(fee);
    }

    /**
     * @dev Borrower pledge operation
     */
    function stake(uint256 _pid, uint256 _stakeAmount, uint256 _deadLine) external payable nonReentrant notPause limit(_pid) ensure(_deadLine){
        // pool info
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        TotalAmount storage total = totalInfo[_pid];
        // oracle price
        uint256[2]memory prices = getUnderlyingPriceView(_pid);
        uint256 amount = pool.borrowSupply.mul(prices[1].mul(calDecimal).div(prices[0])).div(calDecimal);
        uint256 totalAmount = pool.maxSupply.mul(pool.pledgeRate).div(feeDecimal);
        require(totalAmount > amount, "Insufficient quantity remaining");
        require(pool.state == 0, "pool state is not 0");
        uint256 remainAmount = totalAmount.sub(amount);
        uint256 userStakeAmount = _stakeAmount.mul(prices[1].mul(calDecimal).div(prices[0])).div(calDecimal);
        require(userStakeAmount <= remainAmount, "stake amount should be less than the remaining amount");
        amount = getPayableAmount(pool.borrowToken, _stakeAmount);
        require(amount > 0, 'stake amount is zero');
        // update info
        pool.borrowSupply = pool.borrowSupply.add(_stakeAmount);
        total.actualTotal1 = total.actualTotal1.add(_stakeAmount);
        user.stakeAmount = user.stakeAmount.add(_stakeAmount);
        user.state = false;
        emit Deposit(msg.sender, pool.borrowToken, _stakeAmount, _stakeAmount);
    }

    /**
     * @dev Borrower, '1' is get back the deposit, '2' is retrieve loan and jp_token
     */
    function claim(uint256 _pid) external nonReentrant notPause  {
        // pool info
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        TotalAmount storage total = totalInfo[_pid];
        require(block.timestamp > pool.matchTime, "now time must be greater than match time");
        require(pool.state == 1 || pool.state == 2, "pool state not in 1 or 2");
        require(user.stakeAmount > 0, "The user is not pledged");
        if (pool.state == 1) {
            // Get back the deposit
            require(!user.state, "user state is not false");
            uint256 redeemAmount = user.stakeAmount;
            require(redeemAmount < total.actualTotal1, "Insufficient liquidity in the pool");
            _redeem(msg.sender,pool.borrowToken,redeemAmount);
            total.actualTotal1 = total.actualTotal1.sub(redeemAmount);
            user.state = true;
            emit Claim(msg.sender, stakeToken, redeemAmount);
        }
        if (pool.state == 2) {
            // retrieve loan and jp_token
            require(!user.state, "user state is not false");
            uint256[2]memory prices = getUnderlyingPriceView(_pid);
            uint256 price = prices[1].mul(calDecimal).div(prices[0]);
            // Total Margin
            uint256 totalValue = pool.borrowSupply.mul(price).div(calDecimal);
            // Total Borrow
            uint256 totalBorrow = totalValue.mul(feeDecimal).div(pool.pledgeRate);
            // User share
            uint256 userShare = user.stakeAmount.mul(calDecimal).div(pool.borrowSupply);
            // amount
            uint256 redeemAmount = totalBorrow.mul(userShare).div(calDecimal);
            // mint jp_token
            pool.jpCoin.mint(msg.sender, userShare);
            _redeem(msg.sender,stakeToken,redeemAmount);
            // update user info
            user.state = true;
            emit Claim(msg.sender, stakeToken, redeemAmount);
        }
    }

    /**
     * @dev The borrower withdraws the remaining margin
     */
    function unstake(uint256 _pid, uint256 _amount, uint256 _deadLine) external nonReentrant notPause ensure(_deadLine)  {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        TotalAmount storage total = totalInfo[_pid];
        require(block.timestamp < pool.endTime, "now time less than pool end time");
        require(pool.state == 3, "pool state is not 3");
        uint256 jpTokenTotal = pool.jpCoin.totalSupply();
        uint256 Jp_share = total.actualTotal1.mul(calDecimal).div(jpTokenTotal);
        uint256 redeemAmount = Jp_share.mul(_amount).div(calDecimal);
        require(redeemAmount <= total.actualTotal1,"Available pool liquidity is unsufficient");
        // burn jp_token
        pool.jpCoin.burn(msg.sender, _amount);
        total.actualTotal1 = total.actualTotal1.sub(redeemAmount);
        // fee
        uint256 userPayback = redeemFees(borrowFee,pool.borrowToken,redeemAmount);
        // withdraws the remaining margin
        _redeem(msg.sender,pool.borrowToken,userPayback);
        emit Unstake(msg.sender, pool.borrowToken, _amount, userPayback);
    }

    /**
     * @dev Admin update pool status, match time
     * @notice Status changes to '1' or '2'
     */
    function settle() public onlyOwner{
        for (uint256 _pid = 0; _pid < poolInfo.length; _pid++) {
            PoolInfo storage pool = poolInfo[_pid];
            if (pool.state == 0) {
                if (block.timestamp > pool.matchTime) {
                    uint256[2]memory prices = getUnderlyingPriceView(_pid);
                    uint256 price = prices[1].mul(calDecimal).div(prices[0]);
                    uint256 totalValue = pool.borrowSupply.mul(price);
                    uint256 lowStandard = pool.totalSupply.mul(pool.utilization).div(feeDecimal);
                    uint256 highStandard = pool.totalSupply.mul(pool.pledgeRate).div(feeDecimal);
                    // update state
                    if (totalValue > lowStandard && totalValue < highStandard) {
                        pool.state = 2;
                    } else {
                        pool.state = 1;
                    }
                }
            }
        }
    }

    /**
     * @dev Admin update pool status, end time
     */
    function finish(uint256 _pid) public onlyOwner{
        for (uint256 _pid = 0; _pid < poolInfo.length; _pid++) {
            PoolInfo storage pool = poolInfo[_pid];
            TotalAmount storage total = totalInfo[_pid];
            if (pool.state == 2) {
                if (block.timestamp > pool.endTime) {
                    (address token0, address token1) = (pool.borrowToken, stakeToken);
                    // sellamount
                    uint256 rate = pool.interestRate.add(feeDecimal);
                    uint256 sellamount = pool.totalSupply.mul(rate).div(feeDecimal);
                    uint256 borrowAmount = getAmountIn(swapRouter,token0,token1,sellamount);
                    ( ,uint256 amountIn) = sellExactAmount(swapRouter,token0,token1,sellamount);
                    require(amountIn >= pool.totalSupply, "amountIn must be great than totalSupply");
                    pool.state = 3;
                    // update actualTotal0, actualTotal1
                    total.actualTotal0 = amountIn;
                    total.actualTotal1 = total.actualTotal1.sub(borrowAmount);
                }
            }
        }
    }

    /**
     * @dev Check liquidation conditions
     */
    function checkoutLiquidate() external onlyOwner {
        for (uint256 _pid = 0; _pid < poolInfo.length; _pid++) {
            PoolInfo storage pool = poolInfo[_pid];
            if (pool.state == 2) {
                uint256[2]memory prices = getUnderlyingPriceView(_pid);
                if (_checkLiquidateCondition(_pid,prices)){
                    _liquidate(_pid);
                }
            }
        }
    }

    function _checkLiquidateCondition(uint256 _pid, uint256[2]memory prices) internal view returns(bool) {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 price = prices[1].mul(calDecimal).div(prices[0]);
        uint256 borrowValue = pool.borrowSupply.mul(price).div(calDecimal);
        uint256 value = pool.totalSupply.mul(feeDecimal).div(pool.pledgeRate);
        uint256 totalValue = value.mul(liquidateThreshold.add(feeDecimal));
        return borrowValue <= totalValue;
    }

    function _liquidate(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        TotalAmount storage total = totalInfo[_pid];
        require(block.timestamp > pool.matchTime, "now time is less than match time");
        (address token0, address token1) = (pool.borrowToken, stakeToken);
        // sellamount
        uint256 rate = pool.interestRate.add(feeDecimal);
        uint256 sellamount = pool.totalSupply.mul(rate).div(feeDecimal);
        uint256 borrowAmount = getAmountIn(swapRouter,token0,token1,sellamount);
        ( ,uint256 amountIn) = sellExactAmount(swapRouter,token0,token1,sellamount);
        require(amountIn >= pool.totalSupply, "amountIn must be great than totalSupply");
        pool.state = 3;
        // update actualTotal0, actualTotal1
        total.actualTotal0 = amountIn;
        total.actualTotal1 = total.actualTotal1.sub(borrowAmount);
    }


    /**
     * @dev Get the swap path
     */
    function getSwapPath(address swapRouter,address token0,address token1) public pure returns (address[] memory path){
        IUniswapV2Router02 IUniswap = IUniswapV2Router02(swapRouter);
        path = new address[](2);
        path[0] = token0 == address(0) ? IUniswap.WETH() : token0;
        path[1] = token1 == address(0) ? IUniswap.WETH() : token1;
    }

     /**
      * @dev Get input based on output
      */
    function getAmountIn(address swapRouter,address token0,address token1,uint256 amountOut) public view returns (uint256){
        IUniswapV2Router02 IUniswap = IUniswapV2Router02(swapRouter);
        address[] memory path = getSwapPath(swapRouter,token0,token1);
        uint[] memory amounts = IUniswap.getAmountsIn(amountOut, path);
        return amounts[0];
    }

     /**
      * @dev sell Exact Amount
      */
    function sellExactAmount(address swapRouter,address token0,address token1,uint256 amountout) payable public returns (uint256,uint256){
        uint256 amountSell = amountout > 0 ? getAmountIn(swapRouter,token0,token1,amountout) : 0;
        return (amountSell,_swap(swapRouter,token0,token1,amountSell));
    }

    /**
      * @dev Swap
      */
    function _swap(address swapRouter,address token0,address token1,uint256 amount0)public returns (uint256) {
        if (token0 != address(0)){
            safeApprove(token0, address(swapRouter), uint256(-1));
        }
        if (token1 != address(0)){
            safeApprove(token1, address(swapRouter), uint256(-1));
        }
        IUniswapV2Router02 IUniswap = IUniswapV2Router02(swapRouter);
        address[] memory path = getSwapPath(swapRouter,token0,token1);
        uint256[] memory amounts;
        if(token0 == address(0)){
            amounts = IUniswap.swapExactETHForTokens{value:amount0}(0, path,address(this), now+30);
        }else if(token1 == address(0)){
            amounts = IUniswap.swapExactTokensForETH(amount0,0, path, address(this), now+30);
        }else{
            amounts = IUniswap.swapExactTokensForTokens(amount0,0, path, address(this), now+30);
        }
        emit Swap(token0,token1,amounts[0],amounts[amounts.length-1]);
        return amounts[amounts.length-1];
    }

    function safeApprove(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeApprove");
    }

    /**
     * @dev Get the latest oracle price
     */
    function getUnderlyingPriceView(uint256 _pid) public view returns(uint256[2]memory){
        PoolInfo storage pool = poolInfo[_pid];
        uint256[] memory assets = new uint256[](2);
        assets[0] = uint256(stakeToken);
        assets[1] = uint256(pool.borrowToken);
        uint256[]memory prices = oraclegetPrices(assets);
        return [prices[0],prices[1]];
    }

    /**
     * @dev set Pause
     */
    function setPause() public onlyOwner {
        paused = !paused;
    }

    modifier notPause() {
        require(paused == false, "Stake has been suspended");
        _;
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'stake: EXPIRED');
        _;
    }

    modifier limit(uint256 _pid) {
        require(block.timestamp >= poolInfo[_pid].startTime, "Time has not started");
        require(block.timestamp < poolInfo[_pid].matchTime, "Exceed the prescribed time");
        _;
    }

}
