// code/contracts/test/security/CrossDomainReplay.t.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712Domain} from "../../src/lib/EIP712Domain.sol";

/// @dev Attacks 9 and 10 in §2.3. A SignedRequest whose EIP-712 domain
/// embeds a stale chainId (attack 9) or stale verifyingContract (attack 10)
/// recovers to an address other than the original signer. The protocol
/// rejects such requests because the recovered signer fails the
/// service-registry membership check (off-chain) and the Merkle inclusion
/// check (on-chain), but the cleanest demonstration is at the typed-data
/// primitive layer: same struct fields, different domain, different recovered
/// signer. This test pins that property.
contract CrossDomainReplayTest is Test {
    uint256 constant ALICE_PK = 0xA11CE;

    bytes32 constant TYPEHASH = keccak256(
        "SignedRequest(bytes32 sessionId,uint64 seq,bytes32 requestHash,bytes32 prevHash)"
    );

    function _digest(uint256 chainId_, address verifyingContract_) internal pure returns (bytes32) {
        bytes32 domain = EIP712Domain.domainSeparator("TallyMesh", "1", chainId_, verifyingContract_);
        bytes32 structHash = keccak256(
            abi.encode(
                TYPEHASH,
                bytes32("session-1"),
                uint64(1),
                keccak256("req"),
                bytes32(0)
            )
        );
        return EIP712Domain.hashTypedData(domain, structHash);
    }

    function test_attack09_crossChainReplay_recoversDifferentSigner() public {
        bytes32 chainADigest = _digest(1, address(0xCA11));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, chainADigest);
        bytes memory sig = abi.encodePacked(r, s, v);
        // Same signature is recovered against chain B (chainId 137, same contract).
        bytes32 chainBDigest = _digest(137, address(0xCA11));
        address recoveredA = ECDSA.recover(chainADigest, sig);
        address recoveredB = ECDSA.recover(chainBDigest, sig);
        assertEq(recoveredA, vm.addr(ALICE_PK), "valid recovery on the original chain");
        assertTrue(recoveredB != recoveredA, "stale chainId must yield a different recovered signer");
    }

    function test_attack10_crossContractReplay_recoversDifferentSigner() public {
        bytes32 c1Digest = _digest(1, address(0xCA11));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, c1Digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        // Same chainId, different verifyingContract.
        bytes32 c2Digest = _digest(1, address(0xDEAD));
        address recovered1 = ECDSA.recover(c1Digest, sig);
        address recovered2 = ECDSA.recover(c2Digest, sig);
        assertEq(recovered1, vm.addr(ALICE_PK), "valid recovery on the original verifying contract");
        assertTrue(recovered2 != recovered1, "stale verifyingContract must yield a different recovered signer");
    }
}
