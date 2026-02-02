// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IdentityRegistry.sol";

contract IdentityRegistryTest is Test {
    IdentityRegistry public registry;
    address public user1;
    address public user2;
    uint256 public constant USER1_PK = 0xA11CE;
    uint256 public constant USER2_PK = 0xB0B;

    function setUp() public {
        registry = new IdentityRegistry();
        user1 = vm.addr(USER1_PK);
        user2 = vm.addr(USER2_PK);
    }

    function testNameAndSymbol() public {
        assertEq(registry.name(), "ERC8004 Agent Identity");
        assertEq(registry.symbol(), "AGENT");
    }

    function testRegisterWithURI() public {
        vm.startPrank(user1);
        string memory uri = "ipfs://QmTest";
        uint256 agentId = registry.register(uri);

        assertEq(registry.ownerOf(agentId), user1);
        assertEq(registry.tokenURI(agentId), uri);
        assertEq(registry.getAgentWallet(agentId), user1); // Default wallet is owner
        vm.stopPrank();
    }

    function testRegisterWithMetadata() public {
        vm.startPrank(user1);
        string memory uri = "ipfs://QmTest";
        IdentityRegistry.MetadataEntry[] memory metadata = new IdentityRegistry.MetadataEntry[](2);
        metadata[0] = IdentityRegistry.MetadataEntry("key1", bytes("value1"));
        metadata[1] = IdentityRegistry.MetadataEntry("key2", bytes("value2"));

        uint256 agentId = registry.register(uri, metadata);

        assertEq(registry.getMetadata(agentId, "key1"), bytes("value1"));
        assertEq(registry.getMetadata(agentId, "key2"), bytes("value2"));
        vm.stopPrank();
    }

    function testSetAgentURI() public {
        vm.startPrank(user1);
        uint256 agentId = registry.register("ipfs://Old");
        registry.setAgentURI(agentId, "ipfs://New");
        assertEq(registry.tokenURI(agentId), "ipfs://New");
        vm.stopPrank();
    }

    function testSetAgentURINotOwner() public {
        vm.startPrank(user1);
        uint256 agentId = registry.register("ipfs://Old");
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(bytes("Not authorized"));
        registry.setAgentURI(agentId, "ipfs://Hacker");
        vm.stopPrank();
    }

    function testSetMetadata() public {
        vm.startPrank(user1);
        uint256 agentId = registry.register("ipfs://Old");
        registry.setMetadata(agentId, "newKey", bytes("newValue"));
        assertEq(registry.getMetadata(agentId, "newKey"), bytes("newValue"));
        vm.stopPrank();
    }

    function testSetAgentWalletEIP712() public {
        vm.startPrank(user1);
        uint256 agentId = registry.register("ipfs://Old");
        
        // Prepare EIP-712 signature
        address newWallet = user2;
        uint256 deadline = block.timestamp + 1 hours;
        
        bytes32 DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ERC8004 IdentityRegistry")),
                keccak256(bytes("1")),
                block.chainid,
                address(registry)
            )
        );
        
        bytes32 SET_AGENT_WALLET_TYPEHASH = keccak256("SetAgentWallet(uint256 agentId,address newWallet,uint256 deadline)");
        
        bytes32 structHash = keccak256(abi.encode(SET_AGENT_WALLET_TYPEHASH, agentId, newWallet, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER2_PK, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        registry.setAgentWallet(agentId, newWallet, deadline, signature);
        
        assertEq(registry.getAgentWallet(agentId), newWallet);
        vm.stopPrank();
    }
}
