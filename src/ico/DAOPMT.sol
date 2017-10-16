pragma solidity ^0.4.15;

import '/src/common/SafeMath.sol';
import '/src/common/lifecycle/Haltable.sol';
import '/src/common/lifecycle/Killable.sol';
import '/src/ico/DAOPMTPRICE.sol';
import '/src/ico/DAOPMTTOKEN.sol';

/** 
 * @title DAOPlayMarketTokenCrowdsale contract - contract for token sales.
 */
contract DAOPlayMarketTokenCrowdsale is Haltable, SafeMath, Killable {
  
  /* The token we are selling */
  DAOPlayMarketToken public token;
  
  /* How we are going to price our offering */
  Price public price;
  
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
  
  /* How many distinct addresses have invested */
  uint public investorCount = 0;
  
  /* Has this crowdsale been finalized */
  bool public finalized;
  
  /* CAP of tokens */
  uint public CAP;
  
  /** How much ETH each address has invested to this crowdsale */
  mapping (address => uint256) public investedAmountOf;
  
  /** How much tokens this crowdsale has credited for each investor address */
  mapping (address => uint256) public tokenAmountOf;
  
  /** This is for manul testing for the interaction from owner wallet. You can set it to any value and inspect this in blockchain explorer to see that crowdsale interaction works. */
  uint public ownerTestValue;
  
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
  
  /** 
   * @dev Modified allowing execution only if the crowdsale is currently running
   */
  modifier inState(State state) {
    require(getState() == state);
    _;
  }
  
  /**
   * @dev Constructor
   * @param _token DAOPlayMarketToken token address
   * @param _price Price token address
   * @param _multisigWallet team wallet
   * @param _start token ICO start date
   * @param _end token ICO end date
   * @param _cap token ICO 
   */
  function DAOPlayMarketTokenCrowdsale(address _token, Price _price, address _multisigWallet, uint _start, uint _end, uint _cap) public {
  
    assert(_multisigWallet != 0);
    assert(_start != 0);
	assert(_start < _end);
	assert(_cap > 0);
	
	token = DAOPlayMarketToken(_token);
	setPrice(_price);
	multisigWallet = _multisigWallet;
	startsAt = _start;
	endsAt = _end;
	CAP = _cap;

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

    uint weiAmount = msg.value;

    // Account presale sales separately, so that they do not count against pricing tranches
    uint tokenAmount = price.calculateToken(weiAmount, tokensSold, token.decimals(),CAP);

    assert(tokenAmount > 0);

	// Check that we did not bust the cap
    assert(!isBreakingCap(tokenAmount, tokensSold));
	
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

    // Pocket the money
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
  function investOtherCrypto(address receiver, uint _weiAmount) public onlyOwner stopInEmergency {
    assert(getState() == State.Funding);

    uint weiAmount = _weiAmount;

    // Account presale sales separately, so that they do not count against pricing tranches
    uint tokenAmount = price.calculateToken(weiAmount, tokensSold, token.decimals(),CAP);

    assert(tokenAmount > 0);

	// Check that we did not bust the cap
    assert(!isBreakingCap(tokenAmount, tokensSold));
	
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
   * @dev Allow to (re)set pricing strategy.
   */
  function setPrice(Price _price) public onlyOwner {
    price = _price;
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
   * @dev Finalize a succcesful crowdsale.
   */
  function finalize() public inState(State.Success) onlyOwner stopInEmergency {
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
    require(time >= block.timestamp);
    endsAt = time;
    EndsAtChanged(endsAt);
  }
  
   /**
   * Allow to change the team multisig address in the case of emergency.
   */
  function setMultisig(address addr) public onlyOwner {
    assert(addr != 0);
	multisigWallet = addr;
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
   * This is for manual testing of multisig wallet interaction 
   */
  function setOwnerTestValue(uint val) public onlyOwner {
    ownerTestValue = val;
  }
}
