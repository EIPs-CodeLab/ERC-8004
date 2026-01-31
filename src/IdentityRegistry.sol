// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "./interfaces/IERC721.sol";
import "./interfaces/IERC721Metadata.sol";
import "./interfaces/IERC1271.sol";

/**
 * @title IdentityRegistry
 * @notice ERC-8004 Identity Registry - Provides portable, censorship-resistant agent identifiers
 * @dev Implements ERC-721 with URIStorage extension for agent registration
 */
contract IdentityRegistry is IERC721, IERC721Metadata {
    // ERC721 State
    string private _name;
    string private _symbol;
    
    uint256 private _nextAgentId;
    
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    
    // ERC8004 Specific State
    mapping(uint256 => string) private _agentURIs;
    mapping(uint256 => mapping(string => bytes)) private _metadata;
    
    // Reserved metadata key for agent wallet
    string private constant AGENT_WALLET_KEY = "agentWallet";
    
    // EIP-712 Domain Separator
    bytes32 private immutable DOMAIN_SEPARATOR;
    
    // EIP-712 Type Hash for wallet verification
    bytes32 private constant SET_AGENT_WALLET_TYPEHASH = 
        keccak256("SetAgentWallet(uint256 agentId,address newWallet,uint256 deadline)");
    
    // Events
    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);
    event MetadataSet(
        uint256 indexed agentId, 
        string indexed indexedMetadataKey, 
        string metadataKey, 
        bytes metadataValue
    );
    event AgentWalletSet(uint256 indexed agentId, address indexed newWallet);
    
    struct MetadataEntry {
        string metadataKey;
        bytes metadataValue;
    }
    
    constructor() {
        _name = "ERC8004 Agent Identity";
        _symbol = "AGENT";
        _nextAgentId = 1;
        
        // Initialize EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ERC8004 IdentityRegistry")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }
    
    // ============ ERC721 Implementation ============
    
    function name() external view override returns (string memory) {
        return _name;
    }
    
    function symbol() external view override returns (string memory) {
        return _symbol;
    }
    
    function balanceOf(address owner) external view override returns (uint256) {
        require(owner != address(0), "ERC721: address zero is not a valid owner");
        return _balances[owner];
    }
    
    function ownerOf(uint256 tokenId) public view override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }
    
    function approve(address to, uint256 tokenId) external override {
        address owner = ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");
        require(
            msg.sender == owner || isApprovedForAll(owner, msg.sender),
            "ERC721: approve caller is not token owner or approved for all"
        );
        
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }
    
    function getApproved(uint256 tokenId) public view override returns (address) {
        require(_owners[tokenId] != address(0), "ERC721: invalid token ID");
        return _tokenApprovals[tokenId];
    }
    
    function setApprovalForAll(address operator, bool approved) external override {
        require(operator != msg.sender, "ERC721: approve to caller");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }
    
    function isApprovedForAll(address owner, address operator) public view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }
    
    function transferFrom(address from, address to, uint256 tokenId) public override {
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: caller is not token owner or approved");
        _transfer(from, to, tokenId);
    }
    
    function safeTransferFrom(address from, address to, uint256 tokenId) external override {
        safeTransferFrom(from, to, tokenId, "");
    }
    
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override {
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: caller is not token owner or approved");
        _safeTransfer(from, to, tokenId, data);
    }
    
    function tokenURI(uint256 tokenId) external view override returns (string memory) {
        require(_owners[tokenId] != address(0), "ERC721: invalid token ID");
        return _agentURIs[tokenId];
    }
    
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            interfaceId == 0x01ffc9a7; // ERC165
    }
    
    // ============ ERC8004 Registration Functions ============
    
    /**
     * @notice Register a new agent with URI and metadata
     * @param agentURI URI pointing to the agent registration file
     * @param metadata Array of metadata entries (excluding agentWallet)
     * @return agentId The newly minted agent ID
     */
    function register(string calldata agentURI, MetadataEntry[] calldata metadata) 
        external 
        returns (uint256 agentId) 
    {
        agentId = _nextAgentId++;
        
        _mint(msg.sender, agentId);
        _agentURIs[agentId] = agentURI;
        
        // Set agentWallet to owner by default
        _metadata[agentId][AGENT_WALLET_KEY] = abi.encode(msg.sender);
        emit MetadataSet(agentId, AGENT_WALLET_KEY, AGENT_WALLET_KEY, abi.encode(msg.sender));
        
        // Set additional metadata
        for (uint256 i = 0; i < metadata.length; i++) {
            require(
                keccak256(bytes(metadata[i].metadataKey)) != keccak256(bytes(AGENT_WALLET_KEY)),
                "Cannot set agentWallet via metadata array"
            );
            _metadata[agentId][metadata[i].metadataKey] = metadata[i].metadataValue;
            emit MetadataSet(
                agentId, 
                metadata[i].metadataKey, 
                metadata[i].metadataKey, 
                metadata[i].metadataValue
            );
        }
        
        emit Registered(agentId, agentURI, msg.sender);
    }
    
    /**
     * @notice Register a new agent with only URI
     * @param agentURI URI pointing to the agent registration file
     * @return agentId The newly minted agent ID
     */
    function register(string calldata agentURI) external returns (uint256 agentId) {
        agentId = _nextAgentId++;
        
        _mint(msg.sender, agentId);
        _agentURIs[agentId] = agentURI;
        
        // Set agentWallet to owner by default
        _metadata[agentId][AGENT_WALLET_KEY] = abi.encode(msg.sender);
        emit MetadataSet(agentId, AGENT_WALLET_KEY, AGENT_WALLET_KEY, abi.encode(msg.sender));
        
        emit Registered(agentId, agentURI, msg.sender);
    }
    
    /**
     * @notice Register a new agent without URI (to be set later)
     * @return agentId The newly minted agent ID
     */
    function register() external returns (uint256 agentId) {
        agentId = _nextAgentId++;
        
        _mint(msg.sender, agentId);
        
        // Set agentWallet to owner by default
        _metadata[agentId][AGENT_WALLET_KEY] = abi.encode(msg.sender);
        emit MetadataSet(agentId, AGENT_WALLET_KEY, AGENT_WALLET_KEY, abi.encode(msg.sender));
        
        emit Registered(agentId, "", msg.sender);
    }
    
    /**
     * @notice Update the agent URI
     * @param agentId The agent ID
     * @param newURI The new URI
     */
    function setAgentURI(uint256 agentId, string calldata newURI) external {
        require(_isApprovedOrOwner(msg.sender, agentId), "Not authorized");
        _agentURIs[agentId] = newURI;
        emit URIUpdated(agentId, newURI, msg.sender);
    }
    
    /**
     * @notice Get metadata value for a key
     * @param agentId The agent ID
     * @param metadataKey The metadata key
     * @return The metadata value
     */
    function getMetadata(uint256 agentId, string memory metadataKey) 
        external 
        view 
        returns (bytes memory) 
    {
        require(_owners[agentId] != address(0), "Agent does not exist");
        return _metadata[agentId][metadataKey];
    }
    
    /**
     * @notice Set metadata value for a key (cannot set agentWallet)
     * @param agentId The agent ID
     * @param metadataKey The metadata key
     * @param metadataValue The metadata value
     */
    function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue) 
        external 
    {
        require(_isApprovedOrOwner(msg.sender, agentId), "Not authorized");
        require(
            keccak256(bytes(metadataKey)) != keccak256(bytes(AGENT_WALLET_KEY)),
            "Use setAgentWallet for agentWallet key"
        );
        
        _metadata[agentId][metadataKey] = metadataValue;
        emit MetadataSet(agentId, metadataKey, metadataKey, metadataValue);
    }
    
    /**
     * @notice Get the agent wallet address
     * @param agentId The agent ID
     * @return The agent wallet address
     */
    function getAgentWallet(uint256 agentId) external view returns (address) {
        require(_owners[agentId] != address(0), "Agent does not exist");
        bytes memory walletData = _metadata[agentId][AGENT_WALLET_KEY];
        if (walletData.length == 0) {
            return address(0);
        }
        return abi.decode(walletData, (address));
    }
    
    /**
     * @notice Set agent wallet with signature verification (EIP-712 or ERC-1271)
     * @param agentId The agent ID
     * @param newWallet The new wallet address
     * @param deadline Signature expiration timestamp
     * @param signature The signature from newWallet
     */
    function setAgentWallet(
        uint256 agentId, 
        address newWallet, 
        uint256 deadline, 
        bytes calldata signature
    ) external {
        require(_isApprovedOrOwner(msg.sender, agentId), "Not authorized");
        require(block.timestamp <= deadline, "Signature expired");
        require(newWallet != address(0), "Invalid wallet address");
        
        // Verify signature
        bytes32 structHash = keccak256(abi.encode(SET_AGENT_WALLET_TYPEHASH, agentId, newWallet, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        
        // Check if newWallet is a contract (ERC-1271) or EOA (EIP-712)
        if (_isContract(newWallet)) {
            // ERC-1271 verification
            require(
                IERC1271(newWallet).isValidSignature(digest, signature) == 0x1626ba7e,
                "Invalid ERC-1271 signature"
            );
        } else {
            // EIP-712 EOA verification
            address signer = _recover(digest, signature);
            require(signer == newWallet, "Invalid signature");
        }
        
        _metadata[agentId][AGENT_WALLET_KEY] = abi.encode(newWallet);
        emit MetadataSet(agentId, AGENT_WALLET_KEY, AGENT_WALLET_KEY, abi.encode(newWallet));
        emit AgentWalletSet(agentId, newWallet);
    }
    
    /**
     * @notice Unset the agent wallet (reset to zero address)
     * @param agentId The agent ID
     */
    function unsetAgentWallet(uint256 agentId) external {
        require(_isApprovedOrOwner(msg.sender, agentId), "Not authorized");
        _metadata[agentId][AGENT_WALLET_KEY] = abi.encode(address(0));
        emit MetadataSet(agentId, AGENT_WALLET_KEY, AGENT_WALLET_KEY, abi.encode(address(0)));
        emit AgentWalletSet(agentId, address(0));
    }
    
    // ============ Internal Functions ============
    
    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0), "ERC721: mint to the zero address");
        require(_owners[tokenId] == address(0), "ERC721: token already minted");
        
        _balances[to] += 1;
        _owners[tokenId] = to;
        
        emit Transfer(address(0), to, tokenId);
    }
    
    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "ERC721: transfer from incorrect owner");
        require(to != address(0), "ERC721: transfer to the zero address");
        
        delete _tokenApprovals[tokenId];
        
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;
        
        // Clear agentWallet on transfer
        _metadata[tokenId][AGENT_WALLET_KEY] = abi.encode(address(0));
        emit MetadataSet(tokenId, AGENT_WALLET_KEY, AGENT_WALLET_KEY, abi.encode(address(0)));
        
        emit Transfer(from, to, tokenId);
    }
    
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "ERC721: transfer to non ERC721Receiver");
    }
    
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender);
    }
    
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (!_isContract(to)) {
            return true;
        }
        
        try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        } catch {
            return false;
        }
    }
    
    function _isContract(address account) private view returns (bool) {
        return account.code.length > 0;
    }
    
    function _recover(bytes32 digest, bytes memory signature) private pure returns (address) {
        require(signature.length == 65, "Invalid signature length");
        
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        
        return ecrecover(digest, v, r, s);
    }
}

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}
