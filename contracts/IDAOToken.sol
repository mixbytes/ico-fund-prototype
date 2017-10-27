pragma solidity ^0.4.15;

import 'zeppelin-solidity/contracts/token/ERC20.sol';


/// @title Interface of token which represents rights in a DAOFund
contract IDAOToken is ERC20 {
    /// @notice called by the fund: burns the specified amount of investor's tokens
    /// @dev access check still has to be properly implemented!
    function burnFrom(address from, uint256 value) returns (bool);

    // on token transfers token must call DAOFund.onTokenTransfer(address from, address to, uint amount);
}
