// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IdentityRegistry.sol";
import "../src/ValidationRegistry.sol";

contract ValidationRegistryTest is Test {
    IdentityRegistry public identityRegistry;
    ValidationRegistry public validationRegistry;
    
    address public agentOwner;
    address public validator;
    uint256 public agentId;
    bytes32 public constant REQUEST_HASH = keccak256("request");

    function setUp() public {
        agentOwner = address(0x123);
        validator = address(0x456);
        
        identityRegistry = new IdentityRegistry();
        validationRegistry = new ValidationRegistry(address(identityRegistry));
        
        vm.prank(agentOwner);
        agentId = identityRegistry.register("ipfs://Agent1");
    }

    function testValidationRequest() public {
        vm.startPrank(agentOwner);
        
        validationRegistry.validationRequest(
            validator,
            agentId,
            "ipfs://Request",
            REQUEST_HASH
        );
        
        (address vAddr, uint256 aId,,,,) = validationRegistry.getValidationStatus(REQUEST_HASH);
        assertEq(vAddr, validator);
        assertEq(aId, agentId);
        
        vm.stopPrank();
    }
    
    function testValidationResponse() public {
        vm.prank(agentOwner);
        validationRegistry.validationRequest(
            validator,
            agentId,
            "ipfs://Request",
            REQUEST_HASH
        );
        
        vm.startPrank(validator);
        validationRegistry.validationResponse(
            REQUEST_HASH,
            100,
            "ipfs://Response",
            keccak256("response"),
            "success"
        );
        
        (,, uint8 response,, string memory tag,) = validationRegistry.getValidationStatus(REQUEST_HASH);
        assertEq(response, 100);
        assertEq(tag, "success");
        vm.stopPrank();
    }
    
    function testValidationSummary() public {
        // Create 2 requests
        bytes32 req1 = keccak256("req1");
        bytes32 req2 = keccak256("req2");
        
        vm.startPrank(agentOwner);
        validationRegistry.validationRequest(validator, agentId, "", req1);
        validationRegistry.validationRequest(validator, agentId, "", req2);
        vm.stopPrank();
        
        // Respond to both
        vm.startPrank(validator);
        validationRegistry.validationResponse(req1, 100, "", bytes32(0), "");
        validationRegistry.validationResponse(req2, 50, "", bytes32(0), "");
        vm.stopPrank();
        
        (uint64 count, uint8 avg) = validationRegistry.getSummary(
            agentId,
            new address[](0),
            ""
        );
        
        assertEq(count, 2);
        assertEq(avg, 75); // (100 + 50) / 2
    }
    
    function testUnauthorizedRequest() public {
        vm.prank(address(0x999)); // Not owner
        vm.expectRevert(bytes("Not authorized"));
        validationRegistry.validationRequest(validator, agentId, "", REQUEST_HASH);
    }
}
