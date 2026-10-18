import React from "react";
import { Easing, Img, interpolate, spring, staticFile, useCurrentFrame } from "remotion";
import { C, clamp, fontFamily } from "./BoutiqueVideo";

/*
 * Briques des vidéos « pas à pas » (LivreurVertical, CommanderVertical) : même rendu que TicketsVideo
 * (téléphone avec un vrai écran qui défile, cadres de mise en avant, légende sous le téléphone, pastille d'étape).
 * Les écrans viennent de video/capture/livreur_commande_shots_test.dart, en 430 px CSS de large.
 */

export const FPS = 30;
export const sec = (x: number) => Math.round(x * FPS);

const PHONE_W = 640;
const PHONE_H = 1130;
const INNER_W = PHONE_W - 40;
const CSS_W = 430;
const K = INNER_W / CSS_W; // 1 px CSS de l'application = K px de la vidéo

export type Ring = { x: number; y: number; w: number; h: number; at: number; color?: string };

/** Écran réel : `img` (430 px CSS de large, hauteur `h`), défilement par points clés [image, y CSS], cadres de mise en avant. */
export const ScreenPhone: React.FC<{
  img: string;
  h: number;
  scroll?: [number, number][];
  rings?: Ring[];
  top?: number;
  enter?: number;
}> = ({ img, h, scroll = [[0, 0]], rings = [], top = 470, enter = 0 }) => {
  const frame = useCurrentFrame();
  const pop = spring({ frame: frame - enter, fps: FPS, config: { damping: 15, stiffness: 130 } });
  const pts = scroll.length === 1 ? [scroll[0], [scroll[0][0] + 1, scroll[0][1]] as [number, number]] : scroll;
  const y = interpolate(frame, pts.map((p) => p[0]), pts.map((p) => p[1]), { ...clamp, easing: Easing.inOut(Easing.cubic) });
  const sway = Math.sin(frame / 30) * 1.2;
  if (frame < enter) return null;
  return (
    <div
      style={{
        position: "absolute",
        top,
        left: (1080 - PHONE_W) / 2,
        width: PHONE_W,
        height: PHONE_H,
        borderRadius: 78,
        background: "#E7EDE9",
        padding: 14,
        boxSizing: "border-box",
        border: `6px solid ${C.orange}`,
        boxShadow: "0 60px 110px rgba(0,0,0,0.38)",
        transform: `translateY(${(1 - pop) * 900}px) rotate(${sway * pop}deg)`,
      }}
    >
      <div style={{ width: "100%", height: "100%", borderRadius: 64, background: "#F6FAF7", overflow: "hidden", position: "relative" }}>
        <div style={{ position: "absolute", left: 0, top: 0, width: INNER_W, height: h * K, transform: `translateY(${-y * K + 46}px)` }}>
          <Img src={staticFile(`ecrans/${img}.jpg`)} style={{ width: INNER_W, height: h * K, display: "block" }} />
          {rings.map((r, i) => {
            const p = spring({ frame: frame - r.at, fps: FPS, config: { damping: 12, stiffness: 190 } });
            const pulse = 1 + Math.sin((frame - r.at) / 5) * 0.012;
            return (
              <div
                key={i}
                style={{
                  position: "absolute",
                  left: r.x * K - 8,
                  top: r.y * K - 8,
                  width: r.w * K + 16,
                  height: r.h * K + 16,
                  borderRadius: 26,
                  border: `7px solid ${r.color ?? C.orange}`,
                  boxShadow: `0 0 0 8px ${r.color ?? C.orange}33, 0 10px 30px rgba(0,0,0,0.25)`,
                  opacity: Math.min(1, p * 1.5) * (frame >= r.at ? 1 : 0),
                  transform: `scale(${(1.25 - 0.25 * Math.min(1, p)) * pulse})`,
                }}
              />
            );
          })}
        </div>
        <div style={{ position: "absolute", left: "50%", top: 14, marginLeft: -70, width: 140, height: 34, borderRadius: 20, background: C.ink, opacity: 0.9 }} />
      </div>
    </div>
  );
};

/** Doigt qui vient toucher un point de l'écran (x, y en px CSS, ramenés au téléphone) au moment `at`. */
export const Tap: React.FC<{ x: number; y: number; at: number; scrollY: number; top?: number }> = ({ x, y, at, scrollY, top = 470 }) => {
  const frame = useCurrentFrame();
  if (frame < at - 14 || frame > at + 26) return null;
  const come = interpolate(frame, [at - 14, at], [1, 0], { ...clamp, easing: Easing.out(Easing.cubic) });
  const press = interpolate(frame, [at, at + 4, at + 9], [1, 0.82, 1], clamp);
  const ripple = interpolate(frame, [at, at + 20], [0, 1], clamp);
  const fade = interpolate(frame, [at + 16, at + 26], [1, 0], clamp);
  const px = (1080 - PHONE_W) / 2 + 20 + x * K;
  const py = top + 20 + 46 + (y - scrollY) * K;
  return (
    <div style={{ position: "absolute", left: px, top: py, opacity: fade, pointerEvents: "none" }}>
      <div style={{ position: "absolute", left: -60 * ripple, top: -60 * ripple, width: 120 * ripple, height: 120 * ripple, borderRadius: "50%", border: `5px solid rgba(255,255,255,${0.9 * (1 - ripple)})` }} />
      <div
        style={{
          position: "absolute",
          left: -34,
          top: -34,
          width: 68,
          height: 68,
          borderRadius: "50%",
          background: "rgba(255,255,255,0.55)",
          border: "4px solid rgba(255,255,255,0.95)",
          boxShadow: "0 8px 20px rgba(0,0,0,0.3)",
          transform: `translate(${come * 120}px, ${come * 160}px) scale(${press})`,
        }}
      />
    </div>
  );
};

/** Légende sous le téléphone : change aux instants donnés. */
export const Caption: React.FC<{ items: { at: number; n?: string; text: string }[]; top?: number }> = ({ items, top = 1650 }) => {
  const frame = useCurrentFrame();
  const idx = items.filter((it) => frame >= it.at).length - 1;
  if (idx < 0) return null;
  const it = items[idx];
  const p = spring({ frame: frame - it.at, fps: FPS, config: { damping: 13, stiffness: 200 } });
  return (
    <div style={{ position: "absolute", top, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
      <div
        key={idx}
        style={{
          display: "flex",
          alignItems: "center",
          gap: 22,
          padding: "20px 44px 20px 24px",
          borderRadius: 999,
          background: C.white,
          boxShadow: "0 18px 44px rgba(0,0,0,0.25)",
          fontFamily,
          fontWeight: 800,
          fontSize: 52,
          color: C.greenDark,
          maxWidth: 1000,
          whiteSpace: "nowrap",
          transform: `translateY(${(1 - p) * 60}px) scale(${0.9 + 0.1 * p})`,
          opacity: Math.min(1, p * 1.6),
        }}
      >
        {it.n && (
          <span style={{ width: 76, height: 76, borderRadius: 38, background: C.orange, color: C.white, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 46, flexShrink: 0 }}>
            {it.n}
          </span>
        )}
        {it.text}
      </div>
    </div>
  );
};

/** Pastille « ÉTAPE n » au-dessus du titre de la scène. */
export const StepBadge: React.FC<{ n: number; of: number; top?: number; delay?: number }> = ({ n, of, top = 222, delay = 0 }) => {
  const frame = useCurrentFrame();
  const p = spring({ frame: frame - delay, fps: FPS, config: { damping: 11, stiffness: 180 } });
  return (
    <div style={{ position: "absolute", top, left: 0, right: 0, display: "flex", justifyContent: "center", gap: 14, alignItems: "center" }}>
      <div
        style={{
          padding: "10px 30px",
          borderRadius: 999,
          background: C.orange,
          color: C.white,
          fontFamily,
          fontWeight: 800,
          fontSize: 40,
          letterSpacing: 4,
          boxShadow: "0 12px 28px rgba(0,0,0,0.25)",
          transform: `scale(${p}) rotate(${(1 - p) * -10}deg)`,
        }}
      >
        ÉTAPE {n}
      </div>
      <div style={{ display: "flex", gap: 8, opacity: Math.min(1, p) }}>
        {Array.from({ length: of }).map((_, i) => (
          <div key={i} style={{ width: i + 1 === n ? 34 : 14, height: 14, borderRadius: 7, background: i + 1 <= n ? C.white : "rgba(255,255,255,0.35)" }} />
        ))}
      </div>
    </div>
  );
};

/** Carte blanche qui surgit (notification, carte extraite d'un écran…). */
export const PopCard: React.FC<{ at: number; top: number; children: React.ReactNode; rotate?: number; width?: number }> = ({ at, top, children, rotate = -3, width = 860 }) => {
  const frame = useCurrentFrame();
  const p = spring({ frame: frame - at, fps: FPS, config: { damping: 11, stiffness: 160 } });
  if (frame < at) return null;
  return (
    <div style={{ position: "absolute", top, left: (1080 - width) / 2, width, transform: `scale(${p}) rotate(${rotate * p}deg)`, opacity: Math.min(1, p * 1.6) }}>
      {children}
    </div>
  );
};

export const Svg: React.FC<{ d: string; size?: number; color?: string }> = ({ d, size = 52, color = C.orange }) => (
  <svg width={size} height={size} viewBox="0 0 24 24">
    <path d={d} fill={color} />
  </svg>
);
export const ICON_CHECK = "M9 16.2 4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4z";
export const ICON_SCOOTER =
  "M19 7c0-1.1-.9-2-2-2h-3v2h3v2.65L13.52 14H10V9H6c-2.21 0-4 1.79-4 4v3h2c0 1.66 1.34 3 3 3s3-1.34 3-3h4.48L19 10.35V7zM7 17c-.55 0-1-.45-1-1h2c0 .55-.45 1-1 1zm-1-7h2v2H6v-2zm13 3c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3zm0 4c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1z";
