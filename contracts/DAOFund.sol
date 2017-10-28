pragma solidity ^0.4.15;

import './IDAOToken.sol';
import './IDAOVault.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';


/// @title ICO fund controlled by the investors
contract DAOFund {
    using SafeMath for uint256;

    enum ApprovalState {
        NotVoted,
        Approval,
        Disapproval
    }

    // Decision point description for the DAO
    struct KeyPoint {
        // duration of the period which is evaluated at this point
        uint duration;

        // funds share percent to be transfered to the project at this keypoint
        uint fundsShare;
    }

    // Dynamic state of a KeyPoint
    struct KeyPointState {
        bool processed;

        // true iff decision was made to further finance the project
        bool success;

        uint votingEndTime;

        uint approvalVotes;
        uint disapprovalVotes;
        mapping(address => ApprovalState) approvalState;
    }


    // event fired when the DAO comes to conclusion about a KeyPoint
    event KeyPointResolved(uint keyPointIndex, bool success);


    // lazy initialization
    modifier initialized {
        if (0 == m_keyPointState.length) {
            // first tranche after the ICO
            m_keyPointState.push(createKeyPointState(getTime()));
            m_keyPointState[0].processed = true;
            m_keyPointState[0].success = true;
            KeyPointResolved(0, true);
            m_vault.transferToTeam(getCurrentKeyPoint().fundsShare);
            initNextKeyPoint();

            assert(isActive());
        }
        _;
    }

    modifier onlyActive {
        require(isActive());
        _;
    }

    modifier onlyRefunding {
        require(isRefunding());
        _;
    }

    modifier onlyFinished {
        require(isFinished());
        _;
    }

    modifier onlyTokenHolder {
        require(m_token.balanceOf(msg.sender) > 0);
        _;
    }

    modifier onlyToken {
        require(msg.sender == address(m_token));
        _;
    }


    // PUBLIC interface

    function DAOFund(IDAOVault vault, IDAOToken token, uint approveMarginPercent){
        m_vault = vault;
        m_token = token;
        require(approveMarginPercent <= 100);
        m_approveMarginPercent = approveMarginPercent;

        m_keyPoints.push(KeyPoint({duration: 0 weeks, fundsShare: 25}));
        m_keyPoints.push(KeyPoint({duration: 40 weeks, fundsShare: 45}));
        m_keyPoints.push(KeyPoint({duration: 20 weeks, fundsShare: 30}));

        validateKeyPoints();
    }

    function approveKeyPoint(bool approval)
        external
        initialized
        onlyActive
        onlyTokenHolder
    {
        KeyPointState storage state = getCurrentKeyPointState();
        require(getTime() < state.votingEndTime);
        require(state.approvalState[msg.sender] == ApprovalState.NotVoted);

        state.approvalState[msg.sender] = approval ? ApprovalState.Approval : ApprovalState.Disapproval;
        addVotingTokens(msg.sender, m_token.balanceOf(msg.sender));
    }

    function executeKeyPoint()
        external
        initialized
        onlyActive
    {
        KeyPointState storage state = getCurrentKeyPointState();
        assert(!state.processed);
        require(getTime() >= state.votingEndTime);

        state.processed = true;
        state.success = isKeyPointApproved();
        KeyPointResolved(m_keyPointState.length - 1, state.success);
        if (state.success) {
            m_vault.transferToTeam(getCurrentKeyPoint().fundsShare);
            if (m_keyPointState.length < m_keyPoints.length)
                initNextKeyPoint();
        }
    }

    function refund()
        external
        initialized
        onlyRefunding
        onlyTokenHolder
    {
        uint numerator = m_token.balanceOf(msg.sender);
        uint denominator = m_token.totalSupply();
        assert(numerator <= denominator);

        m_token.burnFrom(msg.sender, m_token.balanceOf(msg.sender));
        m_vault.refund(msg.sender, numerator, denominator);
    }

    function onTokenTransfer(address from, address to, uint amount)
        external
        initialized
        onlyToken
    {
        if (!isActive())
            return;

        subVotingTokens(from, amount);
        addVotingTokens(to, amount);
    }

    function init() external initialized {}


    // INTERNALS: fund state

    function isActive() private constant returns (bool) {
        return !isFinished() && !isRefunding();
    }

    function isRefunding() private constant returns (bool) {
        assert(m_keyPoints.length >= m_keyPointState.length);
        return getCurrentKeyPointState().processed && !getCurrentKeyPointState().success;
    }

    function isFinished() private constant returns (bool) {
        assert(m_keyPoints.length >= m_keyPointState.length);
        return m_keyPoints.length == m_keyPointState.length
                && getCurrentKeyPointState().processed && getCurrentKeyPointState().success;
    }


    // INTERNALS: keypoints

    function validateKeyPoints() private constant {
        assert(m_keyPoints.length > 1);
        assert(0 == m_keyPoints[0].duration);   // initial tranche happens immediately
        uint fundsTotal;
        for (uint i = 0; i < m_keyPoints.length; i++) {
            KeyPoint storage keyPoint = m_keyPoints[i];

            assert(keyPoint.duration >= 1 weeks);
            fundsTotal = fundsTotal.add(keyPoint.fundsShare);
        }
        assert(100 == fundsTotal);
    }

    function initNextKeyPoint() private {
        assert(m_keyPoints.length > m_keyPointState.length);

        KeyPoint storage keyPoint = m_keyPoints[m_keyPointState.length];
        m_keyPointState.push(createKeyPointState(getTime() + keyPoint.duration));
    }

    function getCurrentKeyPoint() private constant returns (KeyPoint storage) {
        return m_keyPoints[m_keyPointState.length - 1];
    }

    function getCurrentKeyPointState() private constant returns (KeyPointState storage) {
        return m_keyPointState[m_keyPointState.length - 1];
    }

    function createKeyPointState(uint votingEndTime) private constant returns (KeyPointState memory) {
        return KeyPointState({processed: false, success: false,
                votingEndTime: votingEndTime, approvalVotes: 0, disapprovalVotes: 0});
    }


    // INTERNALS

    function addVotingTokens(address tokenOwner, uint amount) private {
        KeyPointState storage state = getCurrentKeyPointState();
        ApprovalState vote = state.approvalState[tokenOwner];
        if (vote == ApprovalState.Approval) {
            state.approvalVotes = state.approvalVotes.add(amount);
        } else if (vote == ApprovalState.Disapproval) {
            state.disapprovalVotes = state.disapprovalVotes.add(amount);
        }
    }

    function subVotingTokens(address tokenOwner, uint amount) private {
        KeyPointState storage state = getCurrentKeyPointState();
        ApprovalState vote = state.approvalState[tokenOwner];
        if (vote == ApprovalState.Approval) {
            state.approvalVotes = state.approvalVotes.sub(amount);
        } else if (vote == ApprovalState.Disapproval) {
            state.disapprovalVotes = state.disapprovalVotes.sub(amount);
        }
    }


    function isKeyPointApproved() private constant returns (bool) {
        KeyPointState storage state = getCurrentKeyPointState();
        uint totalVotes = state.approvalVotes.add(state.disapprovalVotes);
        if (0 == totalVotes)
            return true;

        return state.approvalVotes > state.disapprovalVotes.add(totalVotes.mul(m_approveMarginPercent).div(100));
    }

    function getTime() internal constant returns (uint) {
        return now;
    }


    // FIELDS

    IDAOVault public m_vault;
    IDAOToken public m_token;
    uint public m_approveMarginPercent;

    KeyPoint[] public m_keyPoints;
    KeyPointState[] public m_keyPointState;
}
