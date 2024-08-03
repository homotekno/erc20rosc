// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@thirdweb-dev/contracts/eip/interface/IERC20.sol";

contract erc20rosc {
    address public admin;
    mapping(address => bool) public isAllowed;
    mapping(address => string) public userName;

    IERC20 public erc20FiatContract;

    uint256 public slots;
    uint256 public instalmentAmount;
    uint256 public duration;
    uint256 public collateral;
    uint256 public feePercent;
    uint256 public slash;

    uint256 public slotsLeft;
    uint256 public currentRound;
    mapping(address => bool) public isUser;
    mapping(address => uint256) public userCollateral;
    mapping(address => uint256) public userDeposits;
    address[] public Users;
    address[] public Rafflelist;
    mapping(address => bool) public hasWon;

    mapping(uint256 => mapping(address => bool)) public hasPaidRound;
    mapping(uint256 => mapping(address => bool)) public hasBidRound;
    mapping(uint256 => mapping(address => uint256)) public userBidforRound;

    mapping(uint256 => uint256) public totalPotforRound;
    mapping(uint256 => uint256) public highestBidforRound;
    mapping(uint256 => address) public highestBidderforRound;

    mapping(uint256 => uint256) public defaultersForRound;
    mapping(uint256 => uint256) public totalSlashforRound;
    mapping(uint256 => uint256) public winningPotforRound;
    mapping(uint256 => uint256) public winningSlashforRound;

    mapping(uint256 => uint256) public dueAmountforRound;
    mapping(uint256 => uint256) public dividendAmountforRound;    
    
    mapping(uint256 => uint256) public collateralDividendforRound;
    mapping(uint256 => uint256) public feesOnPotforRound;
    mapping(uint256 => uint256) public feesOnSlashforRound;

    mapping(uint256 => address) public winnerforRound;

    mapping(uint256 => bool) public potWithdrawnforRound;
    mapping(uint256 => bool) public feesWithdrawnforRound;

    bool public payBidWindow;
    bool public fundStatus;
    // mods
    // m.admin
    modifier onlyAdmin(){
        require(msg.sender == admin, "only admin can call this function !!");
        _;
    }
    // active fund?
    modifier activeFund(){
        require(fundStatus, "No active funds at the moment !!");
        _;
    }
    // window
    modifier activePayBidWindow(){
        require(payBidWindow, "payment/bidding window is closed !!");
        _;
    }

    // event
    event userEnrolled(address _user);  

    constructor(uint256 _slots, uint256 _instalmentAmount, uint256 _collateral, uint256 _feePercent, uint256 _duration) {

        admin = msg.sender;
        erc20FiatContract = IERC20(0xA755f72E3106C7e59D269A2FB0Bacb5a5373fC6A);
        slots = _slots;
        instalmentAmount = _instalmentAmount * (10**18);
        slotsLeft = slots;
        collateral = _collateral;
        feePercent = _feePercent;
        duration = _duration * 60;

        currentRound = 0;
        slash = collateral/slots;

        fundStatus = true;

        // balancing
        dividendAmountforRound[0] = 0;
    }

    function allowListUser(address _userAddress, string calldata _userName ) external onlyAdmin{
        isAllowed[_userAddress] = true;
        userName[_userAddress] = _userName;
    }
    // restart fund
    function restartFund(uint256 _slots, uint256 _instalmentAmount, uint256 _collateral, uint256 _feePercent, uint256 _duration) external onlyAdmin(){
        require(!fundStatus, "The previous fund remains unfinished!!");
        slots = _slots;
        instalmentAmount = _instalmentAmount * (10**18);
        slotsLeft = slots;
        collateral = _collateral;
        feePercent = _feePercent;
        duration = _duration * 60;

        currentRound = 0;
        slash = collateral/slots;

        // balancing
        fundStatus = true;
        dividendAmountforRound[0] = 0;
    }

    // enroll allowed user to the fund
    function enrollUser() external payable activeFund{
        // checks
        require(isAllowed[msg.sender], "you are not on the allowlist !!");
        require(!isUser[msg.sender], "you are already enrolled !!");
        require(slotsLeft > 0, "sorry slots are full !!");
        require(currentRound == 0, "fund has already started");
        require(msg.value == collateral, "please pay the exact collateral !!");
        // actions
        isUser[msg.sender] = true;
        userCollateral[msg.sender] = msg.value;
        Users.push(msg.sender);
        userDeposits[msg.sender] = 0;
        hasWon[msg.sender] = false;

        slotsLeft--;
    }
    // start a round of chits
    function startROSCRound() external onlyAdmin activeFund{
        require(slotsLeft == 0, "Slots are yet to be filled!");
        currentRound++;
        payBidWindow = true;
        dueAmountforRound[currentRound] = instalmentAmount - dividendAmountforRound[currentRound - 1];

        uint256 tokenBalance = erc20FiatContract.balanceOf(address(this));
        totalPotforRound[currentRound] = 0 + tokenBalance;


        highestBidforRound[currentRound] = 0;
        highestBidderforRound[currentRound] = admin;

        defaultersForRound[currentRound] = 0;
        totalSlashforRound[currentRound] = 0;
        winningPotforRound[currentRound] = 0;
        winningSlashforRound[currentRound] = 0;

        collateralDividendforRound[currentRound] = 0;
        feesOnPotforRound[currentRound] = 0;
        feesOnSlashforRound[currentRound] = 0;

        winnerforRound[currentRound] = admin;

        delete Rafflelist;

        potWithdrawnforRound[currentRound] = false;
        feesWithdrawnforRound[currentRound] = false;

        // initiate userBidforRound       
    }
    // instalment for the round
    function payROSCRound() external activePayBidWindow{
        require(isUser[msg.sender], "you are not enrolled for this fund !!");
        require(!hasPaidRound[currentRound][msg.sender], "you have already paid this round !!");
        // uint256 allowanceROSC = erc20FiatContract.allowance(msg.sender, address(this));
        // require(allowanceROSC >= instalmentAmount, "insufficient token allowance");
        require(erc20FiatContract.transferFrom(msg.sender, address(this), dueAmountforRound[currentRound]), "ROSC txn failed !!");

        // actions
        hasPaidRound[currentRound][msg.sender] = true;
        totalPotforRound[currentRound] += dueAmountforRound[currentRound];
        userDeposits[msg.sender] += dueAmountforRound[currentRound];
    }
    // auction for the round
    function bidROSCRound(uint256 _bid) external activePayBidWindow{
        // checks
        require(isUser[msg.sender], "you are not enrolled for this fund !!");
        require(!hasWon[msg.sender], "uh-oh! winners cannot bid, sorry !!");
        require(hasPaidRound[currentRound][msg.sender], "complete payment for the round to bid the pot !!");
        require( _bid <= 21 && _bid > highestBidforRound[currentRound], " 2% <= bid >= 21% || new bids > highest bids");
        // actions
        hasBidRound[currentRound][msg.sender] = true;
        userBidforRound[currentRound][msg.sender] = _bid;
        if(_bid > highestBidforRound[currentRound]){
            highestBidforRound[currentRound] = _bid;
            highestBidderforRound[currentRound] = msg.sender;
        }
    }

    // ========================================================================
    // ======================================================================== 

    // close pay-bid window - time based?
    function closePBWindow() internal onlyAdmin activePayBidWindow{
        payBidWindow = false;
    }
    // slash collateral amount of defaulters
    function slashDefaulters() internal onlyAdmin returns(uint256){
        uint256 slashCount = 0;
        for(uint i = 0; i < Users.length; i++){
            address defaulter = Users[i];
            if(!hasPaidRound[currentRound][defaulter]){
                slashCount++;
                userCollateral[defaulter] -= slash;
            }
        }
        return slashCount;
    }
    // collateral dividends/gains/yield
    function collateralGains(uint256 _collateralDividend) internal onlyAdmin{
        for(uint256 i = 0; i < Users.length; i++){
            userCollateral[Users[i]] += _collateralDividend;
        }
    }
    // settlement calculations
    function settlementCalculations() external onlyAdmin{
        closePBWindow();
        defaultersForRound[currentRound] = slashDefaulters(); 
        totalSlashforRound[currentRound] = defaultersForRound[currentRound] * slash;

        // pot calc
        uint256 discountOnPot = totalPotforRound[currentRound] * highestBidforRound[currentRound];
        discountOnPot /= 100;
        feesOnPotforRound[currentRound]  = totalPotforRound[currentRound] * feePercent;
        feesOnPotforRound[currentRound] /= 100;

        winningPotforRound[currentRound] = totalPotforRound[currentRound] - (discountOnPot + feesOnPotforRound[currentRound]);

        // slash calc
        uint256 discountOnSlash = totalSlashforRound[currentRound] * highestBidforRound[currentRound];
        discountOnSlash /= 100;
        feesOnSlashforRound[currentRound]  = totalSlashforRound[currentRound] * feePercent;
        feesOnSlashforRound[currentRound] /= 100;

        winningSlashforRound[currentRound] = totalSlashforRound[currentRound] - (discountOnSlash + feesOnSlashforRound[currentRound]);

        // DIVIDEND Calcl
        // pot
        dividendAmountforRound[currentRound] = discountOnPot / slots;
        // collateral-slash
        collateralDividendforRound[currentRound] = discountOnSlash / slots;

        // collateral gain/yield uppdate userCollateral
        collateralGains(collateralDividendforRound[currentRound]);
    }
    // rng for rafflelist
    function rngROSC(uint256 _randomWordlength) internal view onlyAdmin returns(uint256) {
        require(_randomWordlength > 0, "Length must be greater than 0");
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % _randomWordlength;
    }
    // winner selection
    function winnerWinner() external onlyAdmin {
        // no bids
        if(highestBidforRound[currentRound] == 0) {
            for(uint256 i=0; i < Users.length; i++){
                if(!hasWon[Users[i]]){
                    Rafflelist.push(Users[i]);
                }
            }
            uint256 randomWordlength = Rafflelist.length;

            if (randomWordlength == 1) {
                winnerforRound[currentRound] = Rafflelist[0];

                hasWon[winnerforRound[currentRound]] = true;

            } else {
                uint256 indexOfWinner = rngROSC(randomWordlength);
                winnerforRound[currentRound] = Rafflelist[indexOfWinner];

                hasWon[winnerforRound[currentRound]] = true;
            }
        } else {
            winnerforRound[currentRound] = highestBidderforRound[currentRound];

            hasWon[winnerforRound[currentRound]] = true;
        }
    }
    // 
    // winner pot withdrawals
    function winnerWithdraw() external {
        require(!potWithdrawnforRound[currentRound], "Pot already withdrawn");
        require(msg.sender == winnerforRound[currentRound], "You are not the winner for this round!");
        // Pot collected
        uint256 winningPot = winningPotforRound[currentRound];
        uint256 tokenBalance = erc20FiatContract.balanceOf(address(this));
        if (tokenBalance >= winningPot) {
            require(erc20FiatContract.transfer(msg.sender, winningPot), "Token transfer failed");
        }
        // Collateral slashed
        uint256 winningSlash = winningSlashforRound[currentRound];
        uint256 etherBalance = address(this).balance;
        if (etherBalance >= winningSlash){
            payable(msg.sender).transfer(winningSlash);
        }

        potWithdrawnforRound[currentRound] = true;
    }
    // protocol fees withdrawals
    function protocolFeesWithdraw() external onlyAdmin{
        require(!feesWithdrawnforRound[currentRound], "Fees already withdrawn");
        // fees on pot
        uint256 potFee = feesOnPotforRound[currentRound];
        uint256 tokenBalance = erc20FiatContract.balanceOf(address(this));
        if (tokenBalance >= potFee) {
            require(erc20FiatContract.transfer(admin, potFee), "Token transfer failed");
        }
        // fees on slash
        uint256 slashFee = feesOnSlashforRound[currentRound];
        uint256 etherBalance = address(this).balance;
        if (etherBalance >= slashFee){
            payable(admin).transfer(slashFee);
        }

        feesWithdrawnforRound[currentRound] = true;
    }
    // free collateral withdrawal
    function withdrawUnlockedCollateral() external{
        require(isUser[msg.sender], "Only members can w/d their collateral");
        require(currentRound >= 1, "You cannot withdraw before the ROSC start");
        require(!payBidWindow, "You cannot withdraw before pay/bid deadline");
        uint256 minCollateral = (slots - currentRound) * slash;
        require(userCollateral[msg.sender] > minCollateral, "You do not have enough unlocks to withdraw!!");
        uint256 maxWithdraw = userCollateral[msg.sender] - minCollateral;
        payable(msg.sender).transfer(maxWithdraw);

        userCollateral[msg.sender] = minCollateral;
    }
    // Updated admin withdrawal function
    function adminWithdrawAll() external onlyAdmin {
        // Withdraw all Ether
        uint256 etherBalance = address(this).balance;
        if (etherBalance > 0) {
            payable(admin).transfer(etherBalance);
        }

        // Withdraw all ERC20 tokens
        uint256 tokenBalance = erc20FiatContract.balanceOf(address(this));
        if (tokenBalance > 0) {
            require(erc20FiatContract.transfer(admin, tokenBalance), "Token transfer failed");
        }
    }

    function endFund() external onlyAdmin activeFund{
        // reset all the variables that has to be reused
        for(uint i = 0; i < Users.length; i++){
            address userX = Users[i];
            isUser[userX] = false;
            userCollateral[userX] = 0;
            userDeposits[userX] = 0;
            hasWon[userX] = false;
            for(uint j = 0; j < slots; j++){
                hasPaidRound[j][userX] = false;
                hasBidRound[j][userX] = false;
                userBidforRound[j][userX] = 0;
            }
        }
        delete Users;
        fundStatus = false;
    }
}