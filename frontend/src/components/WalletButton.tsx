import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { robinhoodChain } from "../lib/chain";
import { shortAddr } from "../lib/format";

export function WalletButton() {
  const { address, isConnected, chainId } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();

  if (!isConnected) {
    return (
      <button
        className="wallet-btn"
        disabled={isPending}
        onClick={() => connect({ connector: connectors[0] })}
      >
        {isPending ? "Connecting…" : "Connect Wallet"}
      </button>
    );
  }

  if (chainId !== robinhoodChain.id) {
    return (
      <button className="wallet-btn" onClick={() => switchChain({ chainId: robinhoodChain.id })}>
        Switch to Robinhood Chain
      </button>
    );
  }

  return (
    <button className="wallet-btn connected" title="Disconnect" onClick={() => disconnect()}>
      {shortAddr(address!)}
    </button>
  );
}
