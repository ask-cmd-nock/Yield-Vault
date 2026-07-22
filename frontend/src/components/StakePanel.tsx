import { useState } from "react";
import {
  useAccount, useReadContract, useReadContracts, useWriteContract, useWaitForTransactionReceipt,
} from "wagmi";
import { ADDRESSES, erc20Abi, stakingAbi, isDeployed, DEFAULT_TIERS } from "../lib/contracts";
import { fmt, parseAmount, fmtDuration } from "../lib/format";

const staking = ADDRESSES.staking as `0x${string}`;
const token = ADDRESSES.utilityToken as `0x${string}`;
const ZERO_ADDR = "0x0000000000000000000000000000000000000000" as const;

export function StakePanel() {
  const { address, isConnected } = useAccount();
  const [input, setInput] = useState("");
  const [tierId, setTierId] = useState(0);

  const deployed = isDeployed(ADDRESSES.staking);
  const { writeContract, data: txHash, isPending, error } = useWriteContract();
  const { isLoading: confirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  const { data: balance } = useReadContract({
    address: token, abi: erc20Abi, functionName: "balanceOf",
    args: [address ?? ZERO_ADDR], query: { enabled: !!address },
  });
  const { data: allowance } = useReadContract({
    address: token, abi: erc20Abi, functionName: "allowance",
    args: [address ?? ZERO_ADDR, staking], query: { enabled: !!address && deployed },
  });
  const { data: tiersLength } = useReadContract({
    address: staking, abi: stakingAbi, functionName: "tiersLength", query: { enabled: deployed },
  });
  const { data: tiers } = useReadContracts({
    contracts: Array.from({ length: Number(tiersLength ?? 0n) }, (_, i) => ({
      address: staking, abi: stakingAbi, functionName: "tiers" as const, args: [BigInt(i)],
    })),
    query: { enabled: deployed && !!tiersLength },
  });
  const { data: positionsLength } = useReadContract({
    address: staking, abi: stakingAbi, functionName: "positionsLength",
    args: [address ?? ZERO_ADDR], query: { enabled: !!address && deployed },
  });
  const { data: positions } = useReadContracts({
    contracts: Array.from({ length: Number(positionsLength ?? 0n) }, (_, i) => ({
      address: staking, abi: stakingAbi, functionName: "positions" as const,
      args: [address ?? ZERO_ADDR, BigInt(i)],
    })),
    query: { enabled: !!address && deployed && !!positionsLength },
  });
  const { data: earnedAll } = useReadContracts({
    contracts: Array.from({ length: Number(positionsLength ?? 0n) }, (_, i) => ({
      address: staking, abi: stakingAbi, functionName: "earned" as const,
      args: [address ?? ZERO_ADDR, BigInt(i)],
    })),
    query: { enabled: !!address && deployed && !!positionsLength, refetchInterval: 15_000 },
  });

  const amount = parseAmount(input, 18);
  const needsApproval = amount !== null && allowance !== undefined && allowance < amount;
  const busy = isPending || confirming;

  function onStake() {
    if (!amount) return;
    if (needsApproval) {
      writeContract({ address: token, abi: erc20Abi, functionName: "approve", args: [staking, amount] });
    } else {
      writeContract({ address: staking, abi: stakingAbi, functionName: "stake", args: [amount, BigInt(tierId)] });
    }
  }

  return (
    <div className="card">
      <h2>Stake TEST</h2>
      <div className="sub">
        Lock the utility token to earn boosted protocol-fee rewards. Longer locks, bigger boost.
      </div>

      {!deployed ? (
        <>
          <div className="tier-grid">
            {DEFAULT_TIERS.map((t, i) => (
              <div key={i} className="tier">
                <div className="t-lock">{t.label}</div>
                <div className="t-boost">{t.multiplier} boost</div>
              </div>
            ))}
          </div>
          <div className="soon">
            <div className="badge">DEPLOYMENT IN PROGRESS</div>
            <p>
              The staking contract ships with the vault. Your TEST balance:{" "}
              <b>{fmt(balance, 18)} TEST</b>
            </p>
          </div>
        </>
      ) : (
        <>
          <div className="tier-grid">
            {(tiers ?? []).map((t, i) => {
              if (t.status !== "success") return null;
              const [lockDuration, multiplierBps, enabled] = t.result as [number, number, boolean];
              if (!enabled) return null;
              return (
                <button key={i} className={`tier ${tierId === i ? "selected" : ""}`} onClick={() => setTierId(i)}>
                  <div className="t-lock">{fmtDuration(Number(lockDuration))}</div>
                  <div className="t-boost">{(Number(multiplierBps) / 10000).toFixed(2)}x boost</div>
                </button>
              );
            })}
          </div>

          <div className="balance-line">
            <span>Available: {fmt(balance, 18)} TEST</span>
            <div className="pct-row">
              {[25, 50, 75, 100].map((pct) => (
                <button
                  key={pct}
                  className="pct-btn"
                  onClick={() => balance !== undefined && setInput(((Number(balance) * pct) / 100 / 1e18).toString())}
                >
                  {pct}%
                </button>
              ))}
            </div>
          </div>
          <div className="amount-box">
            <div className="row">
              <input
                placeholder="0.00"
                value={input}
                inputMode="decimal"
                onChange={(e) => setInput(e.target.value.replace(/[^0-9.]/g, ""))}
              />
              <div className="token-pill"><div className="dot" />TEST</div>
            </div>
          </div>

          <button className="cta" disabled={!isConnected || !amount || busy} onClick={onStake}>
            {busy ? "Confirming…" : !isConnected ? "Connect wallet" : needsApproval ? "Approve TEST" : "Stake"}
          </button>

          {error && <div className="error">{error.message.split("\n")[0]}</div>}
          {isSuccess && txHash && (
            <div className="success">
              Confirmed · <a href={`https://robinhoodchain.blockscout.com/tx/${txHash}`} target="_blank" rel="noreferrer">view on explorer</a>
            </div>
          )}

          {(positions ?? []).some((p) => p.status === "success" && (p.result as readonly bigint[])[0] > 0n) && (
            <div className="positions">
              {(positions ?? []).map((p, i) => {
                if (p.status !== "success") return null;
                const [amt, , unlockAt] = p.result as unknown as [bigint, bigint, bigint];
                if (amt === 0n) return null;
                const unlocked = Number(unlockAt) * 1000 <= Date.now();
                const pending = earnedAll?.[i]?.status === "success" ? (earnedAll[i].result as bigint) : undefined;
                return (
                  <div key={i} className="position">
                    <div>
                      <div className="p-main">{fmt(amt, 18)} TEST</div>
                      <div className="p-sub">
                        {unlocked ? "Unlocked" : `Unlocks ${new Date(Number(unlockAt) * 1000).toLocaleDateString()}`}
                        {" · "}rewards: {fmt(pending, 18)}
                      </div>
                    </div>
                    <div className="p-actions">
                      <button disabled={busy} onClick={() =>
                        writeContract({ address: staking, abi: stakingAbi, functionName: "claim", args: [BigInt(i)] })
                      }>Claim</button>
                      <button disabled={busy || !unlocked} onClick={() =>
                        writeContract({ address: staking, abi: stakingAbi, functionName: "withdraw", args: [BigInt(i)] })
                      }>Withdraw</button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </>
      )}

      <div className="note">
        Boosts apply to reward distribution only — vault shares stay fully fungible.
        Staked tokens are locked until tier maturity; rewards claimable anytime.
      </div>
    </div>
  );
}
