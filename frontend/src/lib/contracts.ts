// Deployed addresses on Robinhood Chain (4663).
// Zero address = not deployed yet; the UI renders a "coming soon" state for it.
export const ADDRESSES = {
  usdg: "0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168",
  utilityToken: "0x542075C8B83EE12B764fBD0C9eF6B97FC3aC3499", // TEST (placeholder for RHVY)
  vault: "0x0000000000000000000000000000000000000000",
  staking: "0x0000000000000000000000000000000000000000",
} as const;

export const ZERO = "0x0000000000000000000000000000000000000000";
export const isDeployed = (a: string) => a !== ZERO;

export const erc20Abi = [
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "a", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "decimals", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ name: "o", type: "address" }, { name: "s", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ name: "s", type: "address" }, { name: "v", type: "uint256" }], outputs: [{ type: "bool" }] },
] as const;

export const vaultAbi = [
  ...erc20Abi,
  { type: "function", name: "totalAssets", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "convertToAssets", stateMutability: "view", inputs: [{ name: "shares", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "deposit", stateMutability: "nonpayable", inputs: [{ name: "assets", type: "uint256" }, { name: "receiver", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "withdraw", stateMutability: "nonpayable", inputs: [{ name: "assets", type: "uint256" }, { name: "receiver", type: "address" }, { name: "owner", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "maxWithdraw", stateMutability: "view", inputs: [{ name: "owner", type: "address" }], outputs: [{ type: "uint256" }] },
] as const;

export const stakingAbi = [
  { type: "function", name: "stake", stateMutability: "nonpayable", inputs: [{ name: "amount", type: "uint256" }, { name: "tierId", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "withdraw", stateMutability: "nonpayable", inputs: [{ name: "positionId", type: "uint256" }], outputs: [] },
  { type: "function", name: "claim", stateMutability: "nonpayable", inputs: [{ name: "positionId", type: "uint256" }], outputs: [] },
  { type: "function", name: "earned", stateMutability: "view", inputs: [{ name: "user", type: "address" }, { name: "positionId", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "totalStaked", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "positionsLength", stateMutability: "view", inputs: [{ name: "user", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "positions", stateMutability: "view", inputs: [{ name: "user", type: "address" }, { name: "id", type: "uint256" }], outputs: [
    { name: "amount", type: "uint128" }, { name: "weight", type: "uint128" }, { name: "unlockAt", type: "uint64" },
    { name: "rewardPerWeightPaid", type: "uint256" }, { name: "rewards", type: "uint256" },
  ] },
  { type: "function", name: "tiersLength", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "tiers", stateMutability: "view", inputs: [{ name: "id", type: "uint256" }], outputs: [
    { name: "lockDuration", type: "uint32" }, { name: "multiplierBps", type: "uint32" }, { name: "enabled", type: "bool" },
  ] },
] as const;

// Mirrors the tiers BoostedStaking creates in its constructor; used for preview
// while the staking contract is not deployed yet.
export const DEFAULT_TIERS = [
  { label: "1 week", multiplier: "1.00x" },
  { label: "1 month", multiplier: "1.25x" },
  { label: "3 months", multiplier: "1.50x" },
  { label: "1 year", multiplier: "2.50x" },
];
