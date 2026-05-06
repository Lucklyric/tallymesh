// Hand-rolled minimal ABIs. We deliberately do NOT import Foundry artifacts,
// to keep the SDK independent of the contracts build directory.

export const depositEscrowAbi = [
  { type: "function", name: "deposit", stateMutability: "payable", inputs: [], outputs: [] },
  {
    type: "function", name: "balanceOf", stateMutability: "view",
    inputs: [{ name: "payer", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

export const batchSettlementAbi = [
  {
    type: "function", name: "bond", stateMutability: "payable", inputs: [], outputs: [],
  },
  {
    type: "function", name: "setAuthorizedSubmitter", stateMutability: "nonpayable",
    inputs: [{ name: "submitter", type: "address" }, { name: "authorized", type: "bool" }],
    outputs: [],
  },
  {
    type: "function", name: "setChallengeWindow", stateMutability: "nonpayable",
    inputs: [{ name: "window", type: "uint64" }], outputs: [],
  },
  {
    type: "function", name: "setChargedCeiling", stateMutability: "nonpayable",
    inputs: [{ name: "newCeiling", type: "uint256" }], outputs: [],
  },
  {
    type: "function", name: "reserveSession", stateMutability: "nonpayable",
    inputs: [
      { name: "sessionId", type: "bytes32" },
      { name: "recipient", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function", name: "submitOptimisticBatch", stateMutability: "nonpayable",
    inputs: [
      { name: "batchId", type: "bytes32" },
      { name: "receiptsRoot", type: "bytes32" },
      { name: "deltasRoot", type: "bytes32" },
      { name: "receiptCount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function", name: "submitZkBatch", stateMutability: "nonpayable",
    inputs: [
      { name: "batchId", type: "bytes32" },
      { name: "receiptsRoot", type: "bytes32" },
      { name: "deltasRoot", type: "bytes32" },
      { name: "receiptCount", type: "uint256" },
      { name: "verifier", type: "address" },
      { name: "proof", type: "bytes" },
    ],
    outputs: [],
  },
  {
    type: "function", name: "finalizeBatch", stateMutability: "nonpayable",
    inputs: [{ name: "batchId", type: "bytes32" }], outputs: [],
  },
  {
    type: "function", name: "claimPayout", stateMutability: "nonpayable",
    inputs: [
      { name: "batchId", type: "bytes32" },
      {
        name: "receipt", type: "tuple",
        components: [
          { name: "sessionId", type: "bytes32" },
          { name: "seq", type: "uint64" },
          { name: "requestHash", type: "bytes32" },
          { name: "resultHash", type: "bytes32" },
          { name: "chargedAmount", type: "uint256" },
          { name: "statusCode", type: "bytes32" },
          { name: "serviceTimestamp", type: "uint64" },
        ],
      },
      { name: "proof", type: "bytes32[]" },
    ],
    outputs: [],
  },
  {
    type: "function", name: "challengeWindow", stateMutability: "view",
    inputs: [], outputs: [{ name: "", type: "uint64" }],
  },
  // Custom errors — declared so viem can decode revert reasons by name.
  { type: "error", name: "ReceiptAlreadyClaimed", inputs: [] },
] as const;
