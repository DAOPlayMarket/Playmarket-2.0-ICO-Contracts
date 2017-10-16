pragma solidity ^0.4.15;

/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 {
  function totalSupply() public constant returns (uint);
  function balanceOf(address owner) public constant returns (uint);
  function allowance(address owner, address spender) public constant returns (uint);
  function transfer(address to, uint value) public returns (bool success);
  function transferFrom(address from, address to, uint value) public returns (bool success);
  function approve(address spender, uint value) public returns (bool success);
  function mint(address to, uint value) public returns (bool success);
  event Transfer(address indexed from, address indexed to, uint value);
  event Approval(address indexed owner, address indexed spender, uint value);
}
