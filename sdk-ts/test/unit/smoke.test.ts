import { describe, it, expect } from "vitest";
import { SDK_VERSION } from "../../src/index.js";

describe("sdk smoke", () => {
  it("exposes a version string", () => {
    expect(SDK_VERSION).toBe("0.0.1");
  });
});
