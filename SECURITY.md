# Security Policy

## Reporting a Vulnerability

Please report security issues directly to the maintainers via email or private GitHub issue defined in the repository.

## Project Scope

The following contracts are in scope:
- `src/IdentityRegistry.sol`
- `src/ReputationRegistry.sol`
- `src/ValidationRegistry.sol`

## Known Considerations (from EIP-8004)

### Sybil Resistance
The protocol is permissionless. Sybil attacks are possible (creating many fake agents). The **Reputation Registry** is the mitigation layer; users and dApps should filter agents based on high reputation from trusted reviewers.

### Off-Chain Data Integrity
The contracts store hashes (`keccak256`) of off-chain data (JSON files). It is the responsibility of the client to verify that the downloaded data matches the on-chain hash. If the hash does not match, the data MUST be rejected.

### Improper Input Handling
- `agentWallet` update requires a valid EIP-712 signature.
- Feedback submission prevents self-modification by the agent owner (though alternate accounts can still be used, see Sybil Resistance).
