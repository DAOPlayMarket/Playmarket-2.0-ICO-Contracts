pragma solidity ^0.4.15;

import '/src/common/SafeMath.sol';
import '/src/common/lifecycle/Haltable.sol';
import '/src/common/lifecycle/Killable.sol';
import '/src/ico/DAOPMTTOKEN.sol';

/** 
 * @title DAOPlayMarketTokenCrowdsale contract - contract for token sales.
 */
contract DAOPlayMarketTokenCrowdsale is Haltable, SafeMath, Killable {
  
  /* The token we are selling */
  DAOPlayMarketToken public token;

  /* tokens will be transfered from this address */
  address public multisigWallet;

  /* the UNIX timestamp start date of the crowdsale */
  uint public startsAt;
  
  /* the UNIX timestamp end date of the crowdsale */
  uint public endsAt;
  
  /* the number of tokens already sold through this contract*/
  uint public tokensSold = 0;
  
  /* How many wei of funding we have raised */
  uint public weiRaised = 0;
  
  /* How many unique addresses that have invested */
  uint public investorCount = 0;
  
  /* Has this crowdsale been finalized */
  bool public finalized;
  
  /* Cap of tokens */
  uint public CAP;
  
  /* How much ETH each address has invested to this crowdsale */
  mapping (address => uint256) public investedAmountOf;
  
  /* How much tokens this crowdsale has credited for each investor address */
  mapping (address => uint256) public tokenAmountOf;
  
  /* Contract address that can call invest other crypto */
  address public cryptoAgent;
  
  /** How many tokens he charged for each investor's address in a particular period */
  mapping (uint => mapping (address => uint256)) public tokenAmountOfPeriod;
  
  struct Stage {
    // UNIX timestamp when the stage begins
    uint start;
    // UNIX timestamp when the stage is over
    uint end;
    // Number of period
    uint period;
    // Price#1 token in WEI
    uint price1;
    // Price#2 token in WEI
    uint price2;
    // Price#3 token in WEI
    uint price3;
    // Cap of period
    uint cap;
    // Token sold in period
    uint tokenSold;
  }
  
  /** Stages **/
  Stage[] public stages;
  uint public periodStage;
  uint public stage;
  
  /** State machine
   *
   * - Preparing: All contract initialization calls and variables have not been set yet
   * - Funding: Active crowdsale
   * - Success: Minimum funding goal reached
   * - Failure: Minimum funding goal not reached before ending time
   * - Finalized: The finalized has been called and succesfully executed
   */
  enum State{Unknown, Preparing, Funding, Success, Failure, Finalized}
  
  // A new investment was made
  event Invested(address investor, uint weiAmount, uint tokenAmount);
  
  // A new investment was made
  event InvestedOtherCrypto(address investor, uint weiAmount, uint tokenAmount);

  // Crowdsale end time has been changed
  event EndsAtChanged(uint _endsAt);
  
  // New distributions were made
  event DistributedTokens(address investor, uint tokenAmount);
  
  /** 
   * @dev Modified allowing execution only if the crowdsale is currently running
   */
  modifier inState(State state) {
    require(getState() == state);
    _;
  }
  
  /**
   * @dev The function can be called only by crowdsale agent.
   */
  modifier onlyCryptoAgent() {
    assert(msg.sender == cryptoAgent);
    _;
  }
  
  /**
   * @dev Constructor
   * @param _token DAOPlayMarketToken token address
   * @param _multisigWallet team wallet
   * @param _start token ICO start date
   * @param _cap token ICO 
   * @param _price array of price 
   * @param _periodStage period of stage
   * @param _capPeriod cap of period
   */
  function DAOPlayMarketTokenCrowdsale(address _token, address _multisigWallet, uint _start, uint _cap, uint[15] _price, uint _periodStage, uint _capPeriod) public {
  
    require(_multisigWallet != 0x0);
    require(_start != 0);
    require(_cap > 0);
    require(_periodStage > 0);
    require(_capPeriod > 0);
	
    token = DAOPlayMarketToken(_token);
    multisigWallet = _multisigWallet;
    startsAt = _start;
    CAP = _cap*10**token.decimals();
	
    periodStage = _periodStage*1 days;
    uint capPeriod = _capPeriod*10**token.decimals();
    uint j = 0;
    for(uint i=0; i<_price.length; i=i+3) {
      stages.push(Stage(startsAt+j*periodStage, startsAt+(j+1)*periodStage, j, _price[i], _price[i+1], _price[i+2], capPeriod, 0));
      j++;
    }
    endsAt = stages[stages.length-1].end;
    stage = 0;
  }
  
  /**
   * Buy tokens from the contract
   */
  function() public payable {
    investInternal(msg.sender);
  }

  /**
   * Make an investment.
   *
   * Crowdsale must be running for one to invest.
   * We must have not pressed the emergency brake.
   *
   * @param receiver The Ethereum address who receives the tokens
   *
   */
  function investInternal(address receiver) private stopInEmergency {
    assert(getState() == State.Funding);

    // Determine in what period we hit
    stage = getStage();
	
    uint weiAmount = msg.value;

    // Account presale sales separately, so that they do not count against pricing tranches
    uint tokenAmount = calculateToken(weiAmount, stage, token.decimals());

    assert(tokenAmount > 0);

	// Check that we did not bust the cap in the period
    assert(stages[stage].cap >= add(tokenAmount, stages[stage].tokenSold));
	
    tokenAmountOfPeriod[stage][receiver]=add(tokenAmountOfPeriod[stage][receiver],tokenAmount);
	
    stages[stage].tokenSold = add(stages[stage].tokenSold,tokenAmount);
	
    if (stages[stage].cap == stages[stage].tokenSold){
      updateStage(stage);
      endsAt = stages[stages.length-1].end;
    }
	
	// Check that we did not bust the cap
    //assert(!isBreakingCap(tokenAmount, tokensSold));
	
    if(investedAmountOf[receiver] == 0) {
       // A new investor
       investorCount++;
    }

    // Update investor
    investedAmountOf[receiver] = add(investedAmountOf[receiver],weiAmount);
    tokenAmountOf[receiver] = add(tokenAmountOf[receiver],tokenAmount);

    // Update totals
    weiRaised = add(weiRaised,weiAmount);
    tokensSold = add(tokensSold,tokenAmount);

    assignTokens(receiver, tokenAmount);

    // send ether to the fund collection wallet
    multisigWallet.transfer(weiAmount);

    // Tell us invest was success
    Invested(receiver, weiAmount, tokenAmount);
	
  }
  
  /**
   * Make an investment.
   *
   * Crowdsale must be running for one to invest.
   * We must have not pressed the emergency brake.
   *
   * @param receiver The Ethereum address who receives the tokens
   * @param _weiAmount amount in Eth
   *
   */
  function investOtherCrypto(address receiver, uint _weiAmount) public onlyCryptoAgent stopInEmergency {
    assert(getState() == State.Funding);

    // Determine in what period we hit
    stage = getStage();
	
    uint weiAmount = _weiAmount;

    // Account presale sales separately, so that they do not count against pricing tranches
    uint tokenAmount = calculateToken(weiAmount, stage, token.decimals());

    assert(tokenAmount > 0);

	// Check that we did not bust the cap in the period
    assert(stages[stage].cap >= add(tokenAmount, stages[stage].tokenSold));
	
    tokenAmountOfPeriod[stage][receiver]=add(tokenAmountOfPeriod[stage][receiver],tokenAmount);
	
    stages[stage].tokenSold = add(stages[stage].tokenSold,tokenAmount);
	
    if (stages[stage].cap == stages[stage].tokenSold){
      updateStage(stage);
      endsAt = stages[stages.length-1].end;
    }
	
	// Check that we did not bust the cap
    //assert(!isBreakingCap(tokenAmount, tokensSold));
	
    if(investedAmountOf[receiver] == 0) {
       // A new investor
       investorCount++;
    }

    // Update investor
    investedAmountOf[receiver] = add(investedAmountOf[receiver],weiAmount);
    tokenAmountOf[receiver] = add(tokenAmountOf[receiver],tokenAmount);

    // Update totals
    weiRaised = add(weiRaised,weiAmount);
    tokensSold = add(tokensSold,tokenAmount);

    assignTokens(receiver, tokenAmount);
	
    // Tell us invest was success
    InvestedOtherCrypto(receiver, weiAmount, tokenAmount);
  }
  
  /**
   * Create new tokens or transfer issued tokens to the investor depending on the cap model.
   */
  function assignTokens(address receiver, uint tokenAmount) private {
     token.mint(receiver, tokenAmount);
  }
   
  /**
   * Check if the current invested breaks our cap rules.
   *
   * Called from invest().
   *
   * @param tokenAmount The amount of tokens we try to give to the investor in the current transaction
   * @param tokensSoldTotal What would be our total sold tokens count after this transaction
   *
   * @return true if taking this investment would break our cap rules
   */
  function isBreakingCap(uint tokenAmount, uint tokensSoldTotal) public constant returns (bool limitBroken){
	if(add(tokenAmount,tokensSoldTotal) <= CAP){
	  return false;
	}
	return true;
  }

  /**
   * @dev Distribution of remaining tokens.
   */
  function distributionOfTokens() public {
    require(block.timestamp >= endsAt);
    require(!finalized);
    uint amount;
    for(uint i=0; i<stages.length; i++) {
      if(tokenAmountOfPeriod[stages[i].period][msg.sender] != 0){
        amount = add(amount,div(mul(sub(stages[i].cap,stages[i].tokenSold),tokenAmountOfPeriod[stages[i].period][msg.sender]),stages[i].tokenSold));
        tokenAmountOfPeriod[stages[i].period][msg.sender] = 0;
      }
    }
    assignTokens(msg.sender, amount);
	
    // Tell us distributed was success
    DistributedTokens(msg.sender, amount);
  }
  
  /**
   * @dev Finalize a succcesful crowdsale.
   */
  function finalize() public inState(State.Success) onlyOwner stopInEmergency {
    require(block.timestamp >= (endsA+periodStage));
    require(!finalized);
	
    finalizeCrowdsale();
    finalized = true;
  }
  
  /**
   * @dev Finalize a succcesful crowdsale.
   */
  function finalizeCrowdsale() internal {
    token.releaseTokenTransfer();
  }
  
  /**
   * @dev Check if the ICO goal was reached.
   * @return true if the crowdsale has raised enough money to be a success
   */
  function isCrowdsaleFull() public constant returns (bool) {
    if(tokensSold >= CAP || block.timestamp >= endsAt){
      return true;  
    }
    return false;
  }
  
  /** 
   * @dev Allow crowdsale owner to close early or extend the crowdsale.
   * @param time timestamp
   */
  function setEndsAt(uint time) public onlyOwner {
    require(!finalized);
    require(time >= block.timestamp);
    endsAt = time;
    EndsAtChanged(endsAt);
  }
  
   /**
   * @dev Allow to change the team multisig address in the case of emergency.
   */
  function setMultisig(address addr) public onlyOwner {
    require(addr != 0x0);
    multisigWallet = addr;
  }
  
  /**
   * @dev Allow crowdsale owner to change the token address.
   */
  function setToken(address addr) public onlyOwner {
    require(addr != 0x0);
    token = DAOPlayMarketToken(addr);
  }
  
  /** 
   * @dev Crowdfund state machine management.
   * @return State current state
   */
  function getState() public constant returns (State) {
    if (finalized) return State.Finalized;
    else if (address(token) == 0 || address(multisigWallet) == 0 || block.timestamp < startsAt) return State.Preparing;
    else if (block.timestamp <= endsAt && block.timestamp >= startsAt && !isCrowdsaleFull()) return State.Funding;
    else if (isCrowdsaleFull()) return State.Success;
    else return State.Failure;
  }
  
  /** 
   * @dev Set base price for ICO.
   */
  function setBasePrice(uint[15] _price, uint _startDate, uint _periodStage, uint _cap, uint _decimals) public onlyOwner {
    periodStage = _periodStage*1 days;
    uint cap = _cap*10**_decimals;
    uint j = 0;
    delete stages;
    for(uint i=0; i<_price.length; i=i+3) {
      stages.push(Stage(_startDate+j*periodStage, _startDate+(j+1)*periodStage, j, _price[i], _price[i+1], _price[i+2], cap, 0));
      j++;
    }
    endsAt = stages[stages.length-1].end;
    stage =0;
  }
  
  /** 
   * @dev Updates the ICO steps if the cap is reached.
   */
  function updateStage(uint number) private onlyOwner {
    require(number>=0);
    uint time = block.timestamp;
    uint j = 0;
    stages[number].end = time;
    for (uint i = number+1; i < stages.length; i++) {
      stages[i].start = time+periodStage*j;
      stages[i].end = time+periodStage*(j+1);
      j++;
    }
  }
  
  /** 
   * @dev Gets the current stage.
   * @return uint current stage
   */
  function getStage() private constant returns (uint){
    for (uint i = 0; i < stages.length; i++) {
      if (block.timestamp >= stages[i].start && block.timestamp < stages[i].end) {
        return stages[i].period;
      }
    }
    return stages[stages.length-1].period;
  }
  
  /** 
   * @dev Gets the cap of amount.
   * @return uint cap of amount
   */
  function getAmountCap(uint value) private constant returns (uint ) {
    if(value <= 10*10**18){
      return 0;
    }else if (value <= 50*10**18){
      return 1;
    }else {
      return 2;
    }
  }
  
  /**
   * When somebody tries to buy tokens for X eth, calculate how many tokens they get.
   * @param value - The value of the transaction send in as wei
   * @param _stage - The stage of ICO
   * @param decimals - How many decimal places the token has
   * @return Amount of tokens the investor receives
   */
   
  function calculateToken(uint value, uint _stage, uint decimals) private constant returns (uint){
    uint tokenAmount = 0;
    uint saleAmountCap = getAmountCap(value); 
	
    if(saleAmountCap == 0){
      tokenAmount = div(value*10**decimals,stages[_stage].price1);
    }else if(saleAmountCap == 1){
      tokenAmount = div(value*10**decimals,stages[_stage].price2);
    }else{
      tokenAmount = div(value*10**decimals,stages[_stage].price3);
    }
    return tokenAmount;
  }
 
  /**
   * @dev Set the contract that can call the invest other crypto function.
   * @param _cryptoAgent crowdsale contract address
   */
  function setCryptoAgent(address _cryptoAgent) public onlyOwner {
    require(!finalized);
    cryptoAgent = _cryptoAgent;
  }
}
