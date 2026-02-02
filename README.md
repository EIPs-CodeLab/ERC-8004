# ERC-8004: Trustless Agents

[![License: CC0-1.0](https://img.shields.io/badge/License-CC0%201.0-lightgrey.svg)](http://creativecommons.org/publicdomain/zero/1.0/)
[![EIP-8004](https://img.shields.io/badge/EIP-8004-blue)](https://eips.ethereum.org/EIPS/eip-8004)

Standardized on-chain discovery, reputation, and validation for AI Agents.

## Overview

ERC-8004 introduces a comprehensive framework for "Trustless Agents" on EVM blockchains. It consists of three core registries:

1.  **Identity Registry**: ERC-721 based system for Agent registration, discovery, and management.
2.  **Reputation Registry**: On-chain feedback system for storing signals (uptime, success rate, user reviews).
3.  **Validation Registry**: Cryptographic verification of agent work (zkML, TEE attestation signals).

## Project Structure

- `src/`: Solidity smart contracts
- `test/`: Foundry unit tests
- `script/`: Deployment scripts
- `Makefile`: Command aliases

## Prerequisites

- [Foundry](https://getfoundry.sh/)
- [Git](https://git-scm.com/)

## Getting Started

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/EIPs-CodeLab/ERC-8004.git
    cd ERC-8004
    ```

2.  **Install dependencies:**
    ```bash
    forge install
    ```

3.  **Build contracts:**
    ```bash
    make build
    ```

4.  **Run tests:**
    ```bash
    make test
    ```

## Development

### Running Tests
Run all tests:
```bash
forge test
```
Run specific test:
```bash
forge test --match-contract IdentityRegistryTest
```

### Deployment (Sepolia)
1.  Copy `.env.example` to `.env` (if not present) and fill in your keys:
    ```bash
    PRIVATE_KEY=your_private_key
    SEPOLIA_RPC_URL=https://rpc.sepolia.org
    ETHERSCAN_API_KEY=your_etherscan_key
    ```
2.  Deploy:
    ```bash
    make deploy-sepolia
    ```

## Real-World Use Cases

| Feature | With ERC-8004 | Without ERC-8004 |
| :--- | :--- | :--- |
| **Discovery** | Universal registry (`eip155:1:0x...`) browseable by any generic dApp | Fragmented, proprietary databases or individual project repositories |
| **Reputation** | Permanent, verifiable history of an agent's performance (uptime, earnings) | Siloed rating systems (like Uber stars) locked in specific platforms |
| **Monetization** | Agents can own their identity (NFT) and transfer accumulated reputation | Selling an agent account violates TOS or is impossible (keys tied to email) |
| **Trust** | Cryptographically linked validation (TEEs, ZK proofs) providing "proof of work" | "Trust me bro" or relying on centralized API guarantees |

## Security

This project follows the [EIP-8004 Security Considerations](https://eips.ethereum.org/EIPS/eip-8004#security-considerations).

contracts are designed to be immutable and permissionless where possible.
See [SECURITY.md](SECURITY.md) for more details.
