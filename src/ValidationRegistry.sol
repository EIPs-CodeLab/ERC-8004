// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "./IdentityRegistry.sol";

/**
 * @title ValidationRegistry
 * @notice ERC-8004 Validation Registry - Enables cryptographic verification of agent work
 * @dev Supports multiple trust models: stake-secured re-execution, zkML proofs, TEE oracles
 */
contract ValidationRegistry {
    IdentityRegistry public immutable identityRegistry;
    
    struct ValidationStatus {
        address validatorAddress;
        uint256 agentId;
        uint8 response;
        bytes32 responseHash;
        string tag;
        uint256 lastUpdate;
    }
    
    // requestHash => ValidationStatus
    mapping(bytes32 => ValidationStatus) private _validations;
    
    // agentId => array of requestHashes
    mapping(uint256 => bytes32[]) private _agentValidations;
    
    // validatorAddress => array of requestHashes
    mapping(address => bytes32[]) private _validatorRequests;
    
    // Events
    event ValidationRequest(
        address indexed validatorAddress,
        uint256 indexed agentId,
        string requestURI,
        bytes32 indexed requestHash
    );
    
    event ValidationResponse(
        address indexed validatorAddress,
        uint256 indexed agentId,
        bytes32 indexed requestHash,
        uint8 response,
        string responseURI,
        bytes32 responseHash,
        string tag
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
     * @notice Request validation of agent work
     * @param validatorAddress The address of the validator smart contract
     * @param agentId The agent ID requesting validation
     * @param requestURI URI to off-chain data containing validation inputs/outputs
     * @param requestHash Commitment to the request data (keccak256)
     */
    function validationRequest(
        address validatorAddress,
        uint256 agentId,
        string calldata requestURI,
        bytes32 requestHash
    ) external {
        // Verify caller is agent owner or operator
        require(
            msg.sender == identityRegistry.ownerOf(agentId) ||
            identityRegistry.isApprovedForAll(identityRegistry.ownerOf(agentId), msg.sender) ||
            identityRegistry.getApproved(agentId) == msg.sender,
            "Not authorized"
        );
        
        require(validatorAddress != address(0), "Invalid validator address");
        require(requestHash != bytes32(0), "Invalid request hash");
        
        // Initialize validation record if it doesn't exist
        if (_validations[requestHash].validatorAddress == address(0)) {
            _validations[requestHash] = ValidationStatus({
                validatorAddress: validatorAddress,
                agentId: agentId,
                response: 0,
                responseHash: bytes32(0),
                tag: "",
                lastUpdate: 0
            });
            
            _agentValidations[agentId].push(requestHash);
            _validatorRequests[validatorAddress].push(requestHash);
        }
        
        emit ValidationRequest(validatorAddress, agentId, requestURI, requestHash);
    }
    
    /**
     * @notice Submit validation response
     * @param requestHash The request hash being validated
     * @param response Validation result (0-100, binary or spectrum)
     * @param responseURI Optional URI to validation evidence
     * @param responseHash Optional hash of response content (keccak256)
     * @param tag Optional categorization tag (e.g., "soft-finality", "hard-finality")
     */
    function validationResponse(
        bytes32 requestHash,
        uint8 response,
        string calldata responseURI,
        bytes32 responseHash,
        string calldata tag
    ) external {
        ValidationStatus storage validation = _validations[requestHash];
        
        // Verify request exists and caller is the designated validator
        require(validation.validatorAddress != address(0), "Validation request does not exist");
        require(msg.sender == validation.validatorAddress, "Only designated validator can respond");
        require(response <= 100, "Response must be 0-100");
        
        // Update validation status (can be called multiple times for progressive validation)
        validation.response = response;
        validation.responseHash = responseHash;
        validation.tag = tag;
        validation.lastUpdate = block.timestamp;
        
        emit ValidationResponse(
            validation.validatorAddress,
            validation.agentId,
            requestHash,
            response,
            responseURI,
            responseHash,
            tag
        );
    }
    
    /**
     * @notice Get validation status for a request
     * @param requestHash The request hash
     * @return validatorAddress The validator address
     * @return agentId The agent ID
     * @return response The validation response (0-100)
     * @return responseHash The response content hash
     * @return tag The categorization tag
     * @return lastUpdate Timestamp of last update
     */
    function getValidationStatus(bytes32 requestHash)
        external
        view
        returns (
            address validatorAddress,
            uint256 agentId,
            uint8 response,
            bytes32 responseHash,
            string memory tag,
            uint256 lastUpdate
        )
    {
        ValidationStatus storage validation = _validations[requestHash];
        require(validation.validatorAddress != address(0), "Validation does not exist");
        
        return (
            validation.validatorAddress,
            validation.agentId,
            validation.response,
            validation.responseHash,
            validation.tag,
            validation.lastUpdate
        );
    }
    
    /**
     * @notice Get aggregated validation summary for an agent
     * @param agentId The agent ID
     * @param validatorAddresses Array of validator addresses to filter by (empty = all)
     * @param tag Tag filter (empty = no filter)
     * @return count Number of matching validations
     * @return averageResponse Average of all response values
     */
    function getSummary(
        uint256 agentId,
        address[] calldata validatorAddresses,
        string calldata tag
    ) external view returns (uint64 count, uint8 averageResponse) {
        bytes32[] storage requestHashes = _agentValidations[agentId];
        
        uint256 sum = 0;
        uint64 matchCount = 0;
        
        bytes32 tagHash = keccak256(bytes(tag));
        bool filterTag = bytes(tag).length > 0;
        bool filterValidators = validatorAddresses.length > 0;
        
        for (uint256 i = 0; i < requestHashes.length; i++) {
            ValidationStatus storage validation = _validations[requestHashes[i]];
            
            // Skip if no response yet
            if (validation.lastUpdate == 0) continue;
            
            // Apply validator filter
            if (filterValidators) {
                bool matchesValidator = false;
                for (uint256 j = 0; j < validatorAddresses.length; j++) {
                    if (validation.validatorAddress == validatorAddresses[j]) {
                        matchesValidator = true;
                        break;
                    }
                }
                if (!matchesValidator) continue;
            }
            
            // Apply tag filter
            if (filterTag && keccak256(bytes(validation.tag)) != tagHash) continue;
            
            sum += validation.response;
            matchCount++;
        }
        
        if (matchCount == 0) {
            return (0, 0);
        }
        
        return (matchCount, uint8(sum / matchCount));
    }
    
    /**
     * @notice Get all validation request hashes for an agent
     * @param agentId The agent ID
     * @return Array of request hashes
     */
    function getAgentValidations(uint256 agentId) external view returns (bytes32[] memory) {
        return _agentValidations[agentId];
    }
    
    /**
     * @notice Get all validation request hashes for a validator
     * @param validatorAddress The validator address
     * @return Array of request hashes
     */
    function getValidatorRequests(address validatorAddress) external view returns (bytes32[] memory) {
        return _validatorRequests[validatorAddress];
    }
}
