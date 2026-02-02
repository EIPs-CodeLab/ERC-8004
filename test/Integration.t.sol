// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IdentityRegistry.sol";
import "../src/ReputationRegistry.sol";
import "../src/ValidationRegistry.sol";

/**
 * @title ERC8004Integration
 * @notice Complete integration test showing the full ERC-8004 workflow
 * @dev Demonstrates: Registration → Feedback → Validation → Trust Evaluation
 */
contract ERC8004IntegrationTest is Test {
    IdentityRegistry public identityRegistry;
    ReputationRegistry public reputationRegistry;
    ValidationRegistry public validationRegistry;
    
    // Actors
    address public priceOracleAgent = address(0x1);
    address public shoppingAgent = address(0x2);
    address public client1 = address(0x3);
    address public client2 = address(0x4);
    address public zkmlValidator = address(0x5);
    
    uint256 public priceOracleAgentId;
    
    function setUp() public {
        // Deploy the three registries
        identityRegistry = new IdentityRegistry();
        reputationRegistry = new ReputationRegistry(address(identityRegistry));
        validationRegistry = new ValidationRegistry(address(identityRegistry));
        
        console.log("=== ERC-8004 Registries Deployed ===");
        console.log("Identity Registry:", address(identityRegistry));
        console.log("Reputation Registry:", address(reputationRegistry));
        console.log("Validation Registry:", address(validationRegistry));
    }
    
    function testCompleteAgentEconomy() public {
        // ===== STEP 1: DISCOVERY - Register PriceOracleAgent =====
        console.log("\n=== STEP 1: AGENT REGISTRATION ===");
        
        vm.prank(priceOracleAgent);
        priceOracleAgentId = identityRegistry.register("ipfs://QmPriceOracleAgent");
        
        console.log("PriceOracleAgent registered with ID:", priceOracleAgentId);
        console.log("Owner:", identityRegistry.ownerOf(priceOracleAgentId));
        console.log("Agent URI:", identityRegistry.tokenURI(priceOracleAgentId));
        
        // Set metadata
        vm.prank(priceOracleAgent);
        identityRegistry.setMetadata(priceOracleAgentId, "skill", abi.encode("price-research"));
        
        assertEq(identityRegistry.ownerOf(priceOracleAgentId), priceOracleAgent);
        assertEq(
            abi.decode(identityRegistry.getMetadata(priceOracleAgentId, "skill"), (string)),
            "price-research"
        );
        
        // ===== STEP 2: TRUST EVALUATION - Build Reputation =====
        console.log("\n=== STEP 2: REPUTATION BUILDING ===");
        
        // Client 1 gives excellent feedback
        vm.prank(client1);
        reputationRegistry.giveFeedback(
            priceOracleAgentId,
            95,
            0,
            "starred",
            "",
            "https://api.priceoracle.com/getPrice",
            "ipfs://Qmfeedback1",
            keccak256("feedback1-content")
        );
        console.log("Client1 gave feedback: 95/100 (starred)");
        
        // Client 2 gives good feedback with uptime metric
        vm.prank(client2);
        reputationRegistry.giveFeedback(
            priceOracleAgentId,
            9985,
            2, // 99.85%
            "uptime",
            "",
            "https://api.priceoracle.com",
            "ipfs://Qmfeedback2",
            keccak256("feedback2-content")
        );
        console.log("Client2 gave feedback: 99.85% uptime");
        
        // Client 1 gives another feedback (response time)
        vm.prank(client1);
        reputationRegistry.giveFeedback(
            priceOracleAgentId,
            450,
            0,
            "responseTime",
            "",
            "",
            "",
            bytes32(0)
        );
        console.log("Client1 gave feedback: 450ms response time");
        
        // Query reputation summary
        address[] memory trustedClients = new address[](2);
        trustedClients[0] = client1;
        trustedClients[1] = client2;
        
        (uint64 count, int128 sum, uint8 decimals) = reputationRegistry.getSummary(
            priceOracleAgentId,
            trustedClients,
            "",
            ""
        );
        
        console.log("\nReputation Summary:");
        console.log("  Total feedback count:", count);
        console.log("  Sum of all values:", uint128(sum));
        console.log("  Decimals:", decimals);
        
        assertEq(count, 3);
        assertEq(sum, 10530); // 95 + 9985 + 450
        
        // Query filtered by tag
        (uint64 starredCount, int128 starredSum,) = reputationRegistry.getSummary(
            priceOracleAgentId,
            trustedClients,
            "starred",
            ""
        );
        
        console.log("\nStarred ratings only:");
        console.log("  Count:", starredCount);
        console.log("  Sum:", uint128(starredSum));
        
        assertEq(starredCount, 1);
        assertEq(starredSum, 95);
        
        // ===== STEP 3: VERIFICATION - Request zkML Validation =====
        console.log("\n=== STEP 3: VALIDATION REQUEST ===");
        
        bytes32 jobHash = keccak256("price-job-12345");
        
        vm.prank(priceOracleAgent);
        validationRegistry.validationRequest(
            zkmlValidator,
            priceOracleAgentId,
            "ipfs://QmJobInputsOutputs",
            jobHash
        );
        
        console.log("Validation requested from zkML validator");
        console.log("Request hash:", vm.toString(jobHash));
        
        // zkML Validator responds with proof
        vm.prank(zkmlValidator);
        validationRegistry.validationResponse(
            jobHash,
            100, // Passed validation
            "ipfs://QmZkmlProof",
            keccak256("zkml-proof-data"),
            "zkml-verified"
        );
        
        console.log("Validator responded: 100/100 (zkml-verified)");
        
        // Get validation status
        (
            address validator,
            uint256 agentId,
            uint8 response,
            bytes32 responseHash,
            string memory tag,
            uint256 lastUpdate
        ) = validationRegistry.getValidationStatus(jobHash);
        
        console.log("\nValidation Status:");
        console.log("  Validator:", validator);
        console.log("  Agent ID:", agentId);
        console.log("  Response:", response);
        console.log("  Tag:", tag);
        console.log("  Last update:", lastUpdate);
        
        assertEq(validator, zkmlValidator);
        assertEq(agentId, priceOracleAgentId);
        assertEq(response, 100);
        assertEq(tag, "zkml-verified");
        
        // ===== STEP 4: ENGAGEMENT - ShoppingAgent Evaluates & Hires =====
        console.log("\n=== STEP 4: AGENT-TO-AGENT ENGAGEMENT ===");
        
        // Shopping agent discovers PriceOracleAgent via Identity Registry
        console.log("ShoppingAgent found agent:", priceOracleAgentId);
        console.log("Agent URI:", identityRegistry.tokenURI(priceOracleAgentId));
        
        // Check reputation
        (uint64 repCount, int128 repSum,) = reputationRegistry.getSummary(
            priceOracleAgentId,
            trustedClients,
            "",
            ""
        );
        console.log("Reputation: Count=", repCount, "Sum=", uint128(repSum));
        
        // Check validation
        address[] memory validators = new address[](1);
        validators[0] = zkmlValidator;
        (uint64 valCount, uint8 valAvg) = validationRegistry.getSummary(
            priceOracleAgentId,
            validators,
            ""
        );
        console.log("Validation: Count=", valCount, "Average=", valAvg);
        
        // Decision: Trust established!
        assertTrue(repCount > 0, "Agent has reputation");
        assertTrue(valAvg >= 90, "Agent has high validation score");
        
        console.log("\n ShoppingAgent decides to hire PriceOracleAgent!");
        console.log("   Criteria met:");
        console.log("   - Reputation from trusted clients");
        console.log("   - zkML validation passed");
        console.log("   - All checks verified on-chain");
        
        // ===== STEP 5: POST-ENGAGEMENT - Leave Feedback =====
        console.log("\n=== STEP 5: POST-ENGAGEMENT FEEDBACK ===");
        
        vm.prank(shoppingAgent);
        reputationRegistry.giveFeedback(
            priceOracleAgentId,
            98,
            0,
            "starred",
            "",
            "",
            "ipfs://QmShoppingAgentFeedback",
            keccak256("shopping-agent-feedback")
        );
        
        console.log("ShoppingAgent gave feedback: 98/100 (starred)");
        
        // Get updated reputation including shopping agent
        address[] memory allClients = new address[](3);
        allClients[0] = client1;
        allClients[1] = client2;
        allClients[2] = shoppingAgent;
        
        (uint64 finalCount, int128 finalSum,) = reputationRegistry.getSummary(
            priceOracleAgentId,
            allClients,
            "",
            ""
        );
        
        console.log("\nFinal Reputation Summary:");
        console.log("  Total feedback:", finalCount);
        console.log("  Sum:", uint128(finalSum));
        console.log("  Average (approx):", uint128(finalSum) / finalCount);
        
        assertEq(finalCount, 4);
        assertEq(finalSum, 10628); // Previous 10530 + 98
        
        console.log("\n Complete ERC-8004 workflow demonstrated!");
        console.log("   Discovery -> Reputation -> Validation -> Engagement -> Feedback");
    }
    
    function testSybilResistance() public {
        console.log("\n=== SYBIL RESISTANCE TEST ===");
        
        // Register agent
        vm.prank(priceOracleAgent);
        priceOracleAgentId = identityRegistry.register("ipfs://agent");
        
        // Simulate Sybil attack: many fake clients give feedback
        for (uint i = 0; i < 10; i++) {
            address fakeClient = address(uint160(i + 100));
            vm.prank(fakeClient);
            reputationRegistry.giveFeedback(
                priceOracleAgentId,
                100,
                0,
                "starred",
                "",
                "",
                "",
                bytes32(0)
            );
        }
        
        console.log("10 Sybil accounts gave fake 100/100 ratings");
        
        // But we only trust specific reviewers
        address[] memory trustedOnly = new address[](1);
        trustedOnly[0] = client1;
        
        // Give real feedback from trusted client
        vm.prank(client1);
        reputationRegistry.giveFeedback(priceOracleAgentId, 60, 0, "starred", "", "", "", bytes32(0));
        
        // Query using only trusted reviewers
        (uint64 count, int128 sum,) = reputationRegistry.getSummary(
            priceOracleAgentId,
            trustedOnly,
            "",
            ""
        );
        
        console.log("\nTrusted reviewers only:");
        console.log("  Count:", count);
        console.log("  Sum:", uint128(sum));
        console.log("  Average:", uint128(sum) / count);
        
        assertEq(count, 1);
        assertEq(sum, 60);
        
        console.log("\n Sybil attack mitigated by filtering trusted reviewers!");
    }
}
