pragma solidity ^0.4.15;

import '/src/common/ownership/Ownable.sol';
import '/src/common/token/ERC20.sol';
import '/src/common/SafeMath.sol';

/**
 * @title Standard ERC20 token
 * @dev Implementation of the basic standard token.
 * @dev https://github.com/ethereum/EIPs/issues/20
 * @dev Based on code by FirstBlood: https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
 */
contract StandardToken is ERC20, SafeMath, Ownable{
	
  uint256 _totalSupply;
  mapping (address => uint256) balances;
  mapping (address => mapping (address => uint256)) approvals;
  address public crowdsaleAgent;
  bool public released = false;  
  
  /**
   * @dev Fix for the ERC20 short address attack http://vessenes.com/the-erc20-short-address-attack-explained/
   * @param numwords payload size  
   */
  modifier onlyPayloadSize(uint numwords) {
    assert(msg.data.length == numwords * 32 + 4);
    _;
  }
  
  /**
   * @dev The function can be called only by crowdsale agent.
   */
  modifier onlyCrowdsaleAgent() {
    assert(msg.sender == crowdsaleAgent);
    _;
  }

  /** Limit token mint after finishing crowdsale
   * @dev Make sure we are not done yet.
   */
  modifier canMint() {
    assert(!released);
    _;
  }
  
  /**
   * @dev Limit token transfer until the crowdsale is over.
   */
  modifier canTransfer() {
    assert(released);
    _;
  } 
  
  /** 
   * @dev Total Supply
   * @return _totalSupply 
   */  
  function totalSupply() public constant returns (uint256) {
    return _totalSupply;
  }
  
  /** 
   * @dev Tokens balance
   * @param _owner holder address
   * @return balance amount 
   */
  function balanceOf(address _owner) public constant returns (uint256) {
    return balances[_owner];
  }
  
  /** 
   * @dev Token allowance
   * @param _owner holder address
   * @param _spender spender address
   * @return remain amount
   */   
  function allowance(address _owner, address _spender) public constant returns (uint256) {
    return approvals[_owner][_spender];
  }

  /** 
   * @dev Tranfer tokens to address
   * @param _to dest address
   * @param _value tokens amount
   * @return transfer result
   */   
  function transfer(address _to, uint _value) public canTransfer onlyPayloadSize(2) returns (bool success) {
    assert(balances[msg.sender] >= _value);
    balances[msg.sender] = sub(balances[msg.sender], _value);
    balances[_to] = add(balances[_to], _value);
    
    Transfer(msg.sender, _to, _value);
    return true;
  }
  
  /**    
   * @dev Tranfer tokens from one address to other
   * @param _from source address
   * @param _to dest address
   * @param _value tokens amount
   * @return transfer result
   */    
  function transferFrom(address _from, address _to, uint _value) public canTransfer onlyPayloadSize(3) returns (bool success) {
    assert(balances[_from] >= _value);
    assert(approvals[_from][msg.sender] >= _value);
    approvals[_from][msg.sender] = sub(approvals[_from][msg.sender], _value);
    balances[_from] = sub(balances[_from], _value);
    balances[_to] = add(balances[_to], _value);
    
    Transfer(_from, _to, _value);
    return true;
  }
  
  /** 
   * @dev Approve transfer
   * @param _spender holder address
   * @param _value tokens amount
   * @return result  
   */
  function approve(address _spender, uint _value) public onlyPayloadSize(2) returns (bool success) {
    // To change the approve amount you first have to reduce the addresses`
    //  approvals to zero by calling `approve(_spender, 0)` if it is not
    //  already 0 to mitigate the race condition described here:
    //  https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    assert((_value == 0) || (approvals[msg.sender][_spender] == 0));
    approvals[msg.sender][_spender] = _value;
    
    Approval(msg.sender, _spender, _value);
    return true;
  }
  
  /** 
   * @dev Create new tokens and allocate them to an address. Only callably by a crowdsale contract
   * @param _to dest address
   * @param _value tokens amount
   * @return mint result
   */ 
  function mint(address _to, uint _value) public onlyCrowdsaleAgent canMint onlyPayloadSize(2) returns (bool success) {
    _totalSupply = add(_totalSupply, _value);
    balances[_to] = add(balances[_to], _value);
    
    Transfer(0, _to, _value);
    return true;
  }
  
  /**
   * @dev Set the contract that can call release and make the token transferable.
   * @param _crowdsaleAgent crowdsale contract address
   */
  function setCrowdsaleAgent(address _crowdsaleAgent) public onlyOwner {
    assert(!released);
    crowdsaleAgent = _crowdsaleAgent;
  }
  
  /**
   * @dev One way function to release the tokens to the wild. Can be called only from the release agent that is the final ICO contract. 
   */
  function releaseTokenTransfer() public onlyCrowdsaleAgent {
    released = true;
  }
}


/** 
 * @title DAOPlayMarket2.0 contract - standard ERC20 token with Short Hand Attack and approve() race condition mitigation.
 */
contract DAOPlayMarketToken is StandardToken {
  
  string public name;
  string public symbol;
  uint public decimals;
  
  /** Name and symbol were updated. */
  event UpdatedTokenInformation(string newName, string newSymbol);

  /**
   * Construct the token.
   *
   * This token must be created through a team multisig wallet, so that it is owned by that wallet.
   *
   * @param _name Token name
   * @param _symbol Token symbol - should be all caps
   * @param _initialSupply How many tokens we start with
   * @param _decimals Number of decimal places
   */
   
  function DAOPlayMarketToken(string _name, string _symbol, uint _initialSupply, uint _decimals) public {
    name = _name;
    symbol = _symbol;
    decimals = _decimals;
	
    _totalSupply = _initialSupply*10**_decimals;

    // Create initially all balance on the team multisig
    balances[msg.sender] = _totalSupply;
  }   
  
   /**
   * Owner can update token information here.
   *
   * It is often useful to conceal the actual token association, until
   * the token operations, like central issuance or reissuance have been completed.
   *
   * This function allows the token owner to rename the token after the operations
   * have been completed and then point the audience to use the token contract.
   */
  function setTokenInformation(string _name, string _symbol) public onlyOwner {
    name = _name;
    symbol = _symbol;

    UpdatedTokenInformation(name, symbol);
  }

}
