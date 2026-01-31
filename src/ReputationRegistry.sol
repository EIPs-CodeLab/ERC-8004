// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "./IdentityRegistry.sol";

/**
 * @title ReputationRegistry
 * @notice ERC-8004 Reputation Registry - Standardized feedback and reputation system for agents
 * @dev Stores feedback signals on-chain with optional off-chain IPFS data
 */
contract ReputationRegistry {
    IdentityRegistry public immutable identityRegistry;
    
    struct Feedback {
        int128 value;
        uint8 valueDecimals;
        string tag1;
        string tag2;
        bool isRevoked;
    }
    
    struct ResponseRecord {
        address responder;
        string responseURI;
        bytes32 responseHash;
    }
    
    // agentId => clientAddress => feedbackIndex => Feedback
    mapping(uint256 => mapping(address => mapping(uint64 => Feedback))) private _feedback;
    
    // agentId => clientAddress => lastFeedbackIndex
    mapping(uint256 => mapping(address => uint64)) private _lastIndex;
    
    // agentId => list of client addresses
    mapping(uint256 => address[]) private _clients;
    mapping(uint256 => mapping(address => bool)) private _isClient;
    
    // agentId => clientAddress => feedbackIndex => responses
    mapping(uint256 => mapping(address => mapping(uint64 => ResponseRecord[]))) private _responses;
    
    // Events
    event NewFeedback(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64 feedbackIndex,
        int128 value,
        uint8 valueDecimals,
        string indexed indexedTag1,
        string tag1,
        string tag2,
        string endpoint,
        string feedbackURI,
        bytes32 feedbackHash
    );
    
    event FeedbackRevoked(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64 indexed feedbackIndex
    );
    
    event ResponseAppended(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64 feedbackIndex,
        address indexed responder,
        string responseURI,
        bytes32 responseHash
    );
    
    constructor(address identityRegistry_) {
        identityRegistry = IdentityRegistry(identityRegistry_);
    }
    
    /**
     * @notice Get the identity registry address
     * @return The identity registry contract address
     */
    function getIdentityRegistry() external view returns (address) {
        return address(identityRegistry);
    }
    
    /**
     * @notice Submit feedback for an agent
     * @param agentId The agent ID receiving feedback
     * @param value The feedback value (signed fixed-point number)
     * @param valueDecimals Number of decimal places (0-18)
     * @param tag1 Optional categorization tag
     * @param tag2 Optional additional tag
     * @param endpoint Optional endpoint URI
     * @param feedbackURI Optional off-chain feedback file URI
     * @param feedbackHash Optional hash of feedbackURI content (keccak256)
     */
    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external {
        // Validate agent exists
        require(identityRegistry.ownerOf(agentId) != address(0), "Agent does not exist");
        
        // Validate decimals
        require(valueDecimals <= 18, "valueDecimals must be <= 18");
        
        // Prevent agent owner/operators from giving feedback to themselves
        address agentOwner = identityRegistry.ownerOf(agentId);
        require(msg.sender != agentOwner, "Cannot feedback yourself");
        require(!identityRegistry.isApprovedForAll(agentOwner, msg.sender), "Operators cannot feedback");
        require(identityRegistry.getApproved(agentId) != msg.sender, "Approved addresses cannot feedback");
        
        // Increment feedback index for this client
        uint64 feedbackIndex = ++_lastIndex[agentId][msg.sender];
        
        // Store feedback
        _feedback[agentId][msg.sender][feedbackIndex] = Feedback({
            value: value,
            valueDecimals: valueDecimals,
            tag1: tag1,
            tag2: tag2,
            isRevoked: false
        });
        
        // Track client if first feedback
        if (feedbackIndex == 1) {
            _clients[agentId].push(msg.sender);
            _isClient[agentId][msg.sender] = true;
        }
        
        emit NewFeedback(
            agentId,
            msg.sender,
            feedbackIndex,
            value,
            valueDecimals,
            tag1,
            tag1,
            tag2,
            endpoint,
            feedbackURI,
            feedbackHash
        );
    }
    
    /**
     * @notice Revoke previously submitted feedback
     * @param agentId The agent ID
     * @param feedbackIndex The feedback index to revoke
     */
    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external {
        require(feedbackIndex > 0 && feedbackIndex <= _lastIndex[agentId][msg.sender], "Invalid feedback index");
        require(!_feedback[agentId][msg.sender][feedbackIndex].isRevoked, "Already revoked");
        
        _feedback[agentId][msg.sender][feedbackIndex].isRevoked = true;
        
        emit FeedbackRevoked(agentId, msg.sender, feedbackIndex);
    }
    
    /**
     * @notice Append a response to feedback
     * @param agentId The agent ID
     * @param clientAddress The client who gave feedback
     * @param feedbackIndex The feedback index
     * @param responseURI URI to response content
     * @param responseHash Hash of response content (keccak256)
     */
    function appendResponse(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        string calldata responseURI,
        bytes32 responseHash
    ) external {
        require(feedbackIndex > 0 && feedbackIndex <= _lastIndex[agentId][clientAddress], "Invalid feedback index");
        
        _responses[agentId][clientAddress][feedbackIndex].push(ResponseRecord({
            responder: msg.sender,
            responseURI: responseURI,
            responseHash: responseHash
        }));
        
        emit ResponseAppended(agentId, clientAddress, feedbackIndex, msg.sender, responseURI, responseHash);
    }
    
    /**
     * @notice Get aggregated feedback summary
     * @param agentId The agent ID
     * @param clientAddresses Array of client addresses to filter by (required, non-empty)
     * @param tag1 Optional tag1 filter (empty string = no filter)
     * @param tag2 Optional tag2 filter (empty string = no filter)
     * @return count Number of matching feedback entries
     * @return summaryValue Sum of all feedback values
     * @return summaryValueDecimals Decimals for the summary (using first feedback's decimals)
     */
    function getSummary(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata tag1,
        string calldata tag2
    ) external view returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals) {
        require(clientAddresses.length > 0, "clientAddresses cannot be empty");
        
        int256 sum = 0;
        uint64 matchCount = 0;
        uint8 decimals = 0;
        bool decimalsSet = false;
        
        bytes32 tag1Hash = keccak256(bytes(tag1));
        bytes32 tag2Hash = keccak256(bytes(tag2));
        bool filterTag1 = bytes(tag1).length > 0;
        bool filterTag2 = bytes(tag2).length > 0;
        
        for (uint256 i = 0; i < clientAddresses.length; i++) {
            address client = clientAddresses[i];
            uint64 lastIdx = _lastIndex[agentId][client];
            
            for (uint64 idx = 1; idx <= lastIdx; idx++) {
                Feedback storage fb = _feedback[agentId][client][idx];
                
                // Skip revoked feedback
                if (fb.isRevoked) continue;
                
                // Apply tag filters
                if (filterTag1 && keccak256(bytes(fb.tag1)) != tag1Hash) continue;
                if (filterTag2 && keccak256(bytes(fb.tag2)) != tag2Hash) continue;
                
                // Set decimals from first valid feedback
                if (!decimalsSet) {
                    decimals = fb.valueDecimals;
                    decimalsSet = true;
                }
                
                sum += int256(fb.value);
                matchCount++;
            }
        }
        
        return (matchCount, int128(sum), decimals);
    }
    
    /**
     * @notice Read a specific feedback entry
     * @param agentId The agent ID
     * @param clientAddress The client address
     * @param feedbackIndex The feedback index
     * @return value The feedback value
     * @return valueDecimals The value decimals
     * @return tag1 Tag1
     * @return tag2 Tag2
     * @return isRevoked Whether the feedback is revoked
     */
    function readFeedback(uint256 agentId, address clientAddress, uint64 feedbackIndex)
        external
        view
        returns (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked)
    {
        require(feedbackIndex > 0 && feedbackIndex <= _lastIndex[agentId][clientAddress], "Invalid feedback index");
        
        Feedback storage fb = _feedback[agentId][clientAddress][feedbackIndex];
        return (fb.value, fb.valueDecimals, fb.tag1, fb.tag2, fb.isRevoked);
    }
    
    /**
     * @notice Read all feedback matching filters
     * @param agentId The agent ID
     * @param clientAddresses Array of client addresses (empty = all clients)
     * @param tag1 Tag1 filter (empty = no filter)
     * @param tag2 Tag2 filter (empty = no filter)
     * @param includeRevoked Whether to include revoked feedback
     * @return clients Array of client addresses
     * @return feedbackIndexes Array of feedback indexes
     * @return values Array of feedback values
     * @return decimalsArray Array of value decimals
     * @return tag1s Array of tag1 values
     * @return tag2s Array of tag2 values
     * @return revokedStatuses Array of revocation statuses
     */
    function readAllFeedback(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata tag1,
        string calldata tag2,
        bool includeRevoked
    )
        external
        view
        returns (
            address[] memory clients,
            uint64[] memory feedbackIndexes,
            int128[] memory values,
            uint8[] memory decimalsArray,
            string[] memory tag1s,
            string[] memory tag2s,
            bool[] memory revokedStatuses
        )
    {
        // Determine which clients to query
        address[] memory queryClients;
        if (clientAddresses.length > 0) {
            queryClients = clientAddresses;
        } else {
            queryClients = _clients[agentId];
        }
        
        // First pass: count matching feedback
        uint256 matchCount = 0;
        bytes32 tag1Hash = keccak256(bytes(tag1));
        bytes32 tag2Hash = keccak256(bytes(tag2));
        bool filterTag1 = bytes(tag1).length > 0;
        bool filterTag2 = bytes(tag2).length > 0;
        
        for (uint256 i = 0; i < queryClients.length; i++) {
            address client = queryClients[i];
            uint64 lastIdx = _lastIndex[agentId][client];
            
            for (uint64 fbIdx = 1; fbIdx <= lastIdx; fbIdx++) {
                Feedback storage fb = _feedback[agentId][client][fbIdx];
                
                if (!includeRevoked && fb.isRevoked) continue;
                if (filterTag1 && keccak256(bytes(fb.tag1)) != tag1Hash) continue;
                if (filterTag2 && keccak256(bytes(fb.tag2)) != tag2Hash) continue;
                
                matchCount++;
            }
        }
        
        // Allocate arrays
        clients = new address[](matchCount);
        feedbackIndexes = new uint64[](matchCount);
        values = new int128[](matchCount);
        decimalsArray = new uint8[](matchCount);
        tag1s = new string[](matchCount);
        tag2s = new string[](matchCount);
        revokedStatuses = new bool[](matchCount);
        
        // Second pass: populate arrays
        uint256 idx = 0;
        for (uint256 i = 0; i < queryClients.length; i++) {
            address client = queryClients[i];
            uint64 lastIdx = _lastIndex[agentId][client];
            
            for (uint64 fbIdx = 1; fbIdx <= lastIdx; fbIdx++) {
                Feedback storage fb = _feedback[agentId][client][fbIdx];
                
                if (!includeRevoked && fb.isRevoked) continue;
                if (filterTag1 && keccak256(bytes(fb.tag1)) != tag1Hash) continue;
                if (filterTag2 && keccak256(bytes(fb.tag2)) != tag2Hash) continue;
                
                clients[idx] = client;
                feedbackIndexes[idx] = fbIdx;
                values[idx] = fb.value;
                decimalsArray[idx] = fb.valueDecimals;
                tag1s[idx] = fb.tag1;
                tag2s[idx] = fb.tag2;
                revokedStatuses[idx] = fb.isRevoked;
                idx++;
            }
        }
    }
    
    /**
     * @notice Get response count for a feedback entry
     * @param agentId The agent ID
     * @param clientAddress The client address
     * @param feedbackIndex The feedback index
     * @param responders Array of responder addresses to filter by (empty = all)
     * @return count Number of matching responses
     */
    function getResponseCount(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        address[] calldata responders
    ) external view returns (uint64 count) {
        ResponseRecord[] storage responses = _responses[agentId][clientAddress][feedbackIndex];
        
        if (responders.length == 0) {
            return uint64(responses.length);
        }
        
        uint64 matchCount = 0;
        for (uint256 i = 0; i < responses.length; i++) {
            for (uint256 j = 0; j < responders.length; j++) {
                if (responses[i].responder == responders[j]) {
                    matchCount++;
                    break;
                }
            }
        }
        
        return matchCount;
    }
    
    /**
     * @notice Get all clients who have given feedback to an agent
     * @param agentId The agent ID
     * @return Array of client addresses
     */
    function getClients(uint256 agentId) external view returns (address[] memory) {
        return _clients[agentId];
    }
    
    /**
     * @notice Get the last feedback index for a client
     * @param agentId The agent ID
     * @param clientAddress The client address
     * @return The last feedback index (0 if no feedback)
     */
    function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64) {
        return _lastIndex[agentId][clientAddress];
    }
}
