import { formatUnits, parseUnits } from "viem";

export function fmt(value: bigint | undefined, decimals: number, maxFrac = 4): string {
  if (value === undefined) return "—";
  const n = Number(formatUnits(value, decimals));
  if (n !== 0 && n < 10 ** -maxFrac) return `<${(10 ** -maxFrac).toFixed(maxFrac)}`;
  return n.toLocaleString("en-US", { maximumFractionDigits: maxFrac });
}

export function parseAmount(input: string, decimals: number): bigint | null {
  try {
    if (!input || Number(input) <= 0) return null;
    return parseUnits(input, decimals);
  } catch {
    return null;
  }
}

export function shortAddr(a: string): string {
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

export function fmtDuration(seconds: number): string {
  const d = Math.round(seconds / 86400);
  if (d >= 365) return `${Math.round(d / 365)} year${d >= 730 ? "s" : ""}`;
  if (d >= 30) return `${Math.round(d / 30)} month${d >= 60 ? "s" : ""}`;
  return `${d} day${d !== 1 ? "s" : ""}`;
}
