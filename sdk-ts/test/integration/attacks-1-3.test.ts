import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { type ChildProcess } from "node:child_process";
import {
  ANVIL_KEYS, deploy, publicClient, startAnvil, walletClientFor,
} from "./_setup.js";
import {
  Client, Service, KeccakAggregator, Settlement, ServiceError,
} from "../../src/index.js";
import { batchSettlementAbi } from "../../src/abis.js";
import { keccak256, toHex, parseEther } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import type { AddressBook } from "../../src/addresses.js";

let anvil: ChildProcess;
let addrs: AddressBook;

beforeAll(async () => {
  anvil = await startAnvil();
  addrs = deploy();
}, 120_000);

afterAll(() => { if (anvil) anvil.kill(); });

const SESSION = ("0x" + "12".repeat(32)) as `0x${string}`;
const BATCH   = ("0x" + "34".repeat(32)) as `0x${string}`;
const ZERO    = ("0x" + "00".repeat(32)) as `0x${string}`;
const BLOB_HASH = ("0x" + "01".repeat(32)) as `0x${string}`;

describe("Attacks 1 + 3 closure (sdk-ts + on-chain backstop)", () => {
  it("Attack 1: replay of same SignedRequest is rejected by service AND ReceiptAlreadyClaimed on chain", async () => {
    const pub = publicClient();
    const deployerW = walletClientFor(ANVIL_KEYS.deployer);
    const payerW    = walletClientFor(ANVIL_KEYS.payer);
    const submW     = walletClientFor(ANVIL_KEYS.submitter);

    await deployerW.writeContract({
      address: addrs.BatchSettlement, abi: batchSettlementAbi,
      functionName: "setAuthorizedSubmitter",
      args: [privateKeyToAccount(ANVIL_KEYS.submitter).address, true],
    });
    await deployerW.writeContract({
      address: addrs.BatchSettlement, abi: batchSettlementAbi,
      functionName: "setChallengeWindow", args: [1n],
    });
    await deployerW.writeContract({
      address: addrs.BatchSettlement, abi: batchSettlementAbi,
      functionName: "setChargedCeiling", args: [parseEther("1")],
    });
    const settlementSubmitter = new Settlement({
      publicClient: pub, walletClient: submW,
      batchSettlement: addrs.BatchSettlement, depositEscrow: addrs.DepositEscrow,
    });
    await settlementSubmitter.bond(parseEther("1"));
    const settlementPayer = new Settlement({
      publicClient: pub, walletClient: payerW,
      batchSettlement: addrs.BatchSettlement, depositEscrow: addrs.DepositEscrow,
    });
    const recipient = privateKeyToAccount(ANVIL_KEYS.service).address;
    await settlementPayer.deposit(parseEther("1"));
    await settlementPayer.reserveSession(SESSION, recipient, parseEther("0.5"));

    const client = new Client({
      account: privateKeyToAccount(ANVIL_KEYS.payer),
      verifyingContract: addrs.BatchSettlement, chainId: 31337,
    });
    const service = new Service({
      account: privateKeyToAccount(ANVIL_KEYS.service),
      verifyingContract: addrs.BatchSettlement, chainId: 31337,
    });
    const req0 = await client.signRequest({
      sessionId: SESSION, seq: 0n, requestHash: keccak256(toHex("req-0")), prevReceipt: null,
    });
    const r0 = await service.handle(req0, {
      chargedAmount: parseEther("0.05"), resultHash: keccak256(toHex("res-0")),
    });

    // Service-level Attack 1 closure.
    let serviceErrorKind: string | null = null;
    try {
      await service.handle(req0, { chargedAmount: parseEther("0.05"), resultHash: keccak256(toHex("res-0")) });
    } catch (e) {
      if (e instanceof ServiceError) serviceErrorKind = e.kind;
    }
    expect(serviceErrorKind).toBe("SeqOutOfOrder");

    // Build a single-receipt batch and run the on-chain claim path twice.
    const agg = new KeccakAggregator([r0.receipt]);
    await settlementSubmitter.submitOptimisticBatch({
      batchId: BATCH, receiptsRoot: agg.root, deltasRoot: ZERO, receiptCount: 1n, expectedBlobHash: BLOB_HASH,
    });
    await fetch("http://127.0.0.1:8545", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "evm_increaseTime", params: [5] }),
    });
    await fetch("http://127.0.0.1:8545", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 2, method: "evm_mine", params: [] }),
    });
    await settlementPayer.finalizeBatch(BATCH);
    await settlementPayer.claimPayout(BATCH, r0.receipt, agg.proofFor(0));
    // Second claim must revert with ReceiptAlreadyClaimed.
    await expect(
      settlementPayer.claimPayout(BATCH, r0.receipt, agg.proofFor(0)),
    ).rejects.toThrow(/ReceiptAlreadyClaimed/);
  }, 180_000);

  it("Attack 3: out-of-order seq is rejected by service before any chain interaction", async () => {
    const client = new Client({
      account: privateKeyToAccount(ANVIL_KEYS.payer),
      verifyingContract: addrs.BatchSettlement, chainId: 31337,
    });
    const service = new Service({
      account: privateKeyToAccount(ANVIL_KEYS.service),
      verifyingContract: addrs.BatchSettlement, chainId: 31337,
    });
    const session2 = ("0x" + "56".repeat(32)) as `0x${string}`;
    const req0 = await client.signRequest({
      sessionId: session2, seq: 0n, requestHash: keccak256(toHex("a")), prevReceipt: null,
    });
    await service.handle(req0, { chargedAmount: 1n, resultHash: keccak256(toHex("a")) });

    // Skip seq=1; client signs seq=2 referencing the receipt-0 hash.
    const r0_local = await (async () => {
      const tmp = new Service({
        account: privateKeyToAccount(ANVIL_KEYS.service),
        verifyingContract: addrs.BatchSettlement, chainId: 31337,
      });
      const fresh = await client.signRequest({
        sessionId: session2, seq: 0n, requestHash: keccak256(toHex("a")), prevReceipt: null,
      });
      return tmp.handle(fresh, { chargedAmount: 1n, resultHash: keccak256(toHex("a")) });
    })();
    const req2 = await client.signRequest({
      sessionId: session2, seq: 2n, requestHash: keccak256(toHex("c")),
      prevReceipt: r0_local.receipt,
    });
    let kind: string | null = null;
    try {
      await service.handle(req2, { chargedAmount: 1n, resultHash: keccak256(toHex("c")) });
    } catch (e) { if (e instanceof ServiceError) kind = e.kind; }
    expect(kind).toBe("SeqOutOfOrder");
  });
});
