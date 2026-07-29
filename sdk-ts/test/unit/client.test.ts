import { describe, it, expect } from "vitest";
import { privateKeyToAccount } from "viem/accounts";
import { keccak256, toHex } from "viem";
import { Client } from "../../src/client.js";
import { hashReceipt, hashSignedRequest } from "../../src/domain.js";
import type { Receipt } from "../../src/types.js";

const PK_PAYER = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as const;
const RECIPIENT = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" as const;
const VERIFYING = "0x5FbDB2315678afecb367f032d93F642f64180aa3" as const;

function makeReceipt(seq: bigint, sessionId: `0x${string}`): Receipt {
  return {
    sessionId,
    seq,
    requestHash: keccak256(toHex(`req-${seq}`)),
    resultHash: keccak256(toHex(`res-${seq}`)),
    chargedAmount: 1_000_000_000_000n,
    statusCode: ("0x" + "00".repeat(32)) as `0x${string}`,
    serviceTimestamp: 1_700_000_000n + seq,
  };
}

describe("Client (wallet-side signer)", () => {
  it("issues SessionIntent with EOA signature", async () => {
    const client = new Client({
      account: privateKeyToAccount(PK_PAYER),
      verifyingContract: VERIFYING,
      chainId: 31337,
    });
    const intent = await client.openSession({
      sessionId: ("0x" + "ab".repeat(32)) as `0x${string}`,
      recipient: RECIPIENT,
      amount: 5n * 10n ** 18n,
      maxAmount: 5n * 10n ** 18n,
      expiry: 1_999_999_999n,
    });
    expect(intent.signer).toBe(privateKeyToAccount(PK_PAYER).address);
    expect(intent.signature.length).toBeGreaterThan(2);
  });

  it("first SignedRequest has prevHash = zero", async () => {
    const client = new Client({
      account: privateKeyToAccount(PK_PAYER),
      verifyingContract: VERIFYING,
      chainId: 31337,
    });
    const sessionId = ("0x" + "ab".repeat(32)) as `0x${string}`;
    const req = await client.signRequest({
      sessionId,
      seq: 0n,
      requestHash: keccak256(toHex("req-0")),
      prevReceipt: null,
    });
    expect(req.prevHash).toBe("0x" + "00".repeat(32));
    expect(req.seq).toBe(0n);
  });

  it("subsequent SignedRequest links to previous receipt hash", async () => {
    const client = new Client({
      account: privateKeyToAccount(PK_PAYER),
      verifyingContract: VERIFYING,
      chainId: 31337,
    });
    const sessionId = ("0x" + "ab".repeat(32)) as `0x${string}`;
    const r0 = makeReceipt(0n, sessionId);
    const req1 = await client.signRequest({
      sessionId,
      seq: 1n,
      requestHash: keccak256(toHex("req-1")),
      prevReceipt: r0,
    });
    expect(req1.prevHash).toBe(hashReceipt(r0));
    expect(req1.seq).toBe(1n);
  });

  it("signature recovers to client account", async () => {
    const account = privateKeyToAccount(PK_PAYER);
    const client = new Client({ account, verifyingContract: VERIFYING, chainId: 31337 });
    const sessionId = ("0x" + "ab".repeat(32)) as `0x${string}`;
    const req = await client.signRequest({
      sessionId,
      seq: 0n,
      requestHash: keccak256(toHex("req-0")),
      prevReceipt: null,
    });
    // verifyMessage from viem: recover signer from EIP-712 digest.
    const { recoverTypedDataAddress } = await import("viem");
    const recovered = await recoverTypedDataAddress({
      domain: {
        name: "TallyMesh",
        version: "1",
        chainId: 31337,
        verifyingContract: VERIFYING,
      },
      types: {
        SignedRequest: [
          { name: "sessionId", type: "bytes32" },
          { name: "seq", type: "uint64" },
          { name: "requestHash", type: "bytes32" },
          { name: "prevHash", type: "bytes32" },
        ],
      },
      primaryType: "SignedRequest",
      message: {
        sessionId: req.sessionId,
        seq: req.seq,
        requestHash: req.requestHash,
        prevHash: req.prevHash,
      },
      signature: req.signature,
    });
    expect(recovered.toLowerCase()).toBe(account.address.toLowerCase());
  });
});
