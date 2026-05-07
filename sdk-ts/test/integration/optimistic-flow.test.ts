import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { type ChildProcess } from "node:child_process";
import {
  ANVIL_KEYS, deploy, publicClient, startAnvil, walletClientFor,
} from "./_setup.js";
import {
  Client, Service, KeccakAggregator, Settlement,
} from "../../src/index.js";
import { batchSettlementAbi, depositEscrowAbi } from "../../src/abis.js";
import { keccak256, toHex, parseEther } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import type { AddressBook } from "../../src/addresses.js";
import type { Receipt } from "../../src/types.js";

let anvil: ChildProcess;
let addrs: AddressBook;

beforeAll(async () => {
  anvil = await startAnvil();
  addrs = deploy();
}, 120_000);

afterAll(() => { if (anvil) anvil.kill(); });

const SESSION = ("0x" + "ab".repeat(32)) as `0x${string}`;
const BATCH   = ("0x" + "cd".repeat(32)) as `0x${string}`;
const ZERO    = ("0x" + "00".repeat(32)) as `0x${string}`;
const BLOB_HASH = ("0x" + "01".repeat(32)) as `0x${string}`;

describe("E2E optimistic flow", () => {
  it("client signs requests, service issues receipts, aggregator builds batch, claim transfers ETH", async () => {
    const pub = publicClient();
    const deployerW = walletClientFor(ANVIL_KEYS.deployer);
    const payerW    = walletClientFor(ANVIL_KEYS.payer);
    const submW     = walletClientFor(ANVIL_KEYS.submitter);

    // 1. Owner authorizes submitter, sets challenge window to 1s, sets chargedCeiling to 1 ether.
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

    // 2. Submitter bonds.
    const settlementSubmitter = new Settlement({
      publicClient: pub, walletClient: submW,
      batchSettlement: addrs.BatchSettlement, depositEscrow: addrs.DepositEscrow,
    });
    await settlementSubmitter.bond(parseEther("1"));

    // 3. Payer deposits + reserves session.
    const settlementPayer = new Settlement({
      publicClient: pub, walletClient: payerW,
      batchSettlement: addrs.BatchSettlement, depositEscrow: addrs.DepositEscrow,
    });
    const recipient = privateKeyToAccount(ANVIL_KEYS.service).address;
    await settlementPayer.deposit(parseEther("1"));
    await settlementPayer.reserveSession(SESSION, recipient, parseEther("0.5"));

    // 4. Client + service exchange three signed requests/receipts.
    const client = new Client({
      account: privateKeyToAccount(ANVIL_KEYS.payer),
      verifyingContract: addrs.BatchSettlement, chainId: 31337,
    });
    const service = new Service({
      account: privateKeyToAccount(ANVIL_KEYS.service),
      verifyingContract: addrs.BatchSettlement, chainId: 31337,
    });
    const receipts: Receipt[] = [];
    let prev = null as null | Receipt;
    for (let i = 0n; i < 3n; i++) {
      const req = await client.signRequest({
        sessionId: SESSION, seq: i,
        requestHash: keccak256(toHex(`req-${i}`)), prevReceipt: prev,
      });
      const r = await service.handle(req, {
        chargedAmount: parseEther("0.05"),
        resultHash: keccak256(toHex(`res-${i}`)),
      });
      receipts.push(r.receipt);
      prev = r.receipt;
    }

    // 5. Aggregator builds the optimistic batch.
    const agg = new KeccakAggregator(receipts);

    // 6. Submitter posts the batch.
    await settlementSubmitter.submitOptimisticBatch({
      batchId: BATCH,
      receiptsRoot: agg.root,
      deltasRoot: ZERO,
      receiptCount: BigInt(receipts.length),
      expectedBlobHash: BLOB_HASH,
    });

    // 7. Wait out the 1s challenge window, then finalize.
    await new Promise((r) => setTimeout(r, 2_000));
    // viem-foundry: bump anvil time so finalize sees a future timestamp.
    await fetch("http://127.0.0.1:8545", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "evm_increaseTime", params: [10] }),
    });
    await fetch("http://127.0.0.1:8545", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 2, method: "evm_mine", params: [] }),
    });
    await settlementPayer.finalizeBatch(BATCH);

    // 8. Claim each receipt; service balance grows by 0.05 ETH per receipt.
    const before = await pub.getBalance({ address: recipient });
    for (let i = 0; i < receipts.length; i++) {
      const proof = agg.proofFor(i);
      await settlementPayer.claimPayout(BATCH, receipts[i]!, proof);
    }
    const after = await pub.getBalance({ address: recipient });
    expect(after - before).toBe(parseEther("0.15"));
  }, 180_000);
});
