// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IdentityRegistry.sol";
import "../src/ReputationRegistry.sol";

contract ReputationRegistryTest is Test {
    IdentityRegistry public identityRegistry;
    ReputationRegistry public reputationRegistry;
    
    address public agentOwner;
    address public client1;
    address public client2;
    uint256 public agentId;

    function setUp() public {
        agentOwner = address(0x123);
        client1 = address(0x456);
        client2 = address(0x789);
        
        identityRegistry = new IdentityRegistry();
        reputationRegistry = new ReputationRegistry(address(identityRegistry));
        
        vm.prank(agentOwner);
        agentId = identityRegistry.register("ipfs://Agent1");
    }

    function testGiveFeedback() public {
        vm.startPrank(client1);
        
        reputationRegistry.giveFeedback(
            agentId,
            80,         // value
            0,          // decimals
            "quality",  // tag1
            "",         // tag2
            "",         // endpoint
            "",         // feedbackURI
            bytes32(0)  // feedbackHash
        );
        
        (uint64 count, int128 sum, uint8 decimals) = reputationRegistry.getSummary(
            agentId,
            _makeAddrArray(client1),
            "",
            ""
        );
        
        assertEq(count, 1);
        assertEq(sum, 80);
        assertEq(decimals, 0);
        
        vm.stopPrank();
    }
    
    function testGiveMultipleFeedback() public {
        // Client 1 gives feedback
        vm.prank(client1);
        reputationRegistry.giveFeedback(agentId, 100, 2, "t1", "t2", "", "", bytes32(0));
        
        // Client 2 gives feedback
        vm.prank(client2);
        reputationRegistry.giveFeedback(agentId, 50, 2, "t1", "t2", "", "", bytes32(0));
        
        address[] memory clients = new address[](2);
        clients[0] = client1;
        clients[1] = client2;
        
        (uint64 count, int128 sum, uint8 decimals) = reputationRegistry.getSummary(
            agentId,
            clients,
            "",
            ""
        );
        
        assertEq(count, 2);
        assertEq(sum, 150); // 100 + 50
        assertEq(decimals, 2);
    }
    
    function testRevokeFeedback() public {
        vm.startPrank(client1);
        reputationRegistry.giveFeedback(agentId, 100, 0, "", "", "", "", bytes32(0));
        
        uint64 lastIndex = reputationRegistry.getLastIndex(agentId, client1);
        reputationRegistry.revokeFeedback(agentId, lastIndex);
        
        (,,,, bool isRevoked) = reputationRegistry.readFeedback(agentId, client1, lastIndex);
        assertTrue(isRevoked);
        
        // Summary should ignore revoked feedback
        (uint64 count, int128 sum,) = reputationRegistry.getSummary(
            agentId,
            _makeAddrArray(client1),
            "",
            ""
        );
        
        assertEq(count, 0);
        assertEq(sum, 0);
        vm.stopPrank();
    }
    
    function testFeedbackSelf() public {
        vm.startPrank(agentOwner);
        vm.expectRevert(bytes("Cannot feedback yourself"));
        reputationRegistry.giveFeedback(agentId, 100, 0, "", "", "", "", bytes32(0));
        vm.stopPrank();
    }
    
    function testAppendResponse() public {
        vm.prank(client1);
        reputationRegistry.giveFeedback(agentId, 100, 0, "", "", "", "", bytes32(0));
        uint64 feedbackIndex = 1;
        
        vm.prank(agentOwner); // Agent responds to feedback
        reputationRegistry.appendResponse(
            agentId, 
            client1,
            feedbackIndex,
            "ipfs://Response",
            bytes32(0)
        );
        
        uint64 respCount = reputationRegistry.getResponseCount(agentId, client1, feedbackIndex, new address[](0));
        assertEq(respCount, 1);
    }

    function _makeAddrArray(address a) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = a;
        return arr;
    }
}
