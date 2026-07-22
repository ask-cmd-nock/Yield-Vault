# RH Yield Vault

An RWA yield optimizer for **Robinhood Chain** (chain ID 4663). Users deposit **USDG**
into a [Morpho Vault V2](https://docs.morpho.org/learn/concepts/vault-v2/) that supplies
liquidity to Morpho lending markets collateralized by official Robinhood **Stock Tokens**
(NVDA, AAPL, TSLA, …). A 15% performance fee is harvested into utility-token buybacks:
part burned, part streamed to token stakers, remainder to the treasury.

> ⚠️ **Unaudited code. Do not use with real funds before a professional audit.**
> The utility token here is a placeholder ("RHVY" / the TEST token). Do not ship any
> token or product name that uses or implies the Robinhood trademark. Token
> distribution, buyback-funded rewards, and governance rights carry securities-law
> implications — get legal review before launch.

## Architecture

```
depositors ──USDG──► Morpho Vault V2 (ERC-4626, deployed from official factory)
                        │  MorphoMarketV1AdapterV2
                        ▼
              Morpho markets (USDG lent vs. NVDA/AAPL/TSLA collateral)
                        │  15% performance fee (fee shares)
                        ▼
              FeeCollectorBuyback ──► caller incentive (0.1%)
                        ├──► 50% USDG → swap → utility token ──► 20% burned
                        │                                   └──► 80% → BoostedStaking rewards
                        └──► 50% USDG → treasury
users ──stables──► ZapRouter ──USDG──► vault (one tx)
stakers ──utility token──► BoostedStaking (lock tiers 1w/1m/3m/1y → 1x–2.5x reward boost)
```

Design invariants:

- **The vault never holds stock tokens.** It is a lender; borrowers hold the RWA
  collateral inside Morpho markets. (Robinhood Stock Tokens are transfer-restricted.)
- **ERC-4626 stays single-asset and fungible.** Multi-stable support is a ZapRouter
  concern; staking boosts affect reward weight only, never vault share pricing.
- **All addresses are config, not code** — `script/config/robinhood.json` — because
  Blockscout shows dozens of impostor tokens reusing official stock symbols.

### Contracts

| Contract | Purpose |
|---|---|
| Morpho Vault V2 (factory-deployed, not in this repo) | The user-facing ERC-4626 vault: caps, timelocks, roles, fees |
| `src/token/RHVYToken.sol` | Fixed-supply utility token (ERC20 + Permit + Votes) |
| `src/staking/BoostedStaking.sol` | Lock-tier staking, synthetix-style reward stream |
| `src/fees/FeeCollectorBuyback.sol` | Vault fee recipient → harvest → buyback/burn/reward/treasury |
| `src/router/ZapRouter.sol` | Any supported stable → USDG → vault deposit in one tx |

### Verified chain addresses (mainnet, July 2026)

| What | Address |
|---|---|
| USDG | `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` |
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |
| Utility token placeholder (TEST) | `0x542075C8B83EE12B764fBD0C9eF6B97FC3aC3499` |
| Morpho core | `0x9D53d5E3bd5E8d4Cbfa6DB1ca238AEA02E651010` |
| Adaptive Curve IRM | `0x2BD3d5965B26B51814AC95127B2b80dD6CcC0fa1` |
| Chainlink Oracle V2 factory | `0xB7c16F6F8cF531447Bf27Ca7220f981E79C9cdF2` |
| Vault V2 factory | `0x9633D22Bb8F42f6f70DbbBe34c11EB9209769b8b` |
| NVDA / AAPL / TSLA | see `script/config/robinhood.json` |

Two config values still need filling in before mainnet deploy (check
[docs.morpho.org addresses](https://docs.morpho.org/get-started/resources/addresses/) and
Robinhood Chain docs): `morphoMarketV1AdapterV2Factory` and `swapRouter` (Uniswap on
Robinhood Chain). If the deployed router is SwapRouter02 (no `deadline` field), adjust
`ISwapRouterV3` accordingly.

## Build & test

```bash
forge build
forge test          # 30 tests, unit + fuzz, all green
```

RPC: public endpoint `https://rpc.mainnet.chain.robinhood.com` is rate-limited — use a
dedicated provider (Alchemy/QuickNode/dRPC) for deploys and fork tests.

## Deploy (order matters)

```bash
export ETH_RPC_URL=<dedicated Robinhood Chain RPC>
# 1. Utility token (skip while using TEST as placeholder)
TREASURY=0x... forge script script/DeployToken.s.sol --rpc-url robinhood --broadcast
#    → update `utilityToken` in script/config/robinhood.json

# 2. Vault V2 + adapter + markets + caps + fee
OWNER=0x... CURATOR=0x... ALLOCATOR=0x... SENTINEL=0x... \
FEE_RECIPIENT=<FeeCollectorBuyback, or deployer temporarily> \
forge script script/DeployVaultV2.s.sol --rpc-url robinhood --broadcast

# 3. Staking + fee collector + zap, wired together
VAULT=<vault from step 2> TREASURY=0x... OWNER=0x... \
forge script script/DeployPeriphery.s.sol --rpc-url robinhood --broadcast
#    → then have the curator submit setPerformanceFeeRecipient(<collector>) if step 2
#      used a temporary recipient, and OWNER must acceptOwnership() on both contracts.
```

Verification on Blockscout: add
`--verify --verifier blockscout --verifier-url https://robinhoodchain.blockscout.com/api/`.

### Adding a Morpho market

Append to `markets` in `script/config/robinhood.json` (fields **alphabetical** — the
script's JSON decoder requires it):

```json
{
  "absoluteCap": 250000000000,
  "collateralToken": "0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEc",
  "collateralTokenAbsoluteCap": 500000000000,
  "irm": "0x2BD3d5965B26B51814AC95127B2b80dD6CcC0fa1",
  "lltv": 625000000000000000,
  "loanToken": "0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168",
  "oracle": "<ChainlinkOracleV2 for NVDA/USDG>",
  "relativeCapWad": 300000000000000000
}
```

(caps in USDG 6-decimal units; `lltv`/`relativeCapWad` in WAD). On a live vault, cap
increases go through the curator `submit()` flow and wait out the 2-day timelock; cap
*decreases* and sentinel `deallocate` are immediate.

### Recommended launch parameters

| Parameter | Value |
|---|---|
| Performance fee | 15% (hard policy cap 20% in the deploy script) |
| Per-market absolute cap | start small (e.g. 250k USDG), raise via timelock |
| Per-collateral relative cap | ≤ 30% of TVL |
| Global TVL | implicit via sum of absolute caps during launch phase |
| Idle liquidity buffer | allocator keeps 5–10% unallocated |
| Buyback split | 50% buyback / 50% treasury; 20% of buyback burned |
| Fee harvest | keeper bot calls `execute(minOut)` every 6–24h with a fresh off-chain quote |
| Timelocks | 2 days on cap increases, adapter adds, fee changes |
| Staking tiers | 1w×1.0 / 1m×1.25 / 3m×1.5 / 1y×2.5 |

## Roles

- **Owner** (multisig): vault ownership, periphery admin, keeper set, params.
- **Curator** (multisig/timelock): caps, adapters, fees — all behind `submit()` + timelock.
- **Allocator** (bot): moves USDG between markets; keeps the liquidity buffer. Reads
  market rates (Morpho API or on-chain), calls `vault.allocate/deallocate(adapter, abi.encode(marketParams), assets)`.
- **Sentinel** (guardian): can force-deallocate and de-risk immediately.
- **Keeper**: calls `FeeCollectorBuyback.execute(minBuybackOut)`; gated so the swap's
  slippage floor can't be griefed to zero. A permissionless TWAP-guarded variant is a
  planned upgrade.

## Security notes

- Morpho Vault V2 core is audited & factory-deployed; this repo's custom periphery
  (token, staking, fee collector, zap) is **not audited**.
- Inflation attack: Vault V2 uses virtual shares; the deploy script additionally burns a
  100 USDG seed deposit to the dead address.
- `BoostedStaking` excludes staked principal from the reward budget when staking and
  reward tokens are the same; withdraw/claim are never pausable.
- `FeeCollectorBuyback.rescue` is an owner escape hatch — keep owner behind the timelock.
- Stock-token markets share equity-market risk: prices gap over weekends/halts even if
  the oracle is live. Keep LLTVs conservative and per-collateral caps low.

## Frontend snippets (viem)

```ts
const vault = { address: VAULT, abi: erc4626Abi }; // standard ERC-4626 ABI

// deposit USDG
await usdg.write.approve([VAULT, amount]);
await client.writeContract({ ...vault, functionName: "deposit", args: [amount, user] });

// read position + vault stats
const shares = await client.readContract({ ...vault, functionName: "balanceOf", args: [user] });
const assets = await client.readContract({ ...vault, functionName: "convertToAssets", args: [shares] });
const tvl    = await client.readContract({ ...vault, functionName: "totalAssets" });

// stake utility token, tier 3 = 1y lock 2.5x boost
await client.writeContract({ address: STAKING, abi: stakingAbi, functionName: "stake", args: [amount, 3n] });
// claim rewards on position 0
await client.writeContract({ address: STAKING, abi: stakingAbi, functionName: "claim", args: [0n] });
```

## Tokenomics sketch (placeholder — legal review required)

Fixed 1B supply: 40% community & LP incentives (4y emission), 25% treasury, 20% staking
rewards reserve, 15% team (1y cliff + 3y vest). Ongoing staker rewards are funded by the
fee buyback loop, not inflation. Seed a utility-token/USDG Uniswap pool at launch so the
buyback leg has liquidity (during testing: seed a small TEST/USDG pool).
