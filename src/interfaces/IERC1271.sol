// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC1271 {
    /**
     * @dev Should return whether the signature provided is valid for the provided data
     * @param hash Hash of the data to be signed
     * @param signature Signature byte array associated with hash
     * @return magicValue 0x1626ba7e if valid, otherwise 0xffffffff
     */
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue);
}
