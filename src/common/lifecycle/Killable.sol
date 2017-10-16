pragma solidity ^0.4.15;

import "/src/common/ownership/Ownable.sol";

/** 
 * @title Killable DAOPlayMarketTokenCrowdsale contract
 */
contract Killable is Ownable {
  function kill() onlyOwner {
    selfdestruct(owner);
  }
}
