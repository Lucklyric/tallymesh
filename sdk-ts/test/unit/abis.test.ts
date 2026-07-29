// test/unit/abis.test.ts
import { describe, it, expect } from "vitest";
import { batchSettlementAbi, depositEscrowAbi } from "../../src/abis.js";

describe("ABI fragments", () => {
  it("BatchSettlement ABI has the functions the SDK uses", () => {
    const names = batchSettlementAbi.filter((x) => x.type === "function").map((x) => x.name).sort();
    expect(names).toEqual(
      [
        "bond", "challengeWindow", "claimPayout", "finalizeBatch",
        "reserveSession", "reserveSessionWithIntent",
        "setAuthorizedSubmitter", "setChallengeWindow",
        "setChargedCeiling", "submitOptimisticBatch", "submitZkBatch",
      ].sort(),
    );
  });
  it("DepositEscrow ABI has deposit + balanceOf", () => {
    const names = depositEscrowAbi.filter((x) => x.type === "function").map((x) => x.name).sort();
    expect(names).toEqual(["balanceOf", "deposit"]);
  });
});
