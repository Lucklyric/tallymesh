import { describe, it, expect } from "vitest";
import { privateKeyToAccount } from "viem/accounts";
import { keccak256, toHex } from "viem";
import { Client } from "../../src/client.js";
import { Service, ServiceError } from "../../src/service.js";

const PK_PAYER = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as const;
const PK_SVC   = "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a" as const;
const VERIFYING = "0x5FbDB2315678afecb367f032d93F642f64180aa3" as const;

const SESSION = ("0x" + "ab".repeat(32)) as `0x${string}`;

function newClient() {
  return new Client({
    account: privateKeyToAccount(PK_PAYER),
    verifyingContract: VERIFYING,
    chainId: 31337,
  });
}
function newService() {
  return new Service({
    account: privateKeyToAccount(PK_SVC),
    verifyingContract: VERIFYING,
    chainId: 31337,
  });
}

describe("Service (request handler + receipt signer)", () => {
  it("accepts the first request (seq=0, prevHash=0) and signs a receipt", async () => {
    const client = newClient();
    const service = newService();
    const req = await client.signRequest({
      sessionId: SESSION,
      seq: 0n,
      requestHash: keccak256(toHex("req-0")),
      prevReceipt: null,
    });
    const r = await service.handle(req, { chargedAmount: 1_000n, resultHash: keccak256(toHex("res-0")) });
    expect(r.receipt.seq).toBe(0n);
    expect(r.receipt.chargedAmount).toBe(1_000n);
    expect(r.signer).toBe(privateKeyToAccount(PK_SVC).address);
  });

  it("REJECTS replay of an already-handled SignedRequest (Attack 1)", async () => {
    const client = newClient();
    const service = newService();
    const req = await client.signRequest({
      sessionId: SESSION,
      seq: 0n,
      requestHash: keccak256(toHex("req-0")),
      prevReceipt: null,
    });
    await service.handle(req, { chargedAmount: 1_000n, resultHash: keccak256(toHex("res-0")) });
    await expect(
      service.handle(req, { chargedAmount: 1_000n, resultHash: keccak256(toHex("res-0")) }),
    ).rejects.toMatchObject({
      name: "ServiceError",
      kind: "SeqOutOfOrder",
    });
  });

  it("REJECTS out-of-order seq (Attack 3): client jumps from 0 to 2", async () => {
    const client = newClient();
    const service = newService();
    const req0 = await client.signRequest({
      sessionId: SESSION, seq: 0n, requestHash: keccak256(toHex("req-0")), prevReceipt: null,
    });
    await service.handle(req0, { chargedAmount: 1_000n, resultHash: keccak256(toHex("res-0")) });
    // Skip seq=1; sign seq=2 with the correct prevHash, but jump in seq.
    // Forge an out-of-order seq=2 request whose prevHash uses receipt[0].
    const r0_real = await (async () => {
      const newSvc = newService();
      const req0fresh = await client.signRequest({
        sessionId: SESSION, seq: 0n, requestHash: keccak256(toHex("req-0")), prevReceipt: null,
      });
      return newSvc.handle(req0fresh, { chargedAmount: 1_000n, resultHash: keccak256(toHex("res-0")) });
    })();
    const req2 = await client.signRequest({
      sessionId: SESSION, seq: 2n, requestHash: keccak256(toHex("req-2")),
      prevReceipt: r0_real.receipt,
    });
    await expect(
      service.handle(req2, { chargedAmount: 1_000n, resultHash: keccak256(toHex("res-2")) }),
    ).rejects.toMatchObject({
      name: "ServiceError",
      kind: "SeqOutOfOrder",
    });
  });

  it("REJECTS prevHash mismatch (forked transcript): seq is right but prevHash is wrong", async () => {
    const client = newClient();
    const service = newService();
    const req0 = await client.signRequest({
      sessionId: SESSION, seq: 0n, requestHash: keccak256(toHex("req-0")), prevReceipt: null,
    });
    await service.handle(req0, { chargedAmount: 1_000n, resultHash: keccak256(toHex("res-0")) });
    // Craft a SignedRequest at seq=1 but with prevHash referencing a fake receipt.
    const fake = {
      sessionId: SESSION, seq: 99n, requestHash: keccak256(toHex("ghost")),
      resultHash: keccak256(toHex("ghost")), chargedAmount: 0n,
      statusCode: ("0x" + "00".repeat(32)) as `0x${string}`,
      serviceTimestamp: 0n,
    } as const;
    const req1bad = await client.signRequest({
      sessionId: SESSION, seq: 1n, requestHash: keccak256(toHex("req-1")),
      prevReceipt: fake,
    });
    await expect(
      service.handle(req1bad, { chargedAmount: 1_000n, resultHash: keccak256(toHex("res-1")) }),
    ).rejects.toMatchObject({
      name: "ServiceError",
      kind: "PrevHashMismatch",
    });
  });

  it("REJECTS forged signer (signature does not recover)", async () => {
    const client = newClient();
    const service = newService();
    const req = await client.signRequest({
      sessionId: SESSION, seq: 0n, requestHash: keccak256(toHex("req-0")), prevReceipt: null,
    });
    // Tamper with declared signer to a different address
    const tampered = { ...req, signer: ("0x" + "99".repeat(20)) as `0x${string}` };
    await expect(
      service.handle(tampered, { chargedAmount: 1_000n, resultHash: keccak256(toHex("res-0")) }),
    ).rejects.toMatchObject({
      name: "ServiceError",
      kind: "BadSignature",
    });
  });

  it("ServiceError is the canonical error class", () => {
    const e = new ServiceError("BadSignature", "test");
    expect(e.name).toBe("ServiceError");
    expect(e.kind).toBe("BadSignature");
  });
});
