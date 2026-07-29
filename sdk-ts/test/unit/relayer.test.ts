import { describe, it, expect } from "vitest";
import { Relayer } from "../../src/index.js";

describe("Relayer (smoke)", () => {
  it("requires walletClient.account", () => {
    const r = new Relayer({} as never, {} as never, ("0x" + "00".repeat(20)) as `0x${string}`);
    expect(() => r.account).toThrow(/walletClient.account is required/);
  });
});
