pragma solidity ^0.4.15;

import '/src/common/ownership/Ownable.sol';
import '/src/common/SafeMath.sol';

/**
 * @title Price 
 */
contract Price is Ownable, SafeMath {
  
  struct Stage {
      // UNIX timestamp when the stage begins
      uint start;
      // UNIX timestamp when the stage is over
      uint end;
	  // Number of period
	  uint period;
  }
  
  /* Sale */
  uint[][] public stageSale;
  uint public startDate;
  uint public periodStage;
  Stage[] public stages;
  
  /* Crowdsale Agent */
  address public crowdsaleAgent;
  
  /**
   * @dev The function can be called only by crowdsale agent.
   */
  modifier onlyCrowdsaleAgent() {
    assert(msg.sender == crowdsaleAgent);
    _;
  }
   
  /**
   * @dev Set the contract that can call setBasePrice.
   * @param _crowdsaleAgent crowdsale contract address
   */
  function setCrowdsaleAgent(address _crowdsaleAgent) public onlyOwner {
	crowdsaleAgent = _crowdsaleAgent;
  }
  
  /**
   * @dev Allow to (re)set base price
   */
  function setBasePrice(uint[] _stageSale, uint _startDate, uint _periodStage) public onlyOwner {
   uint j = 0;
   for(uint i=0; i<_stageSale.length/5; i++) {
      stageSale[i][0] = _stageSale[0+j];
	  stageSale[i][1] = _stageSale[1+j];
	  stageSale[i][2] = _stageSale[2+j];
	  stageSale[i][3] = _stageSale[3+j];
	  stageSale[i][4] = _stageSale[4+j];
	  j=j+5;
    }
	startDate = _startDate;
	periodStage = _periodStage*1 days;
	delete stages;
	for(i=0; i<5; i++) {
		stages.push(Stage(startDate+i*periodStage,startDate+(i+1)*periodStage,i));
	}
  }
  
  function getStageForCap(uint tokensSold, uint CAP) public constant  returns (uint) {
	uint stageCap = div(CAP,5);
	if(tokensSold < stageCap){
	  return 0;
	}else if (tokensSold < mul(2,stageCap)){
	  return 1;
	}else if (tokensSold < mul(3,stageCap)){
	  return 2;
	}else if (tokensSold < mul(4,stageCap)){
	  return 3;
	}else {
	  return 4;
	}
  }
  
  function getStageForNum(uint num, uint CAP) public constant returns (uint) {
	uint stageCap = div(CAP,5);
	if(num == 0){
	  return stageCap;
	}else if (num == 1){
	  return mul(2,stageCap);
	}else if (num == 2){
	  return mul(3,stageCap);
	}else if (num == 3){
	  return mul(4,stageCap);
	}else {
	  return mul(5,stageCap);
	}
  }
  function setStage(uint number) private onlyCrowdsaleAgent {
    uint time = block.timestamp;
	uint j = 0;
	stages[number-1].end = block.timestamp;
	for (uint i = number; i < stages.length; i++) {
      stages[i].start = time+periodStage*j;
	  stages[i].end = time+periodStage*(j+1);
	  j++;
    }
  }
  
  
  function getStage() public constant returns (uint){
    for (uint i = 0; i < stages.length; i++) {
      if (block.timestamp >= stages[i].start && block.timestamp < stages[i].end) {
        return stages[i].period;
      }
    }
  }
  
 
  function getAmountCap(uint value) public constant returns (uint ) {

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
   *
   *
   * @param value - What is the value of the transaction send in as wei
   * @param tokensSold - how much tokens have been sold this far
   * @param decimals - how many decimal units the token has
   * @return Amount of tokens the investor receives
   */
   
  function calculateToken(uint value, uint tokensSold, uint decimals, uint CAP) public constant returns (uint){
	
	uint tokenAmount = 0;
	uint saleStageCap = 0;
	uint saleAmountCap = 0;
	
	uint salePrice = 0;
	uint _value = 0;
	uint tokenAmontCap = 0;
	uint _tokensSold = 0;
	uint _cap = 0;
	uint finalCAP = CAP;
	uint _period = getStage();
	
	saleAmountCap = getAmountCap(value);
	saleStageCap = getStageForCap(tokensSold,CAP);
	saleStageCap = max (saleStageCap,_period);
	
	salePrice = stageSale[saleAmountCap][saleStageCap];
	_value = value*10**decimals;
	tokenAmount = div(_value,salePrice);
	
	_tokensSold = tokensSold;
	
	while(tokenAmount!=0){
	  _cap = getStageForNum(saleStageCap,CAP);
	  if(add(tokenAmount,_tokensSold)>=_cap){
	    if(saleStageCap == 4){
	      assert(add(tokenAmount,_tokensSold) <= finalCAP);
	    }
		//сдвинуть период
		setStage(saleStageCap+1);
		tokenAmontCap = add(tokenAmontCap, sub(_cap,_tokensSold));
		_value = sub(_value,mul(sub(_cap,_tokensSold),salePrice));
		saleStageCap = getStageForCap(_cap,CAP);
	    salePrice = stageSale[saleAmountCap][saleStageCap];
		tokenAmount = div(_value,salePrice);
		_tokensSold = _cap;
	  }else{
	    tokenAmontCap =add(tokenAmontCap,tokenAmount);
		tokenAmount = 0;
	  }
	}
	return tokenAmontCap;
  }
}
