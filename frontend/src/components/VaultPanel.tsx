import { useState } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { ADDRESSES, erc20Abi, vaultAbi, isDeployed } from "../lib/contracts";
import { fmt, parseAmount } from "../lib/format";

const USDG_DECIMALS = 6;
const vault = ADDRESSES.vault as `0x${string}`;
const usdg = ADDRESSES.usdg as `0x${string}`;

export function VaultPanel() {
  const { address, isConnected } = useAccount();
  const [mode, setMode] = useState<"deposit" | "withdraw">("deposit");
  const [input, setInput] = useState("");

  const deployed = isDeployed(ADDRESSES.vault);
  const { writeContract, data: txHash, isPending, error } = useWriteContract();
  const { isLoading: confirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  const { data: usdgBalance } = useReadContract({
    address: usdg, abi: erc20Abi, functionName: "balanceOf",
    args: [address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address },
  });
  const { data: allowance } = useReadContract({
    address: usdg, abi: erc20Abi, functionName: "allowance",
    args: [address ?? "0x0000000000000000000000000000000000000000", vault],
    query: { enabled: !!address && deployed },
  });
  const { data: shares } = useReadContract({
    address: vault, abi: vaultAbi, functionName: "balanceOf",
    args: [address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address && deployed },
  });
  const { data: positionAssets } = useReadContract({
    address: vault, abi: vaultAbi, functionName: "convertToAssets",
    args: [shares ?? 0n],
    query: { enabled: deployed && shares !== undefined },
  });

  const amount = parseAmount(input, USDG_DECIMALS);
  const needsApproval =
    mode === "deposit" && amount !== null && allowance !== undefined && allowance < amount;
  const busy = isPending || confirming;

  function onAction() {
    if (!amount || !address) return;
    if (mode === "deposit") {
      if (needsApproval) {
        writeContract({ address: usdg, abi: erc20Abi, functionName: "approve", args: [vault, amount] });
      } else {
        writeContract({ address: vault, abi: vaultAbi, functionName: "deposit", args: [amount, address] });
      }
    } else {
      writeContract({ address: vault, abi: vaultAbi, functionName: "withdraw", args: [amount, address, address] });
    }
  }

  const balanceShown = mode === "deposit" ? fmt(usdgBalance, USDG_DECIMALS) : fmt(positionAssets, USDG_DECIMALS);

  return (
    <div className="card">
      <h2>USDG Yield Vault</h2>
      <div className="sub">
        Auto-allocated to Morpho markets collateralized by tokenized stocks (NVDA · AAPL · TSLA)
      </div>

      {!deployed ? (
        <div className="soon">
          <div className="badge">DEPLOYMENT IN PROGRESS</div>
          <p>
            The ERC-4626 vault is being deployed from the official Morpho Vault V2 factory.
            <br />
            Your USDG balance: <b>{fmt(usdgBalance, USDG_DECIMALS)} USDG</b>
          </p>
        </div>
      ) : (
        <>
          <div className="mode-switch">
            <button className={mode === "deposit" ? "active" : ""} onClick={() => setMode("deposit")}>Deposit</button>
            <button className={mode === "withdraw" ? "active" : ""} onClick={() => setMode("withdraw")}>Withdraw</button>
          </div>

          <div className="balance-line">
            <span>Available: {balanceShown} USDG</span>
            <div className="pct-row">
              {[25, 50, 75, 100].map((pct) => (
                <button
                  key={pct}
                  className="pct-btn"
                  onClick={() => {
                    const src = mode === "deposit" ? usdgBalance : positionAssets;
                    if (src === undefined) return;
                    setInput(((Number(src) * pct) / 100 / 10 ** USDG_DECIMALS).toString());
                  }}
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
              <div className="token-pill"><div className="dot" />USDG</div>
            </div>
          </div>

          <button className="cta" disabled={!isConnected || !amount || busy} onClick={onAction}>
            {busy ? "Confirming…"
              : !isConnected ? "Connect wallet"
              : needsApproval ? "Approve USDG"
              : mode === "deposit" ? "Deposit" : "Withdraw"}
          </button>

          {error && <div className="error">{error.message.split("\n")[0]}</div>}
          {isSuccess && txHash && (
            <div className="success">
              Confirmed · <a href={`https://robinhoodchain.blockscout.com/tx/${txHash}`} target="_blank" rel="noreferrer">view on explorer</a>
            </div>
          )}
        </>
      )}

      <div className="note">
        Yield accrues in the vault share price. 15% performance fee funds utility-token buybacks
        for stakers. Unaudited — test funds only.
      </div>
    </div>
  );
}
