pragma solidity ^0.4.15;

import './IDAOToken.sol';


/// @title ICO fund controlled by the investors
contract DAOFund {

    // Decision point description for the DAO
    struct KeyPoint {
        // duration of the period which is evaluated at this point
        uint duration;

        // funds share percent to be transfered to the project at this keypoint
        uint fundsShare;
    }

    // Dynamic state of a KeyPoint
    struct KeyPointState {
        // true iff decision was made to further finance the project
        bool success;
    }


    // event fired when the DAO comes to conclusion about a KeyPoint
    event KeyPointResolved(uint keyPointIndex, bool success);


    // PUBLIC interface

    function DAOFund(IDAOToken token){
        m_token = token;

        m_keyPoints.push(KeyPoint({duration: 20 weeks, fundsShare: 25}));
        m_keyPoints.push(KeyPoint({duration: 40 weeks, fundsShare: 45}));
        m_keyPoints.push(KeyPoint({duration: 20 weeks, fundsShare: 30}));

        validateKeyPoints();

        // first tranche after the ICO
        m_keyPointState.push(KeyPointState({success: true}));
        KeyPointResolved(0, true);
    }


    // INTERNALS

    function validateKeyPoints() private constant {
        uint fundsTotal;
        for (uint i = 0; i < m_keyPoints.length; i++) {
            KeyPoint storage keyPoint = m_keyPoints[i];

            assert(keyPoint.duration >= 1 weeks);
            fundsTotal += keyPoint.fundsShare;
        }
        assert(100 == fundsTotal);
    }


    // FIELDS

    IDAOToken public m_token;

    KeyPoint[] public m_keyPoints;
    KeyPointState[] public m_keyPointState;
}
