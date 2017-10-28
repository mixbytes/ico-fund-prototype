pragma solidity ^0.4.15;

import '../IDAOVault.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';


/// @title Test-only vault, DO NOT use in production
contract SimpleTestDAOVault is IDAOVault, Ownable {
    using SafeMath for uint256;

    modifier onlyFund {
        require(msg.sender == m_fund);
        _;
    }


    function SimpleTestDAOVault(address team) {
        m_team = team;
    }

    function() payable {
        require(!isActive());
    }


    function activate(address fund) onlyOwner {
        assert(!isActive());
        m_fund = fund;

        m_weiInitial = this.balance;

        // making vault completely automatic
        owner = address(0);

        assert(isActive());
    }

    function transferToTeam(uint fundsShare) onlyFund {
        m_team.transfer(m_weiInitial.mul(fundsShare).div(100));
    }

    function refund(address to, uint numerator, uint denominator) onlyFund {
        to.transfer(this.balance.mul(numerator).div(denominator));
    }


    function isActive() private constant returns (bool) {
        return m_fund != address(0);
    }


    address public m_team;
    address public m_fund;

    uint public m_weiInitial;
}
