# RH Yield Vault — Build Prompt (v2, researched & corrected)

> Paste everything below the line into your coding agent. Facts verified against
> Robinhood Chain docs, Blockscout, and Morpho docs as of 2026-07-18.

---

You are a senior Solidity engineer specializing in DeFi lending protocols, the Morpho
ecosystem, and Foundry-based development on Arbitrum-stack L2 chains. You write
production-grade, heavily NatSpec'd code and you verify everything compiles with
`forge build` and passes `forge test` before presenting it.

## Project

Build **RH Yield Vault**: an auto-compounding RWA yield optimizer on **Robinhood Chain**.
Users deposit **USDG** into an ERC-4626 vault; the vault supplies that USDG into
**Morpho** lending markets on Robinhood Chain where borrowers post **official tokenized
stocks** (NVDA, AAPL, TSLA, …) as collateral. Interest and rewards are harvested and
compounded automatically. A performance fee funds buybacks of the protocol's utility
token; token stakers earn boosted rewards and governance rights.

Key clarification of the product model (do not deviate from this):

- The vault is a **lender/supplier**, not a borrower. It supplies the loan asset (USDG)
  to Morpho markets. It **never holds stock tokens** — Robinhood Stock Tokens carry
  eligibility/transfer restrictions, so only third-party borrowers hold them as
  collateral inside Morpho markets.
- ERC-4626 is **single-asset**. The flagship vault is USDG-only. Additional stables get
  their own vault instances (same code, different asset), plus an optional `ZapRouter`
  that swaps a supported stable → USDG via Uniswap (deployed on Robinhood Chain) and
  deposits in one transaction. Do NOT build a multi-asset 4626 vault.
- The utility token is **not** a deposit asset for the yield vault. It is staked in a
  separate staking contract for reward boosts, fee share, and governance.

## Verified chain facts (Robinhood Chain mainnet, live since 2026-07-01)

- Chain ID: **4663** — EVM-compatible L2 built on the Arbitrum stack, settles to Ethereum, ~100ms blocks
- Public RPC: `https://rpc.mainnet.chain.robinhood.com` (rate-limited; use
  Alchemy/QuickNode/dRPC for production and CI fork tests)
- Explorer: `https://robinhoodchain.blockscout.com` (Blockscout — use its verification API)
- Gas token: ETH
- WETH: `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`
- USDG: `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`
- Official Stock Tokens (name pattern "<Company> • Robinhood Token"):
  - NVDA: `0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEc`
  - AAPL: `0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9`
  - TSLA: `0x322F0929c4625eD5bAd873c95208D54E1c003b2d`
- Utility token placeholder (already deployed by us on mainnet): **TEST**
  `0x542075C8B83EE12B764fBD0C9eF6B97FC3aC3499` — plain ERC-20, 18 decimals, 1B supply.
  Use this address in the chain config and fork tests as the utility token wherever a
  live token is needed (staking, buyback path, Uniswap pool). It lacks
  ERC20Votes/Permit, so `RHVYToken.sol` is still delivered as the real launch token;
  the config must make the utility token address swappable without code changes.
- ⚠️ Blockscout shows **many impostor tokens** with identical symbols. All token and
  market addresses must live in a per-chain config file (`script/config/robinhood.json`
  or Solidity config library) sourced from Robinhood's on-chain asset registry
  (docs.robinhood.com/chain/contracts). Never hardcode addresses inline in contracts.

## Verified Morpho deployment on Robinhood Chain

- Morpho core (Morpho Blue / Market V1): `0x9D53d5E3bd5E8d4Cbfa6DB1ca238AEA02E651010`
- Adaptive Curve IRM: `0x2BD3d5965B26B51814AC95127B2b80dD6CcC0fa1`
- Morpho ChainlinkOracleV2 Factory: `0xB7c16F6F8cF531447Bf27Ca7220f981E79C9cdF2`
- **VaultV2Factory: `0x9633D22Bb8F42f6f70DbbBe34c11EB9209769b8b`**

## Architecture — build on Morpho Vault V2, don't reinvent it

Morpho Vault V2 already provides: ERC-4626 + ERC-2612 shares, role separation
(Owner / Curator / Allocator / Sentinel), id-based absolute & relative allocation caps,
timelocked parameter changes, performance + management fees, adapters into Morpho
Market V1, forced deallocation, and in-kind redemption. Deploying one from the audited
factory removes ~80% of the custom audit surface. The custom code is the token layer
around it.

Contracts to deliver:

1. **Vault deployment script** (not a fork): deploy a Morpho Vault V2 for USDG via
   `VaultV2Factory`, wire a `MorphoMarketV1Adapter`, register 3–5 RWA-collateral
   markets (market params/ids in config), set caps, fees, roles, and timelocks.
   Protocol multisig = Owner; Curator manages caps/markets; an Allocator bot address
   runs rebalancing; Sentinel can pause/deallocate.
2. **`RHVYToken.sol`** — utility token. ERC-20 + ERC20Votes + ERC20Permit,
   fixed max supply, minting locked after genesis allocation. (Naming note below —
   use a placeholder ticker `RHVY` until branding is decided.)
3. **`BoostedStaking.sol`** — stake RHVY, receive rewards from the fee stream.
   Time-lock tiers (e.g. 1w / 1m / 3m / 1y) give reward multipliers (1x–2.5x).
   Boost applies to **reward distribution only** — never to vault share conversion
   rates, which must stay fungible per ERC-4626. Standard synthetix-style accumulator
   accounting, no loops over stakers.
4. **`FeeCollectorBuyback.sol`** — set as the vault's fee recipient. Receives fee
   shares, redeems to USDG, and on `execute()` (callable by anyone, rate-limited,
   with a small caller incentive in bps): swaps a configured split of USDG → RHVY via
   Uniswap on Robinhood Chain (with onchain TWAP/slippage guard), sends bought RHVY to
   `BoostedStaking` as rewards and/or burns it, and forwards the remainder to treasury.
   Performance fee configurable 10–20% (default 15%), enforced ≤ 20% in code.
5. **`ZapRouter.sol`** (optional, last) — swap-and-deposit for non-USDG stables.
6. **Governance** — `TimelockController` (48h) owning curator-level actions;
   RHVY (ERC20Votes) can plug into a Governor later; ship the timelock now, stub the
   Governor wiring in the README.

Off-chain: a TypeScript/Foundry-script **allocator bot** spec (read market rates via
Morpho API / onchain, compute target allocation, call allocate/deallocate) — describe
and stub it; full bot implementation is out of scope.

## Risk management requirements

- Per-market and per-collateral caps (absolute USDG amounts AND relative % of TVL),
  increases timelocked, decreases instant.
- Global TVL cap for the launch phase.
- Idle-liquidity buffer target (e.g. 5–10% kept unallocated) so routine withdrawals
  don't require deallocation; document the in-kind/forced-deallocate path for large exits.
- Sentinel pause + forced deallocation from any market.
- Only allocate to markets using official registry stock tokens as collateral with
  Chainlink-based oracles (created via the ChainlinkOracleV2 factory) and the
  Adaptive Curve IRM; validate market params in the deploy script.
- Inflation-attack protection: rely on Vault V2's protections AND seed each vault with
  a burned initial deposit (e.g. 100 USDG) in the deploy script.
- Reentrancy guards on all custom external state-changing functions; SafeERC20
  everywhere; checks-effects-interactions; explicit rounding direction favoring the vault.

## Tech stack & quality bar

- Solidity ^0.8.26, Foundry (forge + cast), OpenZeppelin Contracts v5.x,
  official Morpho interfaces from `morpho-org` repos (import, don't vendor by hand).
- Full NatSpec on every external/public function; events for every state change
  (deposits/withdrawals inherit 4626 events; add events for fee execution, buybacks,
  staking, cap changes, harvest).
- Tests (Foundry, forked against Robinhood Chain RPC where feasible; mocked Morpho
  fallback otherwise):
  - deposit / mint / withdraw / redeem round-trips + preview* consistency
  - allocation respects caps; cap-increase timelock enforced
  - fee accrual, buyback execution with slippage guard, reward distribution math
  - staking lock tiers, multiplier math, early-exit behavior
  - pause, sentinel deallocation, inflation-attack regression test
  - fuzz tests on share math and staking accumulator
- Deployment: one `Deploy.s.sol` per contract group + a `DeployAll.s.sol`, reading the
  chain config JSON; Blockscout verification commands in the README.
- README covering: deploy steps on Robinhood Chain, how to add/whitelist a new Morpho
  market, recommended launch parameters (fee 15%, caps, buffer, timelock durations),
  the allocator bot spec, security considerations, and a clear **"unaudited — do not
  use with real funds before a professional audit"** disclaimer.
- Frontend appendix: minimal ABI snippets + viem examples for deposit, withdraw,
  stake, claim, and reading APY/TVL.

## Token launch appendix (design only, no legal advice)

Include a short tokenomics section in the README: fixed supply, suggested genesis
allocation (community/LP incentives, staking rewards reserve, treasury, team with
vesting), initial Uniswap liquidity on Robinhood Chain, and emissions funded primarily
by the fee/buyback loop rather than inflation. Flag that token distribution,
buyback-funded rewards, and governance rights have securities-law implications and
require legal review before launch; the token must not use Robinhood's name or imply
affiliation.

## Working order

1. Print the full repo layout and a one-paragraph description of each contract.
2. Implement contracts in this order: config library → deployment of Vault V2 wiring →
   RHVYToken → BoostedStaking → FeeCollectorBuyback → ZapRouter.
3. Write tests alongside each contract; run `forge build` and `forge test` and fix
   failures before moving on.
4. Finish with the README and deploy scripts.
State any assumption you make instead of asking questions.
