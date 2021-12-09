// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../library/SafeTransfer.sol";
import "../interface/IDebtToken.sol";
import "../interface/IBscPledgeOracle.sol";
import "../interface/IUniswapV2Router02.sol";



contract PledgePool is ReentrancyGuard, Ownable, SafeTransfer{

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    uint256 constant internal calDecimal = 1e18;
    uint256 constant internal feeDecimal = 1e8;
    uint256 public minAmount = 100e18;

    enum PoolState{ MATCH, EXECUTION, FINISH, LIQUIDATION, UNDONE }
    PoolState constant defaultChoice = PoolState.MATCH;

    bool public paused = false;
    address public swapRouter;
    address payable public feeAddress;
    // oracle address
    IBscPledgeOracle public oracle;
    // fee
    uint256 public lendFee;
    uint256 public borrowFee;

    // Base information for each pool
    struct PoolBaseInfo{
        uint256 matchTime;          // settle time
        uint256 endTime;            // finish time
        uint256 interestRate;       // Pool fixed interest  (1e8)
        uint256 maxSupply;          // Pool max supply
        uint256 lendSupply;         // Pool lend actual supply
        uint256 borrowSupply;       // Pool borrow actual supply
        uint256 pledgeRate;         // Pledge rate (1e8)
        address lendToken;          // lend stake address
        address borrowToken;        // borrow stake address
        PoolState state;            // 'MATCH, EXECUTION, FINISH, LIQUIDATION'
        IDebtToken spCoin;          // sp_token erc20 address
        IDebtToken jpCoin;          // jp_token erc20 address
        uint256 autoLiquidateThreshold; // Liquidate Threshold
    }
    // total base pool.
    PoolBaseInfo[] public poolBaseInfo;

    // Data information for each pool
    struct PoolDataInfo{
        uint256 settleAmount0;     // settle time of lend actual amount
        uint256 settleAmount1;     // settle time of borrow actual amount
        uint256 finishAmount0;     // finish time of lend actual amount
        uint256 finishAmount1;     // finish time of borrow actual ampunt
        uint256 liquidationAmoun0; // liquidation of lend actual amount
        uint256 liquidationAmoun1; // liquidation of borrow actual amount
    }

    PoolDataInfo[] public poolDataInfo;

    // Borrow User Info
    struct BorrowInfo {
        uint256 stakeAmount;
        uint256 refundAmount;
        bool refundFlag;
        bool claimFlag;
    }
    // Info of each user that stakes tokens.
    mapping (address => mapping (uint256 => BorrowInfo)) public userBorrowInfo;

    // Lend User Info
    struct LendInfo {
        uint256 stakeAmount;
        uint256 refundAmount;
        bool refundFlag;
        bool claimFlag;
    }

    // Info of each user that stakes tokens.
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
        oracle = IBscPledgeOracle(_oracle);
        swapRouter = _swapRouter;
        feeAddress = _feeAddress;
        lendFee = 0;
        borrowFee = 0;
    }

    /**
     * @dev Function to set commission
     * @notice The  fee
     */
    function setFee(uint256 _lendFee,uint256 _borrowFee) onlyOwner external{
        lendFee = _lendFee;
        borrowFee = _borrowFee;
    }

    /**
     * @dev Function to set swap router address
     */
    function setSwapRouterAddress(address _swapRouter) onlyOwner external{
        swapRouter = _swapRouter;
    }

    /**
     * @dev Function to set fee address
     */
    function setFeeAddress(address payable _feeAddress) onlyOwner external {
        feeAddress = _feeAddress;
    }

     /**
     * @dev Query pool length
     */
    function poolLength() external view returns (uint256) {
        return poolBaseInfo.length;
    }

    /**
     * @dev Add new pool information, Can only be called by the owner.
     */
    function createPoolInfo(uint256 _matchTime,  uint256 _endTime, uint64 _interestRate,
                        uint256 _maxSupply, uint256 _pledgeRate, address _lendToken, address _borrowToken,
                    address _spToken, address _jpToken, uint256 _autoLiquidateThreshold) public onlyOwner{
        // check if token has been set ...
        poolBaseInfo.push(PoolBaseInfo({
            matchTime: _matchTime,
            endTime: _endTime,
            interestRate: _interestRate,
            maxSupply: _maxSupply,
            lendSupply:0,
            borrowSupply:0,
            pledgeRate: _pledgeRate,
            lendToken:_lendToken,
            borrowToken:_borrowToken,
            state: defaultChoice,
            spCoin: IDebtToken(_spToken),
            jpCoin: IDebtToken(_jpToken),
            autoLiquidateThreshold:_autoLiquidateThreshold
        }));
        // pool data info
        poolDataInfo.push(PoolDataInfo({
            settleAmount0:0,
            settleAmount1:0,
            finishAmount0:0,
            finishAmount1:0,
            liquidationAmoun0:0,
            liquidationAmoun1:0
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
     * @dev get pool state
     */
    function getPoolState(uint256 _pid) public view returns (uint256) {
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        return uint256(pool.state);
    }

    /**
     * @dev The depositor performs the deposit operation
     * @notice pool state muste be MATCH
     */
    function depositLend(uint256 _pid, uint256 _stakeAmount) external payable nonReentrant notPause timeBefore(_pid) stateMatch(_pid){
        // limit of time and state
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        LendInfo storage lendInfo = userLendInfo[msg.sender][_pid];
        // Boundary conditions
        require(_stakeAmount <= (pool.maxSupply).sub(pool.lendSupply), "depositLend: the quantity exceeds the limit");
        uint256 amount = getPayableAmount(pool.lendToken,_stakeAmount);
        require(amount > minAmount, "depositLend: min amount is 100");
        // Save lend user information
        lendInfo.claimFlag = false;
        lendInfo.refundFlag = false;
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
     * @notice pool state muste be Execution
     */
    function refundLend(uint256 _pid) external nonReentrant notPause timeAfter(_pid) stateNotMatchUndone(_pid){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        LendInfo storage lendInfo = userLendInfo[msg.sender][_pid];
        // limit
        require(lendInfo.stakeAmount > 0, "refundLend: not pledged");
        require(pool.lendSupply.sub(data.settleAmount0) > 0, "refundLend: not refund");
        require(!lendInfo.refundFlag, "refundLend: repeat refund");
        // Calculate user share
        uint256 userShare = lendInfo.stakeAmount.mul(calDecimal).div(pool.lendSupply);
        uint256 refundAmount = (pool.lendSupply.sub(data.settleAmount0)).mul(userShare).div(calDecimal);
        _redeem(msg.sender,pool.lendToken,refundAmount);
        // update user info
        lendInfo.refundFlag = true;
        lendInfo.refundAmount = lendInfo.refundAmount.add(refundAmount);
        emit RefundLend(msg.sender, pool.lendToken, refundAmount);
    }

    /**
     * @dev Depositor receives sp_token
     * @notice pool state muste be Execution
     */
    function claimLend(uint256 _pid) external nonReentrant notPause timeAfter(_pid) stateNotMatchUndone(_pid){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        LendInfo storage lendInfo = userLendInfo[msg.sender][_pid];
        require(lendInfo.stakeAmount > 0, "claimLend: not claim sp_token");
        require(!lendInfo.claimFlag,"claimLend: again claim");
        // user of sp_token amount
        uint256 userShare = lendInfo.stakeAmount.mul(calDecimal).div(pool.lendSupply);
        // totalSpAmount = amount0*(interestRate+1)
        uint256 totalSpAmount = data.settleAmount0.mul(pool.interestRate.add(feeDecimal)).div(feeDecimal);
        uint256 spAmount = totalSpAmount.mul(userShare).div(calDecimal);
        // mint sp token
        pool.spCoin.mint(msg.sender, spAmount);
        // update claim flag
        lendInfo.claimFlag = true;
        emit ClaimLend(msg.sender, pool.borrowToken, spAmount);
    }

    /**
     * @dev Depositors withdraw the principal and interest
     * @notice The status of the pool may be executed or liquidation
     */
    function withdrawLend(uint256 _pid, uint256 _spAmount)  external nonReentrant notPause stateFinishLiquidation(_pid) {
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        require(_spAmount > 0, 'withdrawLend: withdraw amount is zero');
        // burn sp_token
        pool.spCoin.burn(msg.sender,_spAmount);
        // sp share
        uint256 totalSpAmount = data.settleAmount0.mul(pool.interestRate.add(feeDecimal)).div(feeDecimal);
        uint256 spShare = _spAmount.mul(calDecimal).div(totalSpAmount);
        // FINISH
        if (pool.state == PoolState.FINISH){
            require(block.timestamp > pool.endTime, "withdrawLend: less than end time");
            // redeem amount
            uint256 redeemAmount = data.finishAmount0.mul(spShare).div(calDecimal);
             _redeem(msg.sender,pool.lendToken,redeemAmount);
            emit WithdrawLend(msg.sender,pool.lendToken,redeemAmount,_spAmount);
        }
        // LIQUIDATION
        if (pool.state == PoolState.LIQUIDATION) {
            require(block.timestamp > pool.matchTime, "withdrawLend: less than match time");
            // redeem amount
            uint256 redeemAmount = data.liquidationAmoun0.mul(spShare).div(calDecimal);
             _redeem(msg.sender,pool.lendToken,redeemAmount);
            emit WithdrawLend(msg.sender,pool.lendToken,redeemAmount,_spAmount);
        }
    }

     /**
     * @dev Emergency withdrawal of Lend
     */
    function emergencyLendWithdrawal(uint256 _pid) external nonReentrant notPause stateUndone(_pid){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        require(pool.lendSupply > 0,"emergencLend: not withdrawal");
        // lend emergency withdrawal
        LendInfo storage lendInfo = userLendInfo[msg.sender][_pid];
        require(lendInfo.stakeAmount > 0, "refundLend: not pledged");
        require(!lendInfo.refundFlag, "refundLend: again refund");
        _redeem(msg.sender,pool.lendToken,lendInfo.stakeAmount);
        lendInfo.refundFlag = true;
        emit EmergencyLendWithdrawal(msg.sender, pool.lendToken, lendInfo.stakeAmount);
    }



    /**
     * @dev Borrower pledge operation
     */
    function depositBorrow(uint256 _pid, uint256 _stakeAmount, uint256 _deadLine) external payable nonReentrant notPause timeBefore(_pid) stateMatch(_pid) timeDeadline(_deadLine){
        // base info
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][_pid];
        uint256 amount = getPayableAmount(pool.borrowToken, _stakeAmount);
        require(amount > 0, 'depositBorrow: deposit amount is zero');
        // save user infomation
        borrowInfo.claimFlag = false;
        borrowInfo.refundFlag = false;
        if (pool.borrowToken == address(0)){
            borrowInfo.stakeAmount = borrowInfo.stakeAmount.add(msg.value);
            // update info
            pool.borrowSupply = pool.borrowSupply.add(msg.value);
        } else{
            borrowInfo.stakeAmount = borrowInfo.stakeAmount.add(_stakeAmount);
            // update info
            pool.borrowSupply = pool.borrowSupply.add(_stakeAmount);
        }
        emit DepositBorrow(msg.sender, pool.borrowToken, _stakeAmount, amount);
    }

     /**
     * @dev Refund of excess deposit to borrower
     * @notice pool state muste be Execution
     */
    function refundBorrow(uint256 _pid) external nonReentrant notPause timeAfter(_pid) stateNotMatchUndone(_pid){
        // base info
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][_pid];
        // conditions
        require(pool.borrowSupply.sub(data.settleAmount1) > 0, "refundBorrow: not refund");
        require(borrowInfo.stakeAmount > 0, "refundBorrow: not pledged");
        require(!borrowInfo.refundFlag, "refundBorrow: again refund");
        // Calculate user share
        uint256 userShare = borrowInfo.stakeAmount.mul(calDecimal).div(pool.borrowSupply);
        uint256 refundAmount = (pool.borrowSupply.sub(data.settleAmount1)).mul(userShare).div(calDecimal);
        _redeem(msg.sender,pool.borrowToken,refundAmount);
        // update info
        borrowInfo.refundAmount = borrowInfo.refundAmount.add(refundAmount);
        borrowInfo.refundFlag = true;
        emit RefundBorrow(msg.sender, pool.borrowToken, refundAmount);
    }

    /**
     * @dev Borrower receives sp_token and loan funds
     * @notice pool state muste be Execution
     */
    function claimBorrow(uint256 _pid) external nonReentrant notPause timeAfter(_pid) stateNotMatchUndone(_pid)  {
        // pool base info
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][_pid];
        // limit
        require(borrowInfo.stakeAmount > 0, "claimBorrow: not claim jp_token");
        require(!borrowInfo.claimFlag,"claimBorrow: again claim");
        // total jp amount = settleAmount0 * pledgeRate
        uint256 totalJpAmount = data.settleAmount0.mul(pool.pledgeRate).div(feeDecimal);
        uint256 userShare = borrowInfo.stakeAmount.mul(calDecimal).div(pool.borrowSupply);
        uint256 jpAmount = totalJpAmount.mul(userShare).div(calDecimal);
        // mint jp token
        pool.jpCoin.mint(msg.sender, jpAmount);
        // claim loan funds
        uint256 borrowAmount = data.settleAmount0.mul(userShare).div(calDecimal);
        _redeem(msg.sender,pool.lendToken,borrowAmount);
        // update user info
        borrowInfo.claimFlag = true;
        emit ClaimBorrow(msg.sender, pool.borrowToken, jpAmount);
    }

    /**
     * @dev The borrower withdraws the remaining margin
     */
    function withdrawBorrow(uint256 _pid, uint256 _jpAmount, uint256 _deadLine) external nonReentrant notPause timeDeadline(_deadLine) stateFinishLiquidation(_pid) {
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        require(_jpAmount > 0, 'withdrawBorrow: withdraw amount is zero');
        // burn jp token
        pool.jpCoin.burn(msg.sender,_jpAmount);
        // jp share
        uint256 totalJpAmount = data.settleAmount0.mul(pool.pledgeRate).div(feeDecimal);
        uint256 jpShare = _jpAmount.mul(calDecimal).div(totalJpAmount);
        // finish
        if (pool.state == PoolState.FINISH) {
            require(block.timestamp > pool.endTime, "withdrawBorrow: less than end time");
            uint256 redeemAmount = jpShare.mul(data.finishAmount1).div(calDecimal);
            _redeem(msg.sender,pool.borrowToken,redeemAmount);
            emit WithdrawBorrow(msg.sender, pool.borrowToken, _jpAmount, redeemAmount);
        }
        // liquition
        if (pool.state == PoolState.LIQUIDATION){
            require(block.timestamp > pool.matchTime, "withdrawBorrow: less than match time");
            uint256 redeemAmount = jpShare.mul(data.liquidationAmoun1).div(calDecimal);
            _redeem(msg.sender,pool.borrowToken,redeemAmount);
            emit WithdrawBorrow(msg.sender, pool.borrowToken, _jpAmount, redeemAmount);
        }
    }

    /**
     * @dev Emergency withdrawal of Borrow
     * @notice In extreme cases, the total deposit is 0, or the total margin is 0
     */
    function emergencyBorrowWithdrawal(uint256 _pid) external nonReentrant notPause stateUndone(_pid) {
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        require(pool.borrowSupply > 0,"emergencyBorrow: not withdrawal");
        // borrow emergency withdrawal
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][_pid];
        require(borrowInfo.stakeAmount > 0, "refundBorrow: not pledged");
        require(!borrowInfo.refundFlag, "refundBorrow: again refund");
        _redeem(msg.sender,pool.borrowToken,borrowInfo.stakeAmount);
        borrowInfo.refundFlag = true;
        emit EmergencyBorrowWithdrawal(msg.sender, pool.borrowToken, borrowInfo.stakeAmount);
    }

    /**
     * @dev Can it be settle
     */
    function checkoutSettle(uint256 _pid) public view returns(bool){
        return block.timestamp > poolBaseInfo[_pid].matchTime;
    }

    /**
     * @dev  Settle
     */
    function settle(uint256 _pid) public onlyOwner {
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        require(block.timestamp > poolBaseInfo[_pid].matchTime, "settle: less than matchtime");
        require(pool.state == PoolState.MATCH, "settle: pool state must be match");
        if (pool.lendSupply > 0 && pool.borrowSupply > 0) {
            // oracle price
            uint256[2]memory prices = getUnderlyingPriceView(_pid);
            uint256 totalValue = pool.borrowSupply.mul(prices[1].mul(calDecimal).div(prices[0])).div(calDecimal);
            uint256 actualValue = totalValue.mul(feeDecimal).div(pool.pledgeRate);
            if (pool.lendSupply > actualValue){
                // total lend grate than total borrow
                data.settleAmount0 = actualValue;
                data.settleAmount1 = pool.borrowSupply;
            } else {
                // total lend less than total borrow
                data.settleAmount0 = pool.lendSupply;
                data.settleAmount1 = pool.lendSupply.mul(pool.pledgeRate).div(prices[1].mul(feeDecimal).div(prices[0]));
            }
            // update pool state
            pool.state = PoolState.EXECUTION;
        } else {
            // extreme case
            pool.state = PoolState.UNDONE;
            data.settleAmount0 = pool.lendSupply;
            data.settleAmount1 = pool.borrowSupply;
        }
    }

    /**
     * @dev Can it be finish
     */
    function checkoutFinish(uint256 _pid) public view returns(bool){
        return block.timestamp > poolBaseInfo[_pid].endTime;
    }

    /**
     * @dev finish
     */
    function finish(uint256 _pid) public onlyOwner {
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        require(block.timestamp > poolBaseInfo[_pid].endTime, "finish: less than end time");
        require(pool.state == PoolState.EXECUTION,"finish: pool state must be execution");
        // parameter
        (address token0, address token1) = (pool.borrowToken, pool.lendToken);
        // sellAmount = (lend*(1+rate))*(1+lendFee)
        uint256 lendAmount = data.settleAmount0.mul(pool.interestRate.add(feeDecimal)).div(feeDecimal);
        uint256 sellAmount = lendAmount.mul(lendFee.add(feeDecimal)).div(feeDecimal);
        (uint256 amountSell,uint256 amountIn) = _sellExactAmount(swapRouter,token0,token1,sellAmount);
        // '>' lend fee is not 0 , '=' lendfee is 0
        require(amountIn >= lendAmount, "finish: Slippage is too high");
        if (amountIn > lendAmount) {
            uint256 feeAmount = amountIn.sub(lendAmount) ;
            // lend fee
            _redeem(feeAddress,pool.lendToken, feeAmount);
            data.finishAmount0 = amountIn.sub(feeAmount);
        }else {
            data.finishAmount0 = amountIn;
        }
        // borrow fee
        uint256 remianNowAmount = data.settleAmount1.sub(amountSell);
        uint256 remianLendAmount = redeemFees(lendFee,pool.borrowToken,remianNowAmount);
        data.finishAmount1 = remianLendAmount;
        // update pool state
        pool.state = PoolState.FINISH;
    }


    /**
     * @dev Check liquidation conditions
     */
    function checkoutLiquidate(uint256 _pid) external view returns(bool) {
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        uint256[2]memory prices = getUnderlyingPriceView(_pid);
        uint256 borrowValueNow = data.settleAmount1.mul(prices[1].mul(calDecimal).div(prices[0])).div(calDecimal);
        uint256 valueThreshold = data.settleAmount0.mul(feeDecimal.add(pool.autoLiquidateThreshold)).div(feeDecimal);
        return borrowValueNow < valueThreshold;
    }

    /**
     * @dev Liquidation
     */
    function liquidate(uint256 _pid) public onlyOwner {
        PoolDataInfo storage data = poolDataInfo[_pid];
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        require(block.timestamp > pool.matchTime, "now time is less than match time");
        // sellamount
        (address token0, address token1) = (pool.borrowToken, pool.lendToken);
        uint256 lendAmount = data.settleAmount0.mul(pool.interestRate.add(feeDecimal)).div(feeDecimal);
        // Add lend fee
        uint256 sellAmount = lendAmount.mul(lendFee.add(feeDecimal)).div(feeDecimal);
        (uint256 amountSell,uint256 amountIn) = _sellExactAmount(swapRouter,token0,token1,sellAmount);
        // There may be slippage, amountIn - lendAmount < 0;
        if (amountIn > lendAmount) {
            uint256 feeAmount = amountIn.sub(lendAmount) ;
            // lend fee
            _redeem(feeAddress,pool.lendToken, feeAmount);
            data.liquidationAmoun0 = amountIn.sub(feeAmount);
        }else {
            data.liquidationAmoun0 = amountIn;
        }
        // liquidationAmoun1  borrow Fee
        uint256 remianNowAmount = data.settleAmount1.sub(amountSell);
        uint256 remianBorrowAmount = redeemFees(borrowFee,pool.borrowToken,remianNowAmount);
        data.liquidationAmoun1 = remianBorrowAmount;
        // update pool state
        pool.state = PoolState.LIQUIDATION;
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
        paused = !paused;
    }

    modifier notPause() {
        require(paused == false, "Stake has been suspended");
        _;
    }

    modifier timeDeadline(uint256 _deadline) {
        require(_deadline >= block.timestamp, 'stake: EXPIRED');
        _;
    }

    modifier timeBefore(uint256 _pid) {
        require(block.timestamp < poolBaseInfo[_pid].matchTime, "Less than this time");
        _;
    }

    modifier timeAfter(uint256 _pid) {
        require(block.timestamp > poolBaseInfo[_pid].matchTime, "Greate than this time");
        _;
    }


    modifier stateMatch(uint256 _pid) {
        require(poolBaseInfo[_pid].state == PoolState.MATCH, "Pool status is not equal to match");
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
