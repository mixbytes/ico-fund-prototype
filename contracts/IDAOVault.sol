pragma solidity ^0.4.15;


/// @title Interface of funds storage in a DAOFund
contract IDAOVault {
    /// @notice transfer specified percent to the project team
    /// @param fundsShare percent of collected funds to transfer
    function transferToTeam(uint fundsShare);

    /// @notice send some funds to investor in case of failed project
    /// @param to investor's address
    /// @param numerator numerator in the investor's token share
    /// @param denominator denominator in the investor's token share
    function refund(address to, uint numerator, uint denominator);
}
