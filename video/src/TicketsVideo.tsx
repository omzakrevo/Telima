import React from "react";
import { AbsoluteFill, Audio, Easing, Img, Series, interpolate, spring, staticFile, useCurrentFrame } from "remotion";
import { Backdrop, C, Highlight, Out, Words, clamp, fontFamily, usePop } from "./BoutiqueVideo";

/*
 * Vidéo verticale 9:16 « Telima Voyages : réserver un ticket de car », avec les VRAIS écrans de l'application
 * (captures de l'application : voir video/public/ecrans, générées par app/test/video_shots_test.dart) et la voix off
 * « Léo » (ElevenLabs) : public/voix-off-tickets.mp3, 44 s.
 * Les scènes sont calées sur la voix (détection des silences + longueur des phrases) : si la voix change, reprendre CUTS
 * et les secondes indiquées dans chaque scène (SEC = secondes absolues dans la voix).
 */

export const TICKETS_FPS = 30;
const s = (sec: number) => Math.round(sec * TICKETS_FPS);

const SITE = "telimatchi.com";

// Début de chaque scène (secondes), dernière valeur = fin de la vidéo
const CUTS = [0, 5.2, 9.25, 18.1, 23.2, 25.7, 31.3, 38.8, 44.0];
const FR = CUTS.slice(1).map((c, i) => s(c) - s(CUTS[i]));
export const TICKETS_TOTAL_FRAMES = s(CUTS[CUTS.length - 1]);
/** Image relative au début de la scène [i] pour un instant absolu de la voix. */
const T = (i: number, sec: number) => s(sec) - s(CUTS[i]);

// ───────────────────────── Téléphone avec un vrai écran qui défile ─────────────────────────

const PHONE_W = 640;
const PHONE_H = 1130;
const INNER_W = PHONE_W - 40;
const K = INNER_W / 390; // 1 px CSS de l'application = K px de la vidéo

type Ring = { x: number; y: number; w: number; h: number; at: number; color?: string };

/** Écran réel : `img` (390 px CSS de large, hauteur `h`), défilement par points clés [image, y CSS], cadres de mise en avant. */
const ScreenPhone: React.FC<{
  img: string;
  h: number;
  scroll: [number, number][];
  rings?: Ring[];
  top?: number;
  enter?: number;
  exitAt?: number;
}> = ({ img, h, scroll, rings = [], top = 430, enter = 0, exitAt }) => {
  const frame = useCurrentFrame();
  const pop = spring({ frame: frame - enter, fps: TICKETS_FPS, config: { damping: 15, stiffness: 130 } });
  const out = exitAt === undefined ? 0 : interpolate(frame, [exitAt, exitAt + 12], [0, 1], clamp);
  const y = interpolate(frame, scroll.map((p) => p[0]), scroll.map((p) => p[1]), { ...clamp, easing: Easing.inOut(Easing.cubic) });
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
        transform: `translateY(${(1 - pop) * 900 + out * 700}px) rotate(${sway * pop}deg)`,
        opacity: 1 - out,
      }}
    >
      <div style={{ width: "100%", height: "100%", borderRadius: 64, background: "#F6FAF7", overflow: "hidden", position: "relative" }}>
        <div style={{ position: "absolute", left: 0, top: 0, width: INNER_W, height: h * K, transform: `translateY(${-y * K + 46}px)` }}>
          <Img src={staticFile(`ecrans/${img}.jpg`)} style={{ width: INNER_W, height: h * K, display: "block" }} />
          {rings.map((r, i) => {
            const p = spring({ frame: frame - r.at, fps: TICKETS_FPS, config: { damping: 12, stiffness: 190 } });
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
                  boxShadow: `0 0 0 8px ${(r.color ?? C.orange)}33, 0 10px 30px rgba(0,0,0,0.25)`,
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

/** Légende sous le téléphone : change aux instants donnés. */
const Caption: React.FC<{ items: { at: number; n?: string; text: string }[]; top?: number }> = ({ items, top = 1625 }) => {
  const frame = useCurrentFrame();
  const idx = items.filter((it) => frame >= it.at).length - 1;
  if (idx < 0) return null;
  const it = items[idx];
  const p = spring({ frame: frame - it.at, fps: TICKETS_FPS, config: { damping: 13, stiffness: 200 } });
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
          fontSize: 54,
          color: C.greenDark,
          transform: `translateY(${(1 - p) * 60}px) scale(${0.9 + 0.1 * p})`,
          opacity: Math.min(1, p * 1.6),
        }}
      >
        {it.n && (
          <span style={{ width: 76, height: 76, borderRadius: 38, background: C.orange, color: C.white, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 46 }}>{it.n}</span>
        )}
        {it.text}
      </div>
    </div>
  );
};

const LOGOS: { slug: string; name: string; bg: string; ratio: number; color: string }[] = [
  { slug: "rahimo-transport", name: "Rahimo", bg: "#E9F8FD", ratio: 1.96, color: "#D62828" },
  { slug: "tsr-express", name: "TSR Express", bg: "#E1F2FD", ratio: 2.6, color: "#1B7A3D" },
  { slug: "elitis-express", name: "Elitis Express", bg: "#67380C", ratio: 2.32, color: "#8A4B14" },
  { slug: "rakieta-transport", name: "Rakieta", bg: "#F1FBFC", ratio: 2.19, color: "#1F4FA8" },
  { slug: "staf", name: "STAF", bg: "#F6F9F7", ratio: 3.68, color: "#1D3B8B" },
  { slug: "", name: "Saramaya", bg: "#0F766E", ratio: 2, color: "#0F766E" },
];

/** Plaque d'une compagnie dans le mur de logos. */
const LogoCard: React.FC<{ l: (typeof LOGOS)[number]; at: number; x: number; y: number }> = ({ l, at, x, y }) => {
  const frame = useCurrentFrame();
  const p = spring({ frame: frame - at, fps: TICKETS_FPS, config: { damping: 11, stiffness: 170 } });
  const float = Math.sin((frame + at * 3) / 16) * 7;
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y + float * Math.min(1, p),
        width: 440,
        height: 250,
        borderRadius: 40,
        background: C.white,
        border: `8px solid ${l.color}`,
        boxShadow: `0 26px 60px rgba(0,0,0,0.30)`,
        transform: `scale(${p}) rotate(${(1 - p) * -12}deg)`,
        opacity: Math.min(1, p * 1.6),
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        overflow: "hidden",
        fontFamily,
      }}
    >
      {l.slug ? (
        <div style={{ width: 360, height: 360 / l.ratio, background: l.bg, borderRadius: 18, overflow: "hidden", marginBottom: 6 }}>
          <Img src={staticFile(`compagnies/${l.slug}.jpg`)} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
        </div>
      ) : (
        <div style={{ width: 360, height: 130, background: `linear-gradient(135deg, ${l.color}, #0b4d47)`, borderRadius: 18, display: "flex", alignItems: "center", justifyContent: "center", color: C.white, fontWeight: 800, fontSize: 50, letterSpacing: 2, marginBottom: 6 }}>
          SARAMAYA
        </div>
      )}
      <div style={{ fontWeight: 800, fontSize: 40, color: l.color }}>{l.name}</div>
    </div>
  );
};

/** Pastille d'étape (Nom, Signature, Ville…). */
const Pill: React.FC<{ text: string; at: number; x: number; y: number; icon: React.ReactNode; color?: string }> = ({ text, at, x, y, icon, color = C.greenDark }) => {
  const frame = useCurrentFrame();
  const p = spring({ frame: frame - at, fps: TICKETS_FPS, config: { damping: 11, stiffness: 200 } });
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y + Math.sin((frame + at) / 12) * 5 * Math.min(1, p),
        display: "flex",
        alignItems: "center",
        gap: 20,
        padding: "16px 30px 16px 20px",
        borderRadius: 999,
        background: C.white,
        color,
        fontFamily,
        fontWeight: 800,
        fontSize: 46,
        boxShadow: "0 20px 46px rgba(0,0,0,0.28)",
        transform: `scale(${p}) rotate(${(1 - p) * 8}deg)`,
        opacity: Math.min(1, p * 1.6),
      }}
    >
      {icon}
      {text}
    </div>
  );
};

const Svg: React.FC<{ d: string; size?: number; color?: string }> = ({ d, size = 52, color = C.orange }) => (
  <svg width={size} height={size} viewBox="0 0 24 24">
    <path d={d} fill={color} />
  </svg>
);
const ICON_USER = "M12 12a5 5 0 1 0 0-10 5 5 0 0 0 0 10zm0 2c-4 0-8 2-8 5v3h16v-3c0-3-4-5-8-5z";
const ICON_PEN = "M3 17.25V21h3.75L17.8 9.94l-3.75-3.75L3 17.25zM20.7 7.04a1 1 0 0 0 0-1.41l-2.34-2.34a1 1 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z";
const ICON_PIN = "M12 2a7 7 0 0 0-7 7c0 5 7 13 7 13s7-8 7-13a7 7 0 0 0-7-7zm0 9.5A2.5 2.5 0 1 1 12 6.5a2.5 2.5 0 0 1 0 5z";
const ICON_BUS = "M4 16c0 .9.4 1.7 1 2.2V20a1 1 0 0 0 1 1h1a1 1 0 0 0 1-1v-1h8v1a1 1 0 0 0 1 1h1a1 1 0 0 0 1-1v-1.8c.6-.5 1-1.3 1-2.2V6c0-3.5-3.6-4-8-4S4 2.5 4 6v10zm3.5 1a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm9 0a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zM6 11V6h12v5H6z";
const ICON_TICKET = "M22 10V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v4a2 2 0 0 1 0 4v4a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-4a2 2 0 0 1 0-4zm-9 7.5h-2v-2h2v2zm0-4h-2v-3h2v3zm0-5h-2v-2h2v2z";
const ICON_CHECK = "M9 16.2 4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4z";

// ───────────────────────── Scènes ─────────────────────────

/** 1. Accroche (0 → 5,2 s) */
const Scene1: React.FC = () => {
  const frame = useCurrentFrame();
  const first = interpolate(frame, [T(0, 1.55), T(0, 1.8)], [1, 0], clamp);
  const bus = interpolate(frame, [0, T(0, 1.6)], [-300, 1380], { ...clamp, easing: Easing.inOut(Easing.quad) });
  return (
    <Out frames={FR[0]}>
      <div style={{ opacity: first }}>
        <Words text="Voyager d'une ville à l'autre ?" top={250} size={96} stagger={3} />
      </div>
      <div style={{ position: "absolute", top: 640, left: bus, opacity: first }}>
        <Svg d={ICON_BUS} size={220} color={C.white} />
      </div>
      <div style={{ opacity: interpolate(frame, [T(0, 1.7), T(0, 1.95)], [0, 1], clamp) }}>
        <Words text="Réservez votre ticket de car" top={230} size={84} delay={T(0, 1.8)} stagger={4} />
      </div>
      <Highlight text="en quelques secondes" top={560} delay={T(0, 3.9)} size={64} bg={C.orange} color={C.white} />
      <ScreenPhone img="s1-recherche" h={900} enter={T(0, 2.1)} top={700} scroll={[[0, 0], [T(0, 5.2), 90]]} />
    </Out>
  );
};

/** 2. Choisir ville de départ, ville d'arrivée et heure (5,2 → 9,25 s) */
const Scene2: React.FC = () => (
  <Out frames={FR[1]}>
    <Words text="Choisissez votre trajet" top={210} size={88} stagger={4} />
    <ScreenPhone
      img="s2-choix"
      h={1500}
      enter={0}
      scroll={[[0, 250], [T(1, 8.2), 250], [T(1, 9.2), 560]]}
      rings={[
        { x: 22, y: 266, w: 296, h: 64, at: T(1, 6.0) },
        { x: 22, y: 334, w: 296, h: 64, at: T(1, 6.9) },
        { x: 22, y: 493, w: 336, h: 56, at: T(1, 8.1) },
      ]}
    />
    <Caption
      items={[
        { at: T(1, 5.9), n: "1", text: "Ville de départ" },
        { at: T(1, 6.8), n: "2", text: "Ville d'arrivée" },
        { at: T(1, 8.0), n: "3", text: "Heure de départ" },
      ]}
    />
  </Out>
);

/** 3. Les compagnies : mur de logos puis page d'une compagnie (9,25 → 18,1 s) */
const Scene3: React.FC = () => {
  const frame = useCurrentFrame();
  const wall = interpolate(frame, [T(2, 13.9), T(2, 14.25)], [1, 0], clamp);
  const cols = [70, 570];
  const cards = [
    { l: LOGOS[0], at: T(2, 9.55), x: cols[0], y: 520 },
    { l: LOGOS[1], at: T(2, 10.4), x: cols[1], y: 560 },
    { l: LOGOS[2], at: T(2, 11.2), x: cols[0], y: 830 },
    { l: LOGOS[3], at: T(2, 12.0), x: cols[1], y: 870 },
    { l: LOGOS[4], at: T(2, 12.8), x: cols[0], y: 1140 },
    { l: LOGOS[5], at: T(2, 13.5), x: cols[1], y: 1180 },
  ];
  return (
    <Out frames={FR[2]}>
      <div style={{ opacity: wall }}>
        <Words text="Toutes les compagnies" top={230} size={76} stagger={4} />
        <div style={{ position: "absolute", top: 340, left: 0, right: 0, textAlign: "center", fontFamily, fontWeight: 700, fontSize: 46, color: C.mint, opacity: interpolate(frame, [20, 36], [0, 1], clamp) }}>
          au même endroit
        </div>
        {cards.map((c, i) => (
          <LogoCard key={i} l={c.l} at={c.at} x={c.x} y={c.y} />
        ))}
      </div>
      <div style={{ opacity: interpolate(frame, [T(2, 14.1), T(2, 14.4)], [0, 1], clamp) }}>
        <Words text="Photos et tarifs" top={210} size={88} delay={T(2, 14.2)} stagger={4} />
      </div>
      <ScreenPhone
        img="s3-compagnie"
        h={1700}
        enter={T(2, 14.0)}
        scroll={[[0, 0], [T(2, 15.4), 0], [T(2, 16.4), 540], [T(2, 18.0), 700]]}
        rings={[
          { x: 14, y: 548, w: 360, h: 110, at: T(2, 16.0) },
          { x: 14, y: 790, w: 362, h: 56, at: T(2, 17.2) },
        ]}
      />
      <Caption
        items={[
          { at: T(2, 14.8), text: "Logo et slogan" },
          { at: T(2, 16.0), text: "Photos du car" },
          { at: T(2, 17.1), text: "Horaires et tarifs" },
        ]}
      />
    </Out>
  );
};

/** 4. Une ligne, un jour, une heure (18,1 → 23,2 s) */
const Scene4: React.FC = () => (
  <Out frames={FR[3]}>
    <Words text="Jour, puis heure" top={210} size={92} stagger={4} />
    <ScreenPhone
      img="s3b-tsr"
      h={1700}
      enter={0}
      scroll={[[0, 640], [T(3, 21.0), 640], [T(3, 22.4), 700]]}
      rings={[
        { x: 14, y: 796, w: 362, h: 52, at: T(3, 18.45) },
        { x: 14, y: 888, w: 330, h: 46, at: T(3, 19.35) },
        { x: 14, y: 948, w: 362, h: 110, at: T(3, 20.05) },
      ]}
    />
    <Caption
      items={[
        { at: T(3, 18.4), n: "1", text: "Touchez une ligne" },
        { at: T(3, 19.3), n: "2", text: "Le jour" },
        { at: T(3, 20.0), n: "3", text: "L'heure" },
        { at: T(3, 21.1), text: "Places disponibles en direct" },
      ]}
    />
  </Out>
);

/** 5. Voyageurs (23,2 → 25,7 s) */
const Scene5: React.FC = () => (
  <Out frames={FR[4]}>
    <Words text="Vos voyageurs" top={210} size={96} stagger={4} />
    <ScreenPhone
      img="s4-reservation"
      h={1500}
      enter={0}
      scroll={[[0, 300], [FR[4], 330]]}
      rings={[
        { x: 14, y: 318, w: 360, h: 56, at: T(4, 23.4) },
        { x: 14, y: 370, w: 360, h: 122, at: T(4, 24.9) },
      ]}
    />
    <Caption
      items={[
        { at: T(4, 23.4), n: "1", text: "Nombre de places" },
        { at: T(4, 24.9), n: "2", text: "Leurs noms" },
      ]}
    />
  </Out>
);

/** 6. Paiement en ligne (25,7 → 31,3 s) */
const Scene6: React.FC = () => {
  const paid = usePop(T(5, 30.4), 10, 160);
  return (
    <Out frames={FR[5]}>
      <Words text="Payez en ligne" top={210} size={96} stagger={4} />
      <ScreenPhone
        img="s4-reservation"
        h={1500}
        enter={0}
        scroll={[[0, 330], [T(5, 26.6), 790]]}
        rings={[
          { x: 12, y: 912, w: 280, h: 40, at: T(5, 26.9) },
          { x: 12, y: 1286, w: 362, h: 26, at: T(5, 28.8) },
          { x: 12, y: 1311, w: 362, h: 26, at: T(5, 29.5) },
          { x: 12, y: 1345, w: 362, h: 32, at: T(5, 30.2) },
        ]}
      />
      <Caption
        items={[
          { at: T(5, 26.0), text: "Mobile Money" },
          { at: T(5, 26.9), text: "Orange · Moov" },
          { at: T(5, 28.7), text: "Billets + 500 F de frais" },
        ]}
      />
      <div style={{ position: "absolute", top: 1495, left: 0, right: 0, display: "flex", justifyContent: "center", transform: `scale(${paid})`, opacity: Math.min(1, paid * 2) }}>
        <div style={{ display: "flex", alignItems: "center", gap: 16, padding: "16px 36px", borderRadius: 999, background: C.orange, color: C.white, fontFamily, fontWeight: 800, fontSize: 48, boxShadow: "0 14px 34px rgba(0,0,0,0.3)" }}>
          <Svg d={ICON_CHECK} size={52} color={C.white} /> 18 500 FCFA payés
        </div>
      </div>
    </Out>
  );
};

/** 7. Confirmation, guichet, ticket (31,3 → 38,8 s) */
const Scene7: React.FC = () => {
  const ticket = usePop(T(6, 37.5), 9, 170);
  return (
    <Out frames={FR[6]}>
      <Words text="Au guichet" top={210} size={100} stagger={4} />
      <ScreenPhone
        img="s5-ticket"
        h={1500}
        top={400}
        enter={0}
        scroll={[[0, 150], [T(6, 33.4), 150], [T(6, 34.6), 285]]}
        rings={[
          { x: 14, y: 160, w: 360, h: 88, at: T(6, 31.5) },
          { x: 14, y: 548, w: 360, h: 44, at: T(6, 35.0) },
        ]}
      />
      <Caption top={1730} items={[{ at: T(6, 31.5), text: "Place confirmée" }]} />
      <Pill text="Nom" at={T(6, 35.0)} x={60} y={1560} icon={<Svg d={ICON_USER} />} />
      <Pill text="Signature" at={T(6, 36.0)} x={318} y={1560} icon={<Svg d={ICON_PEN} />} />
      <Pill text="Ville" at={T(6, 36.9)} x={742} y={1560} icon={<Svg d={ICON_PIN} />} />
      <div style={{ position: "absolute", top: 1290, left: 0, right: 0, display: "flex", justifyContent: "center", transform: `scale(${ticket}) rotate(${(1 - ticket) * -6}deg)`, opacity: Math.min(1, ticket * 2) }}>
        <div style={{ display: "flex", alignItems: "center", gap: 20, padding: "22px 44px", borderRadius: 999, background: C.orange, color: C.white, fontFamily, fontWeight: 800, fontSize: 58, boxShadow: "0 18px 44px rgba(0,0,0,0.3)" }}>
          <Svg d={ICON_TICKET} size={64} color={C.white} /> Votre ticket vous est remis
        </div>
      </div>
    </Out>
  );
};

/** 8. Fin (38,8 → 44 s) */
const Scene8: React.FC = () => {
  const frame = useCurrentFrame();
  const logo = usePop(T(7, 39.0), 10, 150);
  const pill = usePop(T(7, 42.4), 12);
  const bus = interpolate(frame, [T(7, 40.2), T(7, 43.6)], [-260, 1340], { ...clamp, easing: Easing.inOut(Easing.cubic) });
  return (
    <AbsoluteFill style={{ fontFamily }}>
      <div style={{ position: "absolute", top: 330, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <Img src={staticFile("logo.png")} style={{ width: 300, height: 300, borderRadius: 76, transform: `scale(${logo}) rotate(${(1 - logo) * -20}deg)`, boxShadow: "0 30px 70px rgba(0,0,0,0.35)" }} />
      </div>
      <div style={{ position: "absolute", top: 670, left: 0, right: 0, textAlign: "center", fontWeight: 800, fontSize: 140, letterSpacing: -5, color: C.white, opacity: interpolate(frame, [T(7, 39.1), T(7, 39.4)], [0, 1], clamp) }}>
        Telima
      </div>
      <div style={{ position: "absolute", top: 835, left: 0, right: 0, textAlign: "center", fontWeight: 800, fontSize: 70, color: C.mint, opacity: interpolate(frame, [T(7, 39.3), T(7, 39.6)], [0, 1], clamp) }}>
        Voyages
      </div>
      <Words text="Votre ticket de car, en toute simplicité" top={1000} size={74} delay={T(7, 39.7)} stagger={5} />
      <div style={{ position: "absolute", top: 1390, left: bus }}>
        <Svg d={ICON_BUS} size={170} color="rgba(255,255,255,0.9)" />
      </div>
      <div style={{ position: "absolute", top: 1560, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 18, padding: "14px 18px 14px 32px", borderRadius: 999, background: C.greenDark, border: "3px solid rgba(255,255,255,0.35)", transform: `scale(${pill})` }}>
          <span style={{ color: C.white, fontWeight: 700, fontSize: 40 }}>Réserver sur</span>
          <span style={{ padding: "14px 34px", borderRadius: 999, background: C.white, color: C.greenDark, fontWeight: 800, fontSize: 48 }}>{SITE}</span>
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const TicketsVideo: React.FC = () => {
  const scenes = [Scene1, Scene2, Scene3, Scene4, Scene5, Scene6, Scene7, Scene8];
  return (
    <AbsoluteFill>
      <Audio src={staticFile("voix-off-tickets.mp3")} />
      <Backdrop />
      <Series>
        {scenes.map((Scene, i) => (
          <Series.Sequence key={i} durationInFrames={FR[i]}>
            <Scene />
          </Series.Sequence>
        ))}
      </Series>
    </AbsoluteFill>
  );
};
