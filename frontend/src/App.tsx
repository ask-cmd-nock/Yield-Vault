import { useEffect, useState } from "react";
import { useReadContract } from "wagmi";
import { WalletButton } from "./components/WalletButton";
import { VaultPanel } from "./components/VaultPanel";
import { StakePanel } from "./components/StakePanel";
import { TvlChart, fmtUsd, type TvlPoint } from "./components/TvlChart";
import { ADDRESSES, vaultAbi, stakingAbi, isDeployed } from "./lib/contracts";
import { fmt } from "./lib/format";

type Page = "overview" | "earn" | "stake";

const PAGES: { id: Page; label: string }[] = [
  { id: "overview", label: "Overview" },
  { id: "earn", label: "Earn" },
  { id: "stake", label: "Stake" },
];

const TVL_HISTORY_KEY = "rhvy-tvl-history-v1";
const USDG_DECIMALS = 6;

function loadHistory(): TvlPoint[] {
  try {
    const raw = localStorage.getItem(TVL_HISTORY_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export default function App() {
  const [page, setPage] = useState<Page>("overview");
  const [history, setHistory] = useState<TvlPoint[]>(loadHistory);

  const vaultDeployed = isDeployed(ADDRESSES.vault);
  const stakingDeployed = isDeployed(ADDRESSES.staking);

  const { data: tvl } = useReadContract({
    address: ADDRESSES.vault as `0x${string}`,
    abi: vaultAbi,
    functionName: "totalAssets",
    query: { enabled: vaultDeployed, refetchInterval: 30_000 },
  });
  const { data: totalStaked } = useReadContract({
    address: ADDRESSES.staking as `0x${string}`,
    abi: stakingAbi,
    functionName: "totalStaked",
    query: { enabled: stakingDeployed, refetchInterval: 60_000 },
  });

  // Accumulate real TVL snapshots locally so the chart builds up from live reads.
  useEffect(() => {
    if (tvl === undefined) return;
    const v = Number(tvl) / 10 ** USDG_DECIMALS;
    setHistory((h) => {
      const lastPoint = h[h.length - 1];
      if (lastPoint && Date.now() - lastPoint.t < 60_000 && lastPoint.v === v) return h;
      const next = [...h, { t: Date.now(), v }].slice(-720);
      try {
        localStorage.setItem(TVL_HISTORY_KEY, JSON.stringify(next));
      } catch { /* storage full/blocked — chart just won't persist */ }
      return next;
    });
  }, [tvl]);

  const tvlUsd = tvl !== undefined ? Number(tvl) / 10 ** USDG_DECIMALS : undefined;

  return (
    <>
      <header className="nav">
        <div className="nav-inner">
          <div className="brand">
            <div className="brand-mark" />
            <div className="brand-text">
              RH Yield Vault
              <small>Robinhood Chain</small>
            </div>
          </div>

          <nav className="nav-links">
            {PAGES.map((p) => (
              <button
                key={p.id}
                className={`nav-link ${page === p.id ? "active" : ""}`}
                onClick={() => setPage(p.id)}
              >
                {p.label}
              </button>
            ))}
          </nav>

          <div className="nav-right">
            <div className="nav-stat">
              <div className="v">{vaultDeployed ? fmtUsd(tvlUsd ?? 0) : "—"}</div>
              <div className="l">TVL</div>
            </div>
            <div className="nav-stat">
              <div className="v">Mainnet</div>
              <div className="l">Chain 4663</div>
            </div>
            <WalletButton />
          </div>
        </div>
      </header>

      <main className="main">
        {page === "overview" && (
          <div className="page">
            <section className="hero panel">
              <div className="hero-title">OVERVIEW</div>

              <div className="hero-split">
                <div>
                  <div className="hero-col-label">Vault</div>
                  <div className="hero-overview-row">
                    <div className="hero-stat">
                      <div className="v">{tvlUsd !== undefined ? fmtUsd(tvlUsd) : "—"}</div>
                      <div className="l">Total Value Locked</div>
                    </div>
                    <div className="hero-stat">
                      <div className="v accent">2.5x</div>
                      <div className="l">Max Reward Boost</div>
                    </div>
                  </div>
                  <div className="hero-sub">
                    USDG deposited across Morpho markets collateralized by tokenized stocks
                  </div>
                  <div className="hero-tags">
                    <span className="tag-txt">ERC-4626</span>
                    <span className="tag-txt">Morpho Vault V2</span>
                    <span className="tag-txt">Non-custodial</span>
                  </div>
                </div>

                <div>
                  <div className="hero-col-label">Personal Data</div>
                  <div className="personal-box">
                    <span>Connect your wallet to view your position.</span>
                    <WalletButton />
                  </div>
                </div>
              </div>

              <div className="hero-chart">
                <TvlChart
                  points={history}
                  emptyLabel={
                    vaultDeployed
                      ? "Collecting on-chain data…"
                      : "Chart goes live with vault deployment"
                  }
                />
              </div>
            </section>

            <section className="tiles">
              <div className="tile">
                <div className="tile-label">Vault TVL</div>
                <div className="tile-value">
                  {vaultDeployed ? `${fmt(tvl, USDG_DECIMALS, 2)} USDG` : "—"}
                </div>
              </div>
              <div className="tile">
                <div className="tile-label">Performance Fee</div>
                <div className="tile-value">15%</div>
              </div>
              <div className="tile">
                <div className="tile-label">Total Staked</div>
                <div className="tile-value">
                  {stakingDeployed ? `${fmt(totalStaked, 18, 2)} TEST` : "—"}
                </div>
              </div>
              <div className="tile">
                <div className="tile-label">Max Reward Boost</div>
                <div className="tile-value accent">2.5x</div>
              </div>
            </section>

            <section className="section">
              <div className="section-head">
                <h2>VAULTS</h2>
                <p>Set-and-forget yield on stablecoins. Withdraw anytime.</p>
              </div>
              <div className="vault-grid">
                <div className="card-box vault-card">
                  <div className="vc-top">
                    <div>
                      <div className="vc-name">USDG Yield Vault</div>
                      <div className="vc-tags">
                        <span>OPEN TERM</span>
                        <span>CREDIT</span>
                        <span>PERMISSIONLESS</span>
                      </div>
                    </div>
                    {vaultDeployed
                      ? <span className="status-pill live">Active</span>
                      : <span className="status-pill soon-pill">Deploying</span>}
                  </div>

                  <div className="vc-rate-row">
                    <div className="vc-asset">
                      <div className="token-dot" />
                      <div>
                        <div>USDG</div>
                        <div className="l">Asset</div>
                      </div>
                    </div>
                    <div className="vc-apy">
                      {vaultDeployed ? "Variable" : "—"}
                      <div className="l">Net APY</div>
                    </div>
                  </div>

                  <div className="vc-meta">
                    <div className="vc-meta-item">
                      <div className="l">Rewards</div>
                      <div className="v accent">TEST buybacks</div>
                    </div>
                    <div className="vc-meta-item">
                      <div className="l">Integrations</div>
                      <div className="v">Morpho</div>
                    </div>
                    <div className="vc-meta-item">
                      <div className="l">Collateral</div>
                      <div className="v">NVDA · AAPL · TSLA</div>
                    </div>
                  </div>

                  <div className="progress-labels">
                    <span>TVL / Max Capacity</span>
                    <span>{vaultDeployed ? fmtUsd(tvlUsd ?? 0) : "—"}</span>
                  </div>
                  <div className="progress-track">
                    <div className="progress-fill" style={{ width: vaultDeployed ? "40%" : "0%" }} />
                  </div>

                  <button className="btn-primary full" onClick={() => setPage("earn")}>
                    Deposit
                  </button>
                </div>
              </div>
            </section>

            <section className="section">
              <div className="section-head">
                <h2>HOW IT WORKS</h2>
                <p>One deposit, three moving parts — all on-chain.</p>
              </div>
              <div className="how-grid">
                <div className="how-card">
                  <div className="how-step">01</div>
                  <h3>Deposit USDG</h3>
                  <p>
                    Deposit into the ERC-4626 vault and receive shares. The vault
                    auto-allocates across curated Morpho markets backed by tokenized stocks.
                  </p>
                </div>
                <div className="how-card">
                  <div className="how-step">02</div>
                  <h3>Yield compounds</h3>
                  <p>
                    Interest paid by borrowers accrues directly into the vault share
                    price. No claiming, no lockups — withdraw whenever you want.
                  </p>
                </div>
                <div className="how-card">
                  <div className="how-step">03</div>
                  <h3>Fees buy back TEST</h3>
                  <p>
                    A 15% performance fee funds on-chain buybacks of the utility token,
                    distributed to stakers with up to a 2.5x lock boost.
                  </p>
                </div>
              </div>
            </section>
          </div>
        )}

        {page === "earn" && (
          <div className="page panel-page">
            <VaultPanel />
          </div>
        )}

        {page === "stake" && (
          <div className="page panel-page">
            <StakePanel />
          </div>
        )}
      </main>

      <footer className="footer">
        <div className="footer-inner">
          <div className="footer-left">
            <div className="brand-mark" />
            <span>© 2026 RH Yield Vault. Not affiliated with Robinhood Markets, Inc.</span>
            <span className="footer-warn">Unaudited beta — test funds only</span>
          </div>

          <div className="footer-social">
            <a href="https://robinhoodchain.blockscout.com" target="_blank" rel="noreferrer">Explorer</a>
            <a href="https://docs.morpho.org" target="_blank" rel="noreferrer">Morpho Docs</a>
            <a href={`https://robinhoodchain.blockscout.com/token/${ADDRESSES.utilityToken}`} target="_blank" rel="noreferrer">TEST</a>
            <a href={`https://robinhoodchain.blockscout.com/token/${ADDRESSES.usdg}`} target="_blank" rel="noreferrer">USDG</a>
          </div>

          <div className="footer-links">
            <button onClick={() => setPage("overview")}>Overview</button>
            <button onClick={() => setPage("earn")}>Earn</button>
            <button onClick={() => setPage("stake")}>Stake</button>
          </div>
        </div>
      </footer>
    </>
  );
}
