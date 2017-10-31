pragma solidity ^0.4.15;

import '../IDAOToken.sol';
import '../IDAOVault.sol';
import '../DAOFund.sol';


/// @title Test helper for DAOFund, DO NOT use it in production!
contract DAOFundTestHelper is DAOFund {

    function DAOFundTestHelper(IDAOVault vault, IDAOToken token, uint approveMarginPercent)
        DAOFund(vault, token, approveMarginPercent)
    {
    }

    function getVotes() public constant returns (uint approvalVotes, uint disapprovalVotes) {
        approvalVotes = getCurrentKeyPointState().approvalVotes;
        disapprovalVotes = getCurrentKeyPointState().disapprovalVotes;
    }

    function getTime() internal constant returns (uint) {
        return m_time;
    }

    function setTime(uint time) external {
        m_time = time;
    }

    uint m_time;
}
