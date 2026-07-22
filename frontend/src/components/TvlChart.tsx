import { useLayoutEffect, useMemo, useRef, useState } from "react";

export type TvlPoint = { t: number; v: number };

export function fmtUsd(v: number): string {
  if (v >= 1e9) return `$${(v / 1e9).toFixed(2)}B`;
  if (v >= 1e6) return `$${(v / 1e6).toFixed(2)}M`;
  if (v >= 1e3) return `$${(v / 1e3).toFixed(1)}K`;
  return `$${v.toLocaleString("en-US", { maximumFractionDigits: 2 })}`;
}

const PAD = { top: 14, right: 62, bottom: 26, left: 10 };
const H = 240;

function fmtTick(t: number, spanMs: number): string {
  const d = new Date(t);
  if (spanMs > 2 * 86_400_000) return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
  return d.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: false });
}

export function TvlChart({ points, emptyLabel }: { points: TvlPoint[]; emptyLabel: string }) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  const [hover, setHover] = useState<number | null>(null);

  useLayoutEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setWidth(el.clientWidth));
    ro.observe(el);
    setWidth(el.clientWidth);
    return () => ro.disconnect();
  }, []);

  const geom = useMemo(() => {
    if (points.length < 2 || width < 120) return null;
    const t0 = points[0].t;
    const t1 = points[points.length - 1].t;
    const vs = points.map((p) => p.v);
    let v0 = Math.min(...vs);
    let v1 = Math.max(...vs);
    if (v1 === v0) v1 = v0 + (v0 === 0 ? 1 : Math.abs(v0) * 0.08);
    const span = v1 - v0;
    v0 = Math.max(0, v0 - span * 0.25);
    v1 += span * 0.15;

    const iw = width - PAD.left - PAD.right;
    const ih = H - PAD.top - PAD.bottom;
    const X = (t: number) => PAD.left + ((t - t0) / (t1 - t0)) * iw;
    const Y = (v: number) => PAD.top + (1 - (v - v0) / (v1 - v0)) * ih;

    const pts = points.map((p) => ({ x: X(p.t), y: Y(p.v) }));
    const line = pts.map((p, i) => `${i ? "L" : "M"}${p.x.toFixed(1)},${p.y.toFixed(1)}`).join("");
    const base = H - PAD.bottom;
    const area = `${line}L${pts[pts.length - 1].x.toFixed(1)},${base}L${pts[0].x.toFixed(1)},${base}Z`;

    const yTicks = [0.2, 0.55, 0.9].map((k) => {
      const v = v0 + k * (v1 - v0);
      return { y: Y(v), label: fmtUsd(v) };
    });
    const xTicks = [t0, (t0 + t1) / 2, t1].map((t) => ({ x: X(t), label: fmtTick(t, t1 - t0) }));

    return { pts, line, area, yTicks, xTicks, base };
  }, [points, width]);

  if (points.length < 2) {
    return (
      <div className="chart-empty">
        <span className="pulse-dot" />
        {emptyLabel}
      </div>
    );
  }

  const hovered =
    hover !== null && geom && hover < geom.pts.length
      ? { p: geom.pts[hover], d: points[hover] }
      : null;
  const last = geom ? geom.pts[geom.pts.length - 1] : null;

  return (
    <div className="chart-wrap" ref={wrapRef}>
      {geom && (
        <svg width={width} height={H} onMouseLeave={() => setHover(null)}>
          <defs>
            <linearGradient id="tvl-fill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#1ad597" stopOpacity="0.22" />
              <stop offset="100%" stopColor="#1ad597" stopOpacity="0" />
            </linearGradient>
          </defs>

          {geom.yTicks.map((t, i) => (
            <g key={i}>
              <line x1={PAD.left} x2={width - PAD.right + 8} y1={t.y} y2={t.y} className="chart-grid" />
              <text x={width - PAD.right + 12} y={t.y + 3} className="chart-label">{t.label}</text>
            </g>
          ))}
          {geom.xTicks.map((t, i) => (
            <text
              key={i}
              x={t.x}
              y={H - 6}
              className="chart-label"
              textAnchor={i === 0 ? "start" : i === 2 ? "end" : "middle"}
            >
              {t.label}
            </text>
          ))}

          <path d={geom.area} fill="url(#tvl-fill)" />
          <path d={geom.line} fill="none" stroke="#1ad597" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" />

          {last && (
            <>
              <circle cx={last.x} cy={last.y} r="9" fill="#1ad597" opacity="0.18">
                <animate attributeName="r" values="5;11;5" dur="2.4s" repeatCount="indefinite" />
              </circle>
              <circle cx={last.x} cy={last.y} r="3.5" fill="#1ad597" stroke="#0a0a0b" strokeWidth="1.5" />
            </>
          )}

          {hovered && (
            <>
              <line x1={hovered.p.x} x2={hovered.p.x} y1={PAD.top} y2={geom.base} className="chart-crosshair" />
              <circle cx={hovered.p.x} cy={hovered.p.y} r="4.5" fill="#1ad597" stroke="#0a0a0b" strokeWidth="2" />
            </>
          )}

          <rect
            x={PAD.left}
            y={PAD.top}
            width={Math.max(0, width - PAD.left - PAD.right)}
            height={H - PAD.top - PAD.bottom}
            fill="transparent"
            onMouseMove={(e) => {
              const rect = (e.target as SVGRectElement).ownerSVGElement!.getBoundingClientRect();
              const mx = e.clientX - rect.left;
              let best = 0;
              let bestDist = Infinity;
              geom.pts.forEach((p, i) => {
                const d = Math.abs(p.x - mx);
                if (d < bestDist) { bestDist = d; best = i; }
              });
              setHover(best);
            }}
          />
        </svg>
      )}

      {hovered && (
        <div
          className="chart-tooltip"
          style={{
            left: Math.min(Math.max(hovered.p.x, 70), width - 80),
            top: Math.max(hovered.p.y - 58, 4),
          }}
        >
          <div className="tt-value">{fmtUsd(hovered.d.v)}</div>
          <div className="tt-time">
            {new Date(hovered.d.t).toLocaleString("en-US", {
              month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", hour12: false,
            })}
          </div>
        </div>
      )}
    </div>
  );
}
