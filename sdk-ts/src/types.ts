// Pure data types; no chain or signing logic here.
export type Hex32 = `0x${string}`; // 32-byte hex string
export type Hex = `0x${string}`;
export type Address = `0x${string}`;

export interface SessionIntent {
  sessionId: Hex32;
  payer: Address;
  recipient: Address;
  maxAmount: bigint;
  expiresAt: bigint;
}

export interface SignedRequest {
  sessionId: Hex32;
  seq: bigint;
  requestHash: Hex32;
  prevHash: Hex32; // 0x00..00 for the first request in a session
  signature: Hex;  // 65-byte EOA signature OR ERC-1271 wrapper
  signer: Address; // declared signer; on-chain validation binds this
}

export interface Receipt {
  sessionId: Hex32;
  seq: bigint;
  requestHash: Hex32;
  resultHash: Hex32;
  chargedAmount: bigint;
  statusCode: Hex32;
  serviceTimestamp: bigint;
}

export interface SignedReceipt {
  receipt: Receipt;
  signature: Hex;
  signer: Address;
}

export interface BatchHeader {
  batchId: Hex32;
  receiptsRoot: Hex32;
  deltasRoot: Hex32;
  receiptCount: bigint;
}
