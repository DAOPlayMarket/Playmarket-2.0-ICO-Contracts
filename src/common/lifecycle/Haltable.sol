pragma solidity ^0.4.15;

import "/src/common/ownership/Ownable.sol";

/**
 * @title Haltable
 * @dev Abstract contract that allows children to implement an
 * emergency stop mechanism. Differs from Pausable by causing a throw when in halt mode.
 */
contract Haltable is Ownable {
  bool public halted;

  modifier stopInEmergency {
    assert(!halted);
    _;
  }

  modifier onlyInEmergency {
    assert(halted);
    _;
  }

  /**
   *@dev Called by the owner on emergency, triggers stopped state
   */
  function halt() external onlyOwner {
    halted = true;
  }

  /**
   * @dev Called by the owner on end of emergency, returns to normal state
   */
  function unhalt() external onlyOwner onlyInEmergency {
    halted = false;
  }
}
