pragma solidity ^0.4.15;

import './IDAOToken.sol';
import './IDAOVault.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';


/// @title ICO fund controlled by the investors
contract DAOFund {
    using SafeMath for uint256;

    // Vote state
    enum ApprovalState {
        // default
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
        // true iff appropriate actions were taken for the keypoint
        bool processed;

        // true iff decision was made to further finance the project
        bool success;

        // votes are no longer accepted at this time
        uint votingEndTime;

        // current amount of tokens supporting the next tranche to the project
        uint approvalVotes;

        // current amount of tokens supporting cancelation of the project
        uint disapprovalVotes;

        // votes of each investor
        mapping(address => ApprovalState) approvalState;

        // status of an investor as a delegate
        mapping(address => DelegateState) delegateState;

        // status of an investor as a delegator
        mapping(address => DelegatorState) delegatorState;
    }

    // State of investor to which voting was delegated
    struct DelegateState {
        // note: votesAccumulated is always up-to-date, even after voting
        uint votesAccumulated;
    }

    // State of investor which delegates voting to other
    struct DelegatorState {
        address delegate;
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


    modifier notVoted {
        require(getCurrentKeyPointState().approvalState[msg.sender] == ApprovalState.NotVoted);
        _;
    }

    modifier notDelegator {
        require(address(0) == getDelegatorState(msg.sender).delegate);
        _;
    }


    // PUBLIC interface

    function DAOFund(IDAOVault vault, IDAOToken token, uint approveMarginPercent){
        m_vault = vault;
        m_token = token;
        require(approveMarginPercent <= 100);

        // fund configuration
        // this configuration could be set in an inheriting contract

        m_approveMarginPercent = approveMarginPercent;

        m_keyPoints.push(KeyPoint({duration: 0 weeks, fundsShare: 25}));
        m_keyPoints.push(KeyPoint({duration: 40 weeks, fundsShare: 45}));
        m_keyPoints.push(KeyPoint({duration: 20 weeks, fundsShare: 30}));

        // end of fund configuration

        validateKeyPoints();
    }

    /// @notice approves of disapproves current keypoint
    function approveKeyPoint(bool approval)
        external
        initialized
        onlyActive
        onlyTokenHolder
        notVoted
        notDelegator
    {
        KeyPointState storage state = getCurrentKeyPointState();
        require(getTime() < state.votingEndTime);

        state.approvalState[msg.sender] = approval ? ApprovalState.Approval : ApprovalState.Disapproval;
        addVotingTokens(msg.sender, m_token.balanceOf(msg.sender).add(getDelegateState(msg.sender).votesAccumulated));
    }

    /// @notice delegates your vote to other investor
    function delegate(address to)
        external
        initialized
        onlyActive
        onlyTokenHolder
        notVoted
        notDelegator
    {
        require(m_token.balanceOf(to) > 0);

        // finding final delegate in the chain
        address delegate = getDelegate(to);
        // breaking loops
        require(delegate != msg.sender);

        // transfer accumulated
        DelegateState storage senderDelegateState = getDelegateState(msg.sender);
        uint senderTotalVotes = senderDelegateState.votesAccumulated.add(m_token.balanceOf(msg.sender));
        senderDelegateState.votesAccumulated = 0;

        getDelegateState(delegate).votesAccumulated = getDelegateState(delegate).votesAccumulated.add(senderTotalVotes);
        addVotingTokens(delegate, senderTotalVotes);

        // mark sender as a delegator
        getDelegatorState(msg.sender).delegate = delegate;
    }

    /// @notice takes appropriate action after voting is finished
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

    /// @notice requests refund in case the project is failed
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

    /// @dev callback for the token
    function onTokenTransfer(address from, address to, uint amount)
        external
        initialized
        onlyToken
    {
        if (!isActive())
            return;

        address delegate = getDelegate(from);
        if (delegate == from)
            // not a delegator
            subVotingTokens(from, amount);
        else {
            // delegator - updates delegate state
            getDelegateState(delegate).votesAccumulated = getDelegateState(delegate).votesAccumulated.sub(amount);
            subVotingTokens(delegate, amount);
        }

        delegate = getDelegate(to);
        if (delegate == to)
            // not a delegator
            addVotingTokens(to, amount);
        else {
            // delegator - updates delegate state
            getDelegateState(delegate).votesAccumulated = getDelegateState(delegate).votesAccumulated.add(amount);
            addVotingTokens(delegate, amount);
        }
    }

    /// @notice explicit init function
    function init() external initialized {}


    // PUBLIC: fund state

    function isActive() public constant returns (bool) {
        return !isFinished() && !isRefunding();
    }

    function isRefunding() public constant returns (bool) {
        assert(m_keyPoints.length >= m_keyPointState.length);
        return getCurrentKeyPointState().processed && !getCurrentKeyPointState().success;
    }

    function isFinished() public constant returns (bool) {
        assert(m_keyPoints.length >= m_keyPointState.length);
        return m_keyPoints.length == m_keyPointState.length
                && getCurrentKeyPointState().processed && getCurrentKeyPointState().success;
    }


    // INTERNALS: keypoints

    function validateKeyPoints() private constant {
        assert(m_keyPoints.length > 1);
        uint fundsTotal;
        for (uint i = 0; i < m_keyPoints.length; i++) {
            KeyPoint storage keyPoint = m_keyPoints[i];

            if (0 == i)
                assert(0 == keyPoint.duration);     // initial tranche happens immediately
            else
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

    function getCurrentKeyPoint() internal constant returns (KeyPoint storage) {
        return m_keyPoints[m_keyPointState.length - 1];
    }

    function getCurrentKeyPointState() internal constant returns (KeyPointState storage) {
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


    function getDelegateState(address investor) private constant returns (DelegateState storage result) {
        result = getCurrentKeyPointState().delegateState[investor];
        // mutually exclusive state
        assert(0 == result.votesAccumulated || address(0) == getCurrentKeyPointState().delegatorState[investor].delegate);
    }

    function getDelegatorState(address investor) private constant returns (DelegatorState storage result) {
        result = getCurrentKeyPointState().delegatorState[investor];
        // mutually exclusive state
        assert(address(0) == result.delegate || 0 == getCurrentKeyPointState().delegateState[investor].votesAccumulated);
    }

    /// @dev finds final delegate in the delegation chain of the investor
    function getDelegate(address investor) private constant returns (address result) {
        result = investor;
        while (true) {
            address next = getDelegatorState(result).delegate;
            if (address(0) == next)
                break;
            else
                result = next;
        }
    }


    /// @dev main decision maker
    function isKeyPointApproved() private constant returns (bool) {
        KeyPointState storage state = getCurrentKeyPointState();
        uint totalVotes = state.approvalVotes.add(state.disapprovalVotes);
        if (0 == totalVotes)
            return true;

        return state.approvalVotes > state.disapprovalVotes.add(totalVotes.mul(m_approveMarginPercent).div(100));
    }

    /// @dev to be overridden in tests
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
