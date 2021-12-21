// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../library/SafeTransfer.sol";
import "../interface/IDebtToken.sol";
import "../interface/IBscPledgeOracle.sol";
import "../interface/IUniswapV2Router02.sol";



contract MockPledgePool is ReentrancyGuard, Ownable, SafeTransfer{

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // default decimal
    uint256 constant internal calDecimal = 1e18;
    // Based on the decimal of the commission and interest
    uint256 constant internal baseDecimal = 1e8;
    uint256 public minAmount = 100e18;

    enum PoolState{ MATCH, EXECUTION, FINISH, LIQUIDATION, UNDONE }
    PoolState constant defaultChoice = PoolState.MATCH;

    bool public globalPaused = false;
    // pancake swap router
    address public swapRouter;
    // receiving fee address
    address payable public feeAddress;
    // oracle address
    IBscPledgeOracle public oracle;
    // fee
    uint256 public lendFee;
    uint256 public borrowFee;

    // Base information for each pool
    struct PoolBaseInfo{
        uint256 settleTime;         // settle time
        uint256 endTime;            // finish time
        uint256 interestRate;       // Fixed interest on the pool, The unit is 1e8 (1e8)
        uint256 maxSupply;          // Maximum pool limit
        uint256 lendSupply;         // Current lend actual deposit
        uint256 borrowSupply;       // Current borrow actual deposit
        uint256 martgageRate;       // Pool mortgage rate, The unit is 1e8 (1e8)
        address lendToken;          // lend stake token address (BUSD..)
        address borrowToken;        // borrow stake token address (BTC..)
        PoolState state;            // 'MATCH, EXECUTION, FINISH, LIQUIDATION, UNDONE'
        IDebtToken spCoin;          // sp_token erc20 address (spBUSD_1..)
        IDebtToken jpCoin;          // jp_token erc20 address (jpBTC_1..)
        uint256 autoLiquidateThreshold; // Auto liquidate Threshold (Trigger liquidation threshold)
    }
    // total base pool.
    PoolBaseInfo[] public poolBaseInfo;

    // Data information for each pool
    struct PoolDataInfo{
        uint256 settleAmountLend;       // settle time of lend actual amount
        uint256 settleAmountBorrow;     // settle time of borrow actual amount
        uint256 finishAmountLend;       // finish time of lend actual amount
        uint256 finishAmountBorrow;     // finish time of borrow actual ampunt
        uint256 liquidationAmounLend;   // liquidation time of lend actual amount
        uint256 liquidationAmounBorrow; // liquidation time of borrow actual amount
    }
    // total data pool
    PoolDataInfo[] public poolDataInfo;

    // Borrow User Info
    struct BorrowInfo {
        uint256 stakeAmount;           // The current pledge amount of borrow
        uint256 refundAmount;          // Excess refund amount
        bool hasNoRefund;              // default false, false = No refund, true = Refunded
        bool hasNoClaim;               // default faslse, false = No claim, true = Claimed
    }
    // Info of each user that stakes tokens.  {user.address : {pool.index : user.borrowInfo}}
    mapping (address => mapping (uint256 => BorrowInfo)) public userBorrowInfo;

    // Lend User Info
    struct LendInfo {
        uint256 stakeAmount;          // The current pledge amount of lend
        uint256 refundAmount;         // Excess refund amount
        bool hasNoRefund;             // default false, false = No refund, true = Refunded
        bool hasNoClaim;              // // default faslse, false = No claim, true = Claimed
    }

    // Info of each user that stakes tokens.  {user.address : {pool.index : user.lendInfo}}
    mapping (address => mapping (uint256 => LendInfo)) public userLendInfo;

    // event
    event DepositLend(address indexed from,address indexed token,uint256 amount,uint256 mintAmount);
    event RefundLend(address indexed from, address indexed token, uint256 refund);
    event ClaimLend(address indexed from, address indexed token, uint256 amount);
    event WithdrawLend(address indexed from,address indexed token,uint256 amount,uint256 burnAmount);
    event DepositBorrow(address indexed from,address indexed token,uint256 amount,uint256 mintAmount);
    event RefundBorrow(address indexed from, address indexed token, uint256 refund);
    event ClaimBorrow(address indexed from, address indexed token, uint256 amount);
    event WithdrawBorrow(address indexed from,address indexed token,uint256 amount,uint256 burnAmount);
    event Swap(address indexed fromCoin,address indexed toCoin,uint256 fromValue,uint256 toValue);
    event EmergencyBorrowWithdrawal(address indexed from, address indexed token, uint256 amount);
    event EmergencyLendWithdrawal(address indexed from, address indexed token, uint256 amount);

    constructor(
        address _oracle,
        address _swapRouter,
        address payable _feeAddress
    ) public {
        require(_oracle != address(0), "Is zero address");
        require(_swapRouter != address(0), "Is zero address");
        require(_feeAddress != address(0), "Is zero address");

        oracle = IBscPledgeOracle(_oracle);
        swapRouter = _swapRouter;
        feeAddress = _feeAddress;
        lendFee = 0;
        borrowFee = 0;
    }

    /**
     * @dev Set the lend fee and borrow fee
     * @notice Only allow administrators to operate
     */
    function setFee(uint256 _lendFee,uint256 _borrowFee) onlyOwner external{
        lendFee = _lendFee;
        borrowFee = _borrowFee;
    }

    function setPoolState(uint256 _pid, uint256 _state) onlyOwner external{
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        require(_state == 0 || _state == 1 || _state == 2 || _state == 3 || _state == 4, "setPoolState: state error");
        if (_state == 0){
            pool.state = PoolState.MATCH;
        } else if (_state == 1){
            pool.state = PoolState.EXECUTION;
        }else if (_state == 2){
            pool.state = PoolState.FINISH;
        }else if (_state == 3){
            pool.state = PoolState.LIQUIDATION;
        }else {
            pool.state = PoolState.UNDONE;
        }
    }


    /**
     * @dev Set swap router address, example pancakeswap or babyswap..
     * @notice Only allow administrators to operate
     */
    function setSwapRouterAddress(address _swapRouter) onlyOwner external{
        require(_swapRouter != address(0), "Is zero address");
        swapRouter = _swapRouter;
    }

    /**
     * @dev Set up the address to receive the handling fee
     * @notice Only allow administrators to operate
     */
    function setFeeAddress(address payable _feeAddress) onlyOwner external {
        require(_feeAddress != address(0), "Is zero address");
        feeAddress = _feeAddress;
    }

    /**
     * @dev Set the min amount
     */
    function setMinAmount(uint256 _minAmount) onlyOwner external {
        minAmount = _minAmount;
    }

     /**
     * @dev Query pool length
     */
    function poolLength() external view returns (uint256) {
        return poolBaseInfo.length;
    }

    /**
     * @dev Create new pool information, Can only be called by the owner.
     */
    function createPoolInfo(uint256 _settleTime,  uint256 _endTime, uint64 _interestRate,
                        uint256 _maxSupply, uint256 _martgageRate, address _lendToken, address _borrowToken,
                    address _spToken, address _jpToken, uint256 _autoLiquidateThreshold) public onlyOwner{
        // check if token has been set ...
        require(_endTime > _settleTime, "createPool:end time grate than settle time");
        require(_jpToken != address(0), "createPool:is zero address");
        require(_spToken != address(0), "createPool:is zero address");

        poolBaseInfo.push(PoolBaseInfo({
            settleTime: _settleTime,
            endTime: _endTime,
            interestRate: _interestRate,
            maxSupply: _maxSupply,
            lendSupply:0,
            borrowSupply:0,
            martgageRate: _martgageRate,
            lendToken:_lendToken,
            borrowToken:_borrowToken,
            state: defaultChoice,
            spCoin: IDebtToken(_spToken),
            jpCoin: IDebtToken(_jpToken),
            autoLiquidateThreshold:_autoLiquidateThreshold
        }));
        // pool data info
        poolDataInfo.push(PoolDataInfo({
            settleAmountLend:0,
            settleAmountBorrow:0,
            finishAmountLend:0,
            finishAmountBorrow:0,
            liquidationAmounLend:0,
            liquidationAmounBorrow:0
        }));
    }

    /**
     * @dev Update pool information, Can only be called by the owner.
     */
    function updatePoolBaseInfo(uint256 _pid, uint64 _interestRate, uint256 _maxSupply, uint256 _autoLiquidateThreshold) public onlyOwner timeBefore(_pid){
        // Update pool information based on _pid
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        pool.interestRate = _interestRate;
        pool.maxSupply = _maxSupply;
        pool.autoLiquidateThreshold = _autoLiquidateThreshold;
    }

      /**
     * @dev Get pool state
     * @notice returned is an int integer
     */
    function getPoolState(uint256 _pid) public view returns (uint256) {
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        return uint256(pool.state);
    }

    /**
     * @dev The depositor performs the deposit operation
     * @notice pool state muste be MATCH
     * @param _pid is pool index
     * @param _stakeAmount is user stake amount
     */
    function depositLend(uint256 _pid, uint256 _stakeAmount) external payable nonReentrant notPause timeBefore(_pid) stateMatch(_pid){
        // limit of time and state
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        LendInfo storage lendInfo = userLendInfo[msg.sender][_pid];
        // Boundary conditions
        require(_stakeAmount <= (pool.maxSupply).sub(pool.lendSupply), "depositLend: the quantity exceeds the limit");
        uint256 amount = getPayableAmount(pool.lendToken,_stakeAmount);
        require(amount > minAmount, "depositLend: less than min amount");
        // Save lend user information
        lendInfo.hasNoClaim = false;
        lendInfo.hasNoRefund = false;
        if (pool.lendToken == address(0)){
            lendInfo.stakeAmount = lendInfo.stakeAmount.add(msg.value);
            pool.lendSupply = pool.lendSupply.add(msg.value);
        } else {
            lendInfo.stakeAmount = lendInfo.stakeAmount.add(_stakeAmount);
            pool.lendSupply = pool.lendSupply.add(_stakeAmount);
        }
        emit DepositLend(msg.sender, pool.lendToken, _stakeAmount, amount);
    }

    /**
     * @dev Refund of excess deposit to depositor
     * @notice Pool status is not equal to match and undone
     * @param _pid is pool index
     */
    function refundLend(uint256 _pid) external nonReentrant notPause timeAfter(_pid) stateNotMatchUndone(_pid){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        LendInfo storage lendInfo = userLendInfo[msg.sender][_pid];
        // limit of amount
        require(lendInfo.stakeAmount > 0, "refundLend: not pledged");
        require(pool.lendSupply.sub(data.settleAmountLend) > 0, "refundLend: not refund");
        require(!lendInfo.hasNoRefund, "refundLend: repeat refund");
        // user share = Current pledge amount / total amount
        uint256 userShare = lendInfo.stakeAmount.mul(calDecimal).div(pool.lendSupply);
        // refundAmount = total refund amount * user share
        uint256 refundAmount = (pool.lendSupply.sub(data.settleAmountLend)).mul(userShare).div(calDecimal);
        // refund action
        _redeem(msg.sender,pool.lendToken,refundAmount);
        // update user info
        lendInfo.hasNoRefund = true;
        lendInfo.refundAmount = lendInfo.refundAmount.add(refundAmount);
        emit RefundLend(msg.sender, pool.lendToken, refundAmount);
    }

    /**
     * @dev Depositor receives sp_token
     * @notice Pool status is not equal to match and undone
     * @param _pid is pool index
     */
    function claimLend(uint256 _pid) external nonReentrant notPause timeAfter(_pid) stateNotMatchUndone(_pid){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        LendInfo storage lendInfo = userLendInfo[msg.sender][_pid];
        // limit of amount
        require(lendInfo.stakeAmount > 0, "claimLend: not claim sp_token");
        require(!lendInfo.hasNoClaim,"claimLend: again claim");
        // user share = Current pledge amount / total amount
        uint256 userShare = lendInfo.stakeAmount.mul(calDecimal).div(pool.lendSupply);
        // totalSpAmount = settleAmountLend
        uint256 totalSpAmount = data.settleAmountLend;
        // user sp amount = totalSpAmount * user share
        uint256 spAmount = totalSpAmount.mul(userShare).div(calDecimal);
        // mint sp token
        pool.spCoin.mint(msg.sender, spAmount);
        // update claim flag
        lendInfo.hasNoClaim = true;
        emit ClaimLend(msg.sender, pool.borrowToken, spAmount);
    }

    /**
     * @dev Depositors withdraw the principal and interest
     * @notice The status of the pool may be finish or liquidation
     * @param _pid is pool index
     * @param _spAmount is burn sp amount
     */
    function withdrawLend(uint256 _pid, uint256 _spAmount)  external nonReentrant notPause stateFinishLiquidation(_pid) {
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        require(_spAmount > 0, 'withdrawLend: withdraw amount is zero');
        // burn sp_token
        pool.spCoin.burn(msg.sender,_spAmount);
        // Calculate the destruction share
        uint256 totalSpAmount = data.settleAmountLend;
        // sp share = _spAmount/totalSpAmount
        uint256 spShare = _spAmount.mul(calDecimal).div(totalSpAmount);
        // FINISH
        if (pool.state == PoolState.FINISH){
            require(block.timestamp > pool.endTime, "withdrawLend: less than end time");
            // redeem amount = finishAmountLend * spShare
            uint256 redeemAmount = data.finishAmountLend.mul(spShare).div(calDecimal);
            // refund active
             _redeem(msg.sender,pool.lendToken,redeemAmount);
            emit WithdrawLend(msg.sender,pool.lendToken,redeemAmount,_spAmount);
        }
        // LIQUIDATION
        if (pool.state == PoolState.LIQUIDATION) {
            require(block.timestamp > pool.settleTime, "withdrawLend: less than match time");
            // redeem amount
            uint256 redeemAmount = data.liquidationAmounLend.mul(spShare).div(calDecimal);
            // refund action
             _redeem(msg.sender,pool.lendToken,redeemAmount);
            emit WithdrawLend(msg.sender,pool.lendToken,redeemAmount,_spAmount);
        }
    }

     /**
     * @dev Emergency withdrawal of Lend
     * @notice pool state must be undone
     * @param _pid is pool index
     */
    function emergencyLendWithdrawal(uint256 _pid) external nonReentrant notPause stateUndone(_pid){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        require(pool.lendSupply > 0,"emergencLend: not withdrawal");
        // lend emergency withdrawal
        LendInfo storage lendInfo = userLendInfo[msg.sender][_pid];
        // limit of amount
        require(lendInfo.stakeAmount > 0, "refundLend: not pledged");
        require(!lendInfo.hasNoRefund, "refundLend: again refund");
        // refund action
        _redeem(msg.sender,pool.lendToken,lendInfo.stakeAmount);
        // update user info
        lendInfo.hasNoRefund = true;
        emit EmergencyLendWithdrawal(msg.sender, pool.lendToken, lendInfo.stakeAmount);
    }



    /**
     * @dev Borrower pledge operation
     * @param _pid is pool index
     * @param _stakeAmount is number of user pledges
     * @param _deadLine is final deadline
     */
    function depositBorrow(uint256 _pid, uint256 _stakeAmount, uint256 _deadLine) external payable nonReentrant notPause timeBefore(_pid) stateMatch(_pid) timeDeadline(_deadLine){
        // base info
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][_pid];
        // action
        uint256 amount = getPayableAmount(pool.borrowToken, _stakeAmount);
        require(amount > 0, 'depositBorrow: deposit amount is zero');
        // save user infomation
        borrowInfo.hasNoClaim = false;
        borrowInfo.hasNoRefund = false;
        // update info
        if (pool.borrowToken == address(0)){
            borrowInfo.stakeAmount = borrowInfo.stakeAmount.add(msg.value);
            pool.borrowSupply = pool.borrowSupply.add(msg.value);
        } else{
            borrowInfo.stakeAmount = borrowInfo.stakeAmount.add(_stakeAmount);
            pool.borrowSupply = pool.borrowSupply.add(_stakeAmount);
        }
        emit DepositBorrow(msg.sender, pool.borrowToken, _stakeAmount, amount);
    }

     /**
     * @dev Refund of excess deposit to borrower
     * @notice Pool status is not equal to match and undone
     * @param _pid is pool state
     */
    function refundBorrow(uint256 _pid) external nonReentrant notPause timeAfter(_pid) stateNotMatchUndone(_pid){
        // base info
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][_pid];
        // conditions
        require(pool.borrowSupply.sub(data.settleAmountBorrow) > 0, "refundBorrow: not refund");
        require(borrowInfo.stakeAmount > 0, "refundBorrow: not pledged");
        require(!borrowInfo.hasNoRefund, "refundBorrow: again refund");
        // Calculate user share
        uint256 userShare = borrowInfo.stakeAmount.mul(calDecimal).div(pool.borrowSupply);
        uint256 refundAmount = (pool.borrowSupply.sub(data.settleAmountBorrow)).mul(userShare).div(calDecimal);
        // action
        _redeem(msg.sender,pool.borrowToken,refundAmount);
        // update user info
        borrowInfo.refundAmount = borrowInfo.refundAmount.add(refundAmount);
        borrowInfo.hasNoRefund = true;
        emit RefundBorrow(msg.sender, pool.borrowToken, refundAmount);
    }

    /**
     * @dev Borrower receives sp_token and loan funds
     * @notice Pool status is not equal to match and undone
     * @param _pid is pool state
     */
    function claimBorrow(uint256 _pid) external nonReentrant notPause timeAfter(_pid) stateNotMatchUndone(_pid)  {
        // pool base info
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][_pid];
        // limit
        require(borrowInfo.stakeAmount > 0, "claimBorrow: not claim jp_token");
        require(!borrowInfo.hasNoClaim,"claimBorrow: again claim");
        // total jp amount = settleAmountLend * martgageRate
        uint256 totalJpAmount = data.settleAmountLend.mul(pool.martgageRate).div(baseDecimal);
        uint256 userShare = borrowInfo.stakeAmount.mul(calDecimal).div(pool.borrowSupply);
        uint256 jpAmount = totalJpAmount.mul(userShare).div(calDecimal);
        // mint jp token
        pool.jpCoin.mint(msg.sender, jpAmount);
        // claim loan funds
        uint256 borrowAmount = data.settleAmountLend.mul(userShare).div(calDecimal);
        _redeem(msg.sender,pool.lendToken,borrowAmount);
        // update user info
        borrowInfo.hasNoClaim = true;
        emit ClaimBorrow(msg.sender, pool.borrowToken, jpAmount);
    }

    /**
     * @dev The borrower withdraws the remaining margin
     * @param _pid is pool state
     * @param _jpAmount is number of users destroying JPtoken
     * @param _deadLine is final deadline
     */
    function withdrawBorrow(uint256 _pid, uint256 _jpAmount, uint256 _deadLine) external nonReentrant notPause timeDeadline(_deadLine) stateFinishLiquidation(_pid) {
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        require(_jpAmount > 0, 'withdrawBorrow: withdraw amount is zero');
        // burn jp token
        pool.jpCoin.burn(msg.sender,_jpAmount);
        // jp share
        uint256 totalJpAmount = data.settleAmountLend.mul(pool.martgageRate).div(baseDecimal);
        uint256 jpShare = _jpAmount.mul(calDecimal).div(totalJpAmount);
        // finish
        if (pool.state == PoolState.FINISH) {
            require(block.timestamp > pool.endTime, "withdrawBorrow: less than end time");
            uint256 redeemAmount = jpShare.mul(data.finishAmountBorrow).div(calDecimal);
            _redeem(msg.sender,pool.borrowToken,redeemAmount);
            emit WithdrawBorrow(msg.sender, pool.borrowToken, _jpAmount, redeemAmount);
        }
        // liquition
        if (pool.state == PoolState.LIQUIDATION){
            require(block.timestamp > pool.settleTime, "withdrawBorrow: less than match time");
            uint256 redeemAmount = jpShare.mul(data.liquidationAmounBorrow).div(calDecimal);
            _redeem(msg.sender,pool.borrowToken,redeemAmount);
            emit WithdrawBorrow(msg.sender, pool.borrowToken, _jpAmount, redeemAmount);
        }
    }

    /**
     * @dev Emergency withdrawal of Borrow
     * @notice In extreme cases, the total deposit is 0, or the total margin is 0
     * @param _pid is pool index
     */
    function emergencyBorrowWithdrawal(uint256 _pid) external nonReentrant notPause stateUndone(_pid) {
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        require(pool.borrowSupply > 0,"emergencyBorrow: not withdrawal");
        // borrow emergency withdrawal
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][_pid];
        require(borrowInfo.stakeAmount > 0, "refundBorrow: not pledged");
        require(!borrowInfo.hasNoRefund, "refundBorrow: again refund");
        // action
        _redeem(msg.sender,pool.borrowToken,borrowInfo.stakeAmount);
        borrowInfo.hasNoRefund = true;
        emit EmergencyBorrowWithdrawal(msg.sender, pool.borrowToken, borrowInfo.stakeAmount);
    }

    /**
     * @dev Can it be settle
     * @param _pid is pool index
     */
    function checkoutSettle(uint256 _pid) public view returns(bool){
        return block.timestamp > poolBaseInfo[_pid].settleTime;
    }

    /**
     * @dev  Settle
     * @param _pid is pool index
     */
    function settle(uint256 _pid) public onlyOwner {
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        require(block.timestamp > poolBaseInfo[_pid].settleTime, "settle: less than settleTime");
        require(pool.state == PoolState.MATCH, "settle: pool state must be match");
        if (pool.lendSupply > 0 && pool.borrowSupply > 0) {
            // oracle price
            uint256[2]memory prices = getUnderlyingPriceView(_pid);
            // Total Margin Value = Margin amount * Margin price
            uint256 totalValue = pool.borrowSupply.mul(prices[1].mul(calDecimal).div(prices[0])).div(calDecimal);
            // Converted into stable currency value
            uint256 actualValue = totalValue.mul(baseDecimal).div(pool.martgageRate);
            if (pool.lendSupply > actualValue){
                // total lend grate than total borrow
                data.settleAmountLend = actualValue;
                data.settleAmountBorrow = pool.borrowSupply;
            } else {
                // total lend less than total borrow
                data.settleAmountLend = pool.lendSupply;
                data.settleAmountBorrow = pool.lendSupply.mul(pool.martgageRate).div(prices[1].mul(baseDecimal).div(prices[0]));
            }
            // update pool state
            pool.state = PoolState.EXECUTION;
        } else {
            // extreme case, Either lend or borrow is 0
            pool.state = PoolState.UNDONE;
            data.settleAmountLend = pool.lendSupply;
            data.settleAmountBorrow = pool.borrowSupply;
        }
    }

    /**
     * @dev Can it be finish
     * @param _pid is pool index
     */
    function checkoutFinish(uint256 _pid) public view returns(bool){
        return block.timestamp > poolBaseInfo[_pid].endTime;
    }

    /**
     * @dev finish
     * @param _pid is pool index
     */
    function finish(uint256 _pid) public onlyOwner {
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        require(block.timestamp > poolBaseInfo[_pid].endTime, "finish: less than end time");
        require(pool.state == PoolState.EXECUTION,"finish: pool state must be execution");
        // parameter
        (address token0, address token1) = (pool.borrowToken, pool.lendToken);
        // sellAmount = (lend*(1+rate))*(1+lendFee)
        uint256 lendAmount = data.settleAmountLend.mul(pool.interestRate.add(baseDecimal)).div(baseDecimal);
        uint256 sellAmount = lendAmount.mul(lendFee.add(baseDecimal)).div(baseDecimal);
        (uint256 amountSell,uint256 amountIn) = _sellExactAmount(swapRouter,token0,token1,sellAmount);
        // '>' lend fee is not 0 , '=' lendfee is 0
        require(amountIn >= lendAmount, "finish: Slippage is too high");
        if (amountIn > lendAmount) {
            uint256 feeAmount = amountIn.sub(lendAmount) ;
            // lend fee
            _redeem(feeAddress,pool.lendToken, feeAmount);
            data.finishAmountLend = amountIn.sub(feeAmount);
        }else {
            data.finishAmountLend = amountIn;
        }
        // borrow fee
        uint256 remianNowAmount = data.settleAmountBorrow.sub(amountSell);
        uint256 remianLendAmount = redeemFees(lendFee,pool.borrowToken,remianNowAmount);
        data.finishAmountBorrow = remianLendAmount;
        // update pool state
        pool.state = PoolState.FINISH;
    }


    /**
     * @dev Check liquidation conditions
     * @param _pid is pool index
     */
    function checkoutLiquidate(uint256 _pid) external view returns(bool) {
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        // Margin price
        uint256[2]memory prices = getUnderlyingPriceView(_pid);
        // Current value of margin = margin amount * margin price
        uint256 borrowValueNow = data.settleAmountBorrow.mul(prices[1].mul(calDecimal).div(prices[0])).div(calDecimal);
        // Liquidation threshold = settleAmountLend*(1+autoLiquidateThreshold)
        uint256 valueThreshold = data.settleAmountLend.mul(baseDecimal.add(pool.autoLiquidateThreshold)).div(baseDecimal);
        return borrowValueNow < valueThreshold;
    }

    /**
     * @dev Liquidation
     * @param _pid is pool index
     */
    function liquidate(uint256 _pid) public onlyOwner {
        PoolDataInfo storage data = poolDataInfo[_pid];
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        require(block.timestamp > pool.settleTime, "now time is less than match time");
        require(pool.state == PoolState.EXECUTION,"liquidate: pool state must be execution");
        // sellamount
        (address token0, address token1) = (pool.borrowToken, pool.lendToken);
        uint256 lendAmount = data.settleAmountLend.mul(pool.interestRate.add(baseDecimal)).div(baseDecimal);
        // Add lend fee
        uint256 sellAmount = lendAmount.mul(lendFee.add(baseDecimal)).div(baseDecimal);
        (uint256 amountSell,uint256 amountIn) = _sellExactAmount(swapRouter,token0,token1,sellAmount);
        // There may be slippage, amountIn - lendAmount < 0;
        if (amountIn > lendAmount) {
            uint256 feeAmount = amountIn.sub(lendAmount) ;
            // lend fee
            _redeem(feeAddress,pool.lendToken, feeAmount);
            data.liquidationAmounLend = amountIn.sub(feeAmount);
        }else {
            data.liquidationAmounLend = amountIn;
        }
        // liquidationAmounBorrow  borrow Fee
        uint256 remianNowAmount = data.settleAmountBorrow.sub(amountSell);
        uint256 remianBorrowAmount = redeemFees(borrowFee,pool.borrowToken,remianNowAmount);
        data.liquidationAmounBorrow = remianBorrowAmount;
        // update pool state
        pool.state = PoolState.LIQUIDATION;
    }


    /**
     * @dev Fee calculation
     */
    function redeemFees(uint256 feeRatio,address token,uint256 amount) internal returns (uint256){
        uint256 fee = amount.mul(feeRatio)/baseDecimal;
        if (fee>0){
            _redeem(feeAddress,token, fee);
        }
        return amount.sub(fee);
    }



    /**
     * @dev Get the swap path
     */
    function _getSwapPath(address _swapRouter,address token0,address token1) internal pure returns (address[] memory path){
        IUniswapV2Router02 IUniswap = IUniswapV2Router02(_swapRouter);
        path = new address[](2);
        path[0] = token0 == address(0) ? IUniswap.WETH() : token0;
        path[1] = token1 == address(0) ? IUniswap.WETH() : token1;
    }

     /**
      * @dev Get input based on output
      */
    function _getAmountIn(address _swapRouter,address token0,address token1,uint256 amountOut) internal view returns (uint256){
        IUniswapV2Router02 IUniswap = IUniswapV2Router02(_swapRouter);
        address[] memory path = _getSwapPath(swapRouter,token0,token1);
        uint[] memory amounts = IUniswap.getAmountsIn(amountOut, path);
        return amounts[0];
    }

     /**
      * @dev sell Exact Amount
      */
    function _sellExactAmount(address _swapRouter,address token0,address token1,uint256 amountout) internal returns (uint256,uint256){
        uint256 amountSell = amountout > 0 ? _getAmountIn(swapRouter,token0,token1,amountout) : 0;
        return (amountSell,_swap(_swapRouter,token0,token1,amountSell));
    }

    /**
      * @dev Swap
      */
    function _swap(address _swapRouter,address token0,address token1,uint256 amount0) internal returns (uint256) {
        if (token0 != address(0)){
            _safeApprove(token0, address(_swapRouter), uint256(-1));
        }
        if (token1 != address(0)){
            _safeApprove(token1, address(_swapRouter), uint256(-1));
        }
        IUniswapV2Router02 IUniswap = IUniswapV2Router02(_swapRouter);
        address[] memory path = _getSwapPath(_swapRouter,token0,token1);
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

    /**
     * @dev Approve
     */
    function _safeApprove(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeApprove");
    }

    /**
     * @dev Get the latest oracle price
     */
    function getUnderlyingPriceView(uint256 _pid) public view returns(uint256[2]memory){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        uint256[] memory assets = new uint256[](2);
        assets[0] = uint256(pool.lendToken);
        assets[1] = uint256(pool.borrowToken);
        uint256[]memory prices = oracle.getPrices(assets);
        return [prices[0],prices[1]];
    }

    /**
     * @dev set Pause
     */
    function setPause() public onlyOwner {
        globalPaused = !globalPaused;
    }

    modifier notPause() {
        require(globalPaused == false, "Stake has been suspended");
        _;
    }

    modifier timeDeadline(uint256 _deadline) {
        require(_deadline >= block.timestamp, 'stake: EXPIRED');
        _;
    }

    modifier timeBefore(uint256 _pid) {
        require(block.timestamp < poolBaseInfo[_pid].settleTime, "Less than this time");
        _;
    }

    modifier timeAfter(uint256 _pid) {
        require(block.timestamp > poolBaseInfo[_pid].settleTime, "Greate than this time");
        _;
    }


    modifier stateMatch(uint256 _pid) {
        require(poolBaseInfo[_pid].state == PoolState.MATCH, "state: Pool status is not equal to match");
        _;
    }

    modifier stateNotMatchUndone(uint256 _pid) {
        require(poolBaseInfo[_pid].state == PoolState.EXECUTION || poolBaseInfo[_pid].state == PoolState.FINISH || poolBaseInfo[_pid].state == PoolState.LIQUIDATION,"state: not match and undone");
        _;
    }

    modifier stateFinishLiquidation(uint256 _pid) {
        require(poolBaseInfo[_pid].state == PoolState.FINISH || poolBaseInfo[_pid].state == PoolState.LIQUIDATION,"state: finish liquidation");
        _;
    }

    modifier stateUndone(uint256 _pid) {
        require(poolBaseInfo[_pid].state == PoolState.UNDONE,"state: state must be undone");
        _;
    }

}
