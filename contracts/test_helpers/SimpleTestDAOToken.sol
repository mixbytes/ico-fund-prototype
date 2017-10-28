pragma solidity ^0.4.15;

import '../IDAOToken.sol';
import 'zeppelin-solidity/contracts/token/MintableToken.sol';


/// @title Test-only token, DO NOT use in production
contract SimpleTestDAOToken is IDAOToken, MintableToken {

    modifier onlyFund {
        require(msg.sender == address(m_fund));
        _;
    }

    function activate(IDAOFund fund) onlyOwner {
        assert(address(m_fund) == address(0));
        m_fund = fund;

        // making token completely automatic
        finishMinting();
        owner = address(0);
    }

    function burnFrom(address from, uint256 value) onlyFund {
        require(balanceOf(from) >= value);

        balances[from] = balances[from].sub(value);
        totalSupply = totalSupply.sub(value);
        Transfer(from, this, value);
    }

    function transfer(address _to, uint256 _value) returns (bool) {
        m_fund.onTokenTransfer(msg.sender, _to, _value);
        return super.transfer(_to, _value);
    }

    function transferFrom(address _from, address _to, uint256 _value) returns (bool) {
        m_fund.onTokenTransfer(_from, _to, _value);
        return super.transferFrom(_from, _to, _value);
    }

    IDAOFund public m_fund;
}
