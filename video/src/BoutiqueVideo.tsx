import React from "react";
import {
  AbsoluteFill,
  Audio,
  Easing,
  Img,
  Series,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { loadFont } from "@remotion/fonts";
import QRCode from "qrcode";

/*
 * Vidéo verticale 9:16 « Telima Boutiques », style motion design rapide :
 * fond vert continu avec carrés flottants, gros mots animés, notifications qui s'empilent,
 * maquette de téléphone, puis fin avec logo, slogan et lien.
 * Voix off : public/voix-off-boutiques.mp3 (ElevenLabs, voix « Simon »). Les scènes et les animations
 * sont calées sur le minutage mot à mot de cette voix (transcription automatique) : si la voix change,
 * reprendre les coupes CUTS et les délais marqués « voix » dans chaque scène.
 */

// Police chargée depuis public/fonts (mêmes fichiers que l'application) : rendu possible sans Internet.
export const fontFamily = "Plus Jakarta Sans Local";
for (const weight of ["500", "700", "800"]) {
  loadFont({ family: fontFamily, url: staticFile(`fonts/PlusJakartaSans-${weight}.ttf`), weight, format: "truetype" });
}

export const BOUTIQUE_FPS = 30;
const s = (sec: number) => Math.round(sec * BOUTIQUE_FPS);

const SITE = "telimatchi.com";
const SHOP_LINK = "telimatchi.com/b/awa-style";
/** Le QR code affiché mène au site (la boutique « Awa Style » est fictive). */
const QR_TARGET = "https://telimatchi.com";

export const C = {
  green: "#3D8B5F",
  greenDark: "#2B6B48",
  deep: "#1D4F35",
  orange: "#F08A3C",
  ink: "#1C2420",
  muted: "#7A8580",
  white: "#FFFFFF",
  mint: "#CFEBDA",
  red: "#E25555",
  wa: "#25D366",
};

// Début de chaque scène en secondes, calé sur la voix off (dernière valeur = fin de la vidéo, 35 s)
const CUTS = [0, 3.66, 7.28, 10.3, 12.52, 13.22, 15.72, 20.78, 24.62, 28.08, 35.0];
/** Durée de chaque scène en images. */
const FR = CUTS.slice(1).map((c, i) => s(c) - s(CUTS[i]));
export const BOUTIQUE_TOTAL_FRAMES = s(CUTS[CUTS.length - 1]);

// ───────────────────────── Briques communes ─────────────────────────

export const usePop = (delay = 0, damping = 12, stiffness = 160) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - delay, fps, config: { damping, stiffness } });
};

export const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

const typed = (text: string, frame: number, start: number, perChar = 2) =>
  text.slice(0, Math.max(0, Math.min(text.length, Math.floor((frame - start) / perChar))));

/** Fond continu : dégradé vert, carrés translucides qui dérivent, petit logo en haut (comme une signature). */
export const Backdrop: React.FC = () => {
  const frame = useCurrentFrame();
  const squares = [
    { x: 90, y: 300, size: 70, sp: 0.6, r: 12 },
    { x: 860, y: 420, size: 54, sp: 0.9, r: -18 },
    { x: 160, y: 1180, size: 46, sp: 0.7, r: 25 },
    { x: 900, y: 1320, size: 80, sp: 0.5, r: -8 },
    { x: 520, y: 1620, size: 40, sp: 1.1, r: 40 },
    { x: 760, y: 820, size: 34, sp: 0.8, r: 10 },
    { x: 60, y: 760, size: 30, sp: 1.2, r: -30 },
    { x: 420, y: 230, size: 26, sp: 1, r: 20 },
  ];
  return (
    <AbsoluteFill style={{ background: `radial-gradient(120% 80% at 50% 40%, #4CA673 0%, ${C.green} 38%, ${C.deep} 100%)` }}>
      {squares.map((q, i) => (
        <div
          key={i}
          style={{
            position: "absolute",
            left: q.x + Math.sin((frame * q.sp) / 30 + i) * 22,
            top: q.y + Math.cos((frame * q.sp) / 34 + i) * 30,
            width: q.size,
            height: q.size,
            borderRadius: q.size * 0.22,
            background: "rgba(255,255,255,0.10)",
            border: "2px solid rgba(255,255,255,0.10)",
            transform: `rotate(${q.r + frame * q.sp * 0.4}deg)`,
          }}
        />
      ))}
      <div style={{ position: "absolute", top: 110, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <Img src={staticFile("logo.png")} style={{ width: 92, height: 92, borderRadius: 24, boxShadow: "0 10px 24px rgba(0,0,0,0.25)" }} />
      </div>
    </AbsoluteFill>
  );
};

/** Sortie de scène commune : léger zoom + flou + fondu sur les 6 dernières images. */
export const Out: React.FC<{ frames: number; children: React.ReactNode }> = ({ frames, children }) => {
  const frame = useCurrentFrame();
  const k = interpolate(frame, [frames - 6, frames], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ opacity: 1 - k, transform: `scale(${1 + k * 0.08})`, filter: `blur(${k * 10}px)`, fontFamily }}>
      {children}
    </AbsoluteFill>
  );
};

/** Texte qui apparaît mot par mot (montée + flou → net). */
export const Words: React.FC<{
  text: string;
  top: number;
  size?: number;
  delay?: number;
  stagger?: number;
  color?: string;
  weight?: number;
}> = ({ text, top, size = 110, delay = 0, stagger = 4, color = C.white, weight = 800 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div
      style={{
        position: "absolute",
        top,
        left: 70,
        right: 70,
        display: "flex",
        flexWrap: "wrap",
        justifyContent: "center",
        columnGap: size * 0.26,
        fontFamily,
        fontWeight: weight,
        fontSize: size,
        lineHeight: 1.06,
        letterSpacing: -size * 0.02,
        color,
        textAlign: "center",
      }}
    >
      {text.split(" ").map((w, i) => {
        const p = spring({ frame: frame - delay - i * stagger, fps, config: { damping: 14, stiffness: 180 } });
        return (
          <span key={i} style={{ display: "inline-block", opacity: Math.min(1, p * 1.4), transform: `translateY(${(1 - p) * 50}px)`, filter: `blur(${(1 - Math.min(1, p)) * 8}px)` }}>
            {w}
          </span>
        );
      })}
    </div>
  );
};

/** Mot mis en avant : pastille blanche, texte vert. */
export const Highlight: React.FC<{ text: string; top: number; delay: number; size?: number; bg?: string; color?: string; rotate?: number }> = ({
  text,
  top,
  delay,
  size = 92,
  bg = C.white,
  color = C.greenDark,
  rotate = -2,
}) => {
  const p = usePop(delay, 11, 170);
  return (
    <div style={{ position: "absolute", top, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
      <div
        style={{
          padding: `${size * 0.16}px ${size * 0.42}px`,
          borderRadius: size * 0.34,
          background: bg,
          color,
          fontFamily,
          fontWeight: 800,
          fontSize: size,
          letterSpacing: -size * 0.02,
          boxShadow: "0 18px 40px rgba(0,0,0,0.22)",
          transform: `scale(${p}) rotate(${rotate * p}deg)`,
        }}
      >
        {text}
      </div>
    </div>
  );
};

export const Icon3D: React.FC<{ name: string; size: number; delay?: number; float?: number; style?: React.CSSProperties }> = ({ name, size, delay = 0, float = 0, style }) => {
  const frame = useCurrentFrame();
  const pop = usePop(delay);
  const dy = float ? Math.sin((frame + delay * 3) / 14) * float : 0;
  return <Img src={staticFile(`${name}.webp`)} style={{ width: size, height: size, transform: `translateY(${dy}px) scale(${pop})`, ...style }} />;
};

/** Carte de notification (style messagerie) qui glisse depuis le haut. */
const Notif: React.FC<{ delay: number; title: string; body: string; icon?: React.ReactNode; time?: string; width?: number; tilt?: number }> = ({
  delay,
  title,
  body,
  icon,
  time = "maintenant",
  width = 900,
  tilt = 0,
}) => {
  const p = usePop(delay, 13, 190);
  return (
    <div
      style={{
        width,
        display: "flex",
        alignItems: "center",
        gap: 24,
        padding: "24px 28px",
        borderRadius: 38,
        background: "rgba(255,255,255,0.96)",
        boxShadow: "0 16px 40px rgba(0,0,0,0.20)",
        fontFamily,
        transform: `translateY(${(1 - p) * -90}px) scale(${0.85 + p * 0.15}) rotate(${tilt * p}deg)`,
        opacity: Math.min(1, p * 1.5),
      }}
    >
      {icon ?? (
        <div style={{ width: 84, height: 84, borderRadius: 24, background: C.wa, flexShrink: 0, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <svg width={50} height={50} viewBox="0 0 24 24">
            <path fill="#fff" d="M12 3a9 9 0 0 0-7.8 13.5L3 21l4.6-1.2A9 9 0 1 0 12 3z" />
          </svg>
        </div>
      )}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: "flex", justifyContent: "space-between" }}>
          <span style={{ fontWeight: 800, fontSize: 34, color: C.ink }}>{title}</span>
          <span style={{ fontWeight: 500, fontSize: 26, color: C.muted }}>{time}</span>
        </div>
        <div style={{ fontWeight: 500, fontSize: 34, color: "#3B4540", marginTop: 4, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{body}</div>
      </div>
    </div>
  );
};

const Phone: React.FC<{ children: React.ReactNode; top?: number; width?: number; height?: number; delay?: number }> = ({
  children,
  top = 420,
  width = 640,
  height = 1150,
  delay = 2,
}) => {
  const frame = useCurrentFrame();
  const pop = usePop(delay, 15, 140);
  const sway = Math.sin(frame / 26) * 1.6;
  return (
    <div
      style={{
        position: "absolute",
        top,
        left: (1080 - width) / 2,
        width,
        height,
        borderRadius: 80,
        background: "#E7EDE9",
        padding: 12,
        boxSizing: "border-box",
        border: `6px solid ${C.orange}`,
        boxShadow: "0 60px 110px rgba(0,0,0,0.35)",
        transform: `translateY(${(1 - pop) * 700}px) rotate(${sway}deg)`,
      }}
    >
      <div style={{ width: "100%", height: "100%", borderRadius: 66, background: "#F6FAF7", overflow: "hidden", position: "relative", padding: "84px 28px 28px", boxSizing: "border-box", fontFamily }}>
        <div style={{ position: "absolute", top: 20, left: "50%", marginLeft: -80, width: 160, height: 40, borderRadius: 22, background: C.ink }} />
        {children}
      </div>
    </div>
  );
};

const Chip: React.FC<{ label: string; bg: string; color?: string; size?: number }> = ({ label, bg, color = C.white, size = 26 }) => (
  <span style={{ display: "inline-block", padding: `${size * 0.3}px ${size * 0.7}px`, borderRadius: 999, background: bg, color, fontFamily, fontWeight: 700, fontSize: size }}>{label}</span>
);

const qr = QRCode.create(QR_TARGET, { errorCorrectionLevel: "M" });
const QrSvg: React.FC<{ size: number }> = ({ size }) => {
  const n = qr.modules.size;
  const q = 2; // marge blanche en modules
  const cells: React.ReactNode[] = [];
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      if (qr.modules.get(x, y)) cells.push(<rect key={`${x}-${y}`} x={x + q} y={y + q} width={1.02} height={1.02} />);
    }
  }
  return (
    <svg width={size} height={size} viewBox={`0 0 ${n + 2 * q} ${n + 2 * q}`} shapeRendering="crispEdges">
      <rect width={n + 2 * q} height={n + 2 * q} fill="#fff" />
      <g fill={C.ink}>{cells}</g>
    </svg>
  );
};

/** Ressort calculé à partir d'une image donnée (pas un hook : utilisable dans une boucle ou une expression). */
export const popAt = (frame: number, delay: number) => spring({ frame: frame - delay, fps: BOUTIQUE_FPS, config: { damping: 12, stiffness: 170 } });

// ───────────────────────── Scènes ─────────────────────────

/** 1. Accroche : « Tu vends des habits sur WhatsApp ? » */
const Scene1: React.FC = () => {
  const frame = useCurrentFrame();
  // voix : « habits » 0,32 s, « chaussures » 1,08 s, « sacs » 1,92 s
  const goods = ["habits", "chaussures", "sacs"];
  const at = [10, 32, 58];
  const idx = Math.max(0, at.filter((f) => frame >= f).length - 1);
  const bump = interpolate(frame - at[idx], [0, 5], [0.7, 1], clamp);
  return (
    <Out frames={FR[0]}>
      <Words text="Tu vends des" top={600} size={120} />
      <div style={{ position: "absolute", top: 760, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <div style={{ padding: "14px 46px", borderRadius: 40, background: C.white, color: C.greenDark, fontFamily, fontWeight: 800, fontSize: 120, letterSpacing: -2, transform: `scale(${frame < at[1] ? popAt(frame, at[0]) : bump}) rotate(-2deg)`, boxShadow: "0 18px 40px rgba(0,0,0,0.22)" }}>
          {goods[idx]}
        </div>
      </div>
      <Words text="sur WhatsApp ?" top={960} size={120} delay={80} />
    </Out>
  );
};

/** 2. « Ça te parle ? » + messages clients qui s'empilent */
const Scene2: React.FC = () => {
  const msgs = [
    // voix : « C'est combien ? » +0,98 s, « Il reste ta taille ? » +1,82 s, « Tu livres ? » +2,80 s
    { t: "Mariam", b: "C'est combien la robe bleue ?", d: 27, tilt: -1.5 },
    { t: "Client", b: "Il reste la taille 40 ?", d: 53, tilt: 1 },
    { t: "Ibrahim", b: "Envoie encore les photos stp", d: 68, tilt: -1 },
    { t: "Fatou", b: "Tu livres à Dassasgho ?", d: 82, tilt: 1.5 },
    { t: "Inconnu", b: "🎤 Message vocal (0:42)", d: 96, tilt: -1 },
  ];
  return (
    <Out frames={FR[1]}>
      <Words text="Ça te parle ?" top={300} size={110} />
      <div style={{ position: "absolute", top: 520, left: 0, right: 0, display: "flex", flexDirection: "column", alignItems: "center", gap: 22 }}>
        {msgs.map((m) => (
          <Notif key={m.b} delay={m.d} title={m.t} body={m.b} tilt={m.tilt} />
        ))}
      </div>
    </Out>
  );
};

/** 3. « À certains tu ne réponds pas vite… tu les rates. » + compteurs */
const Scene3: React.FC = () => {
  const frame = useCurrentFrame();
  const msgs = Math.floor(interpolate(frame, [14, 70], [12, 88], { ...clamp, easing: Easing.out(Easing.cubic) }));
  const calls = Math.floor(interpolate(frame, [24, 70], [1, 6], clamp));
  const Counter: React.FC<{ icon: string; value: string; delay: number }> = ({ icon, value, delay }) => {
    const p = usePop(delay, 12);
    return (
      <div style={{ display: "flex", alignItems: "center", gap: 26, padding: "22px 34px", borderRadius: 40, background: "rgba(255,255,255,0.95)", transform: `scale(${p})`, boxShadow: "0 16px 36px rgba(0,0,0,0.2)" }}>
        <span style={{ fontSize: 64 }}>{icon}</span>
        <span style={{ padding: "10px 30px", borderRadius: 999, background: C.red, color: C.white, fontFamily, fontWeight: 800, fontSize: 56 }}>{value}</span>
      </div>
    );
  };
  return (
    <Out frames={FR[2]}>
      <Words text="À certains, tu réponds pas vite…" top={420} size={92} stagger={3} />
      <div style={{ position: "absolute", top: 760, left: 0, right: 0, display: "flex", flexDirection: "column", alignItems: "center", gap: 30 }}>
        <Counter icon="💬" value={`+ ${msgs}`} delay={8} />
        <Counter icon="📞" value={`+ ${calls}`} delay={18} />
      </div>
      <Highlight text="tu les rates." top={1190} delay={62} size={96} bg={C.orange} color={C.white} /* voix : +2,14 s */ />
    </Out>
  );
};

/** 4. « Tu n'arrives plus à suivre tes commandes ? » */
const Scene4: React.FC = () => (
  <Out frames={FR[3]}>
    <Words text="Et tes commandes," top={600} size={100} stagger={3} />
    {/* voix : « tu n'arrives plus à suivre » +0,84 s */}
    <Highlight text="tu ne suis plus !" top={900} delay={25} size={96} />
  </Out>
);

/** 5. « NON. » — coup de poing */
const Scene5: React.FC = () => {
  const frame = useCurrentFrame();
  const p = spring({ frame, fps: BOUTIQUE_FPS, config: { damping: 8, stiffness: 260 } });
  const shake = frame < 14 ? Math.sin(frame * 3.2) * (14 - frame) * 1.6 : 0;
  const flash = interpolate(frame, [0, 6], [0.45, 0], clamp);
  return (
    <Out frames={FR[4]}>
      <AbsoluteFill style={{ background: `rgba(255,255,255,${flash})` }} />
      <div style={{ position: "absolute", top: 760, left: 0, right: 0, textAlign: "center", fontFamily, fontWeight: 800, fontSize: 300, letterSpacing: -10, color: C.white, transform: `scale(${2.2 - p * 1.2}) translateX(${shake}px)`, textShadow: "0 20px 50px rgba(0,0,0,0.3)" }}>
        NON.
      </div>
    </Out>
  );
};

/** 6. « Ta boutique doit vendre même quand tu dors. » */
const Scene6: React.FC = () => (
  <Out frames={FR[5]}>
    <Words text="Ta boutique doit vendre" top={640} size={108} stagger={4} />
    <Highlight text="même quand tu dors." top={920} delay={35} size={78} /* voix : +1,18 s */ />
    <div style={{ position: "absolute", top: 1170, left: 0, right: 0, display: "flex", justifyContent: "center", gap: 40 }}>
      <Icon3D name="shopping_bags" size={190} delay={44} float={10} />
      <Icon3D name="purse" size={170} delay={52} float={12} />
    </div>
  </Out>
);

/** 7. La boutique dans le téléphone : nom, catalogue, tailles, stock */
const Scene7: React.FC = () => {
  const frame = useCurrentFrame();
  const name = typed("Awa Style", frame, 22, 3);
  const products = [
    // voix : « tes articles » +2,22 s, « tes prix » +3,06 s, « tes tailles » +3,66 s, « ton stock » +4,24 s
    { n: "Robe wax", p: "15 000", icon: "shopping_bags", bg: "#FFE5CC", d: 66, tag: "S · M · L" },
    { n: "Sac à main", p: "12 500", icon: "purse", bg: "#ECE8FA", d: 78, tag: "Noir · Beige" },
    { n: "Baskets", p: "18 000", icon: "package", bg: "#E3EEFC", d: 108, tag: "39 → 44" },
    { n: "Coffret", p: "7 500", icon: "wrapped_gift", bg: "#FCE6E8", d: 126, tag: "Plus que 2", low: true },
  ];
  return (
    <Out frames={FR[6]}>
      <div style={{ position: "absolute", top: 250, left: 0, right: 0, textAlign: "center", fontFamily, fontWeight: 800, fontSize: 76, color: C.white, letterSpacing: -1.5 }}>
        Crée ta boutique en ligne
      </div>
      <div style={{ position: "absolute", top: 345, left: 0, right: 0, textAlign: "center", fontFamily, fontWeight: 800, fontSize: 76, color: C.mint, letterSpacing: -1.5, opacity: interpolate(frame, [10, 20], [0, 1], clamp) }}>
        sur Telima
      </div>
      <Phone top={480} height={1180}>
        <div style={{ height: 150, borderRadius: 30, background: `linear-gradient(135deg,${C.orange},#F7B26F)`, position: "relative" }}>
          <div style={{ position: "absolute", left: 24, bottom: -46, width: 100, height: 100, borderRadius: 50, border: "6px solid #F6FAF7", background: C.greenDark, display: "flex", alignItems: "center", justifyContent: "center" }}>
            <Img src={staticFile("shopping_bags.webp")} style={{ width: 62, height: 62 }} />
          </div>
        </div>
        <div style={{ marginTop: 58, fontWeight: 800, fontSize: 44, color: C.ink, minHeight: 56 }}>
          {name}
          <span style={{ opacity: frame < 60 && Math.floor(frame / 8) % 2 ? 0 : frame < 60 ? 1 : 0, color: C.green }}>|</span>
        </div>
        <div style={{ fontWeight: 500, fontSize: 26, color: C.muted }}>Vêtements · Chaussures · Accessoires</div>
        <div style={{ marginTop: 22, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
          {products.map((it) => {
            const p = usePop(it.d, 13, 170);
            return (
              <div key={it.n} style={{ background: C.white, borderRadius: 26, padding: 14, boxShadow: "0 8px 22px rgba(28,36,32,0.08)", transform: `scale(${p})`, opacity: Math.min(1, p * 1.4) }}>
                <div style={{ height: 150, borderRadius: 18, background: it.bg, display: "flex", alignItems: "center", justifyContent: "center" }}>
                  <Img src={staticFile(`${it.icon}.webp`)} style={{ width: 104, height: 104 }} />
                </div>
                <div style={{ marginTop: 10, fontWeight: 700, fontSize: 28, color: C.ink }}>{it.n}</div>
                <div style={{ fontWeight: 800, fontSize: 28, color: C.green }}>{it.p} F</div>
                <div style={{ marginTop: 8 }}>
                  <Chip label={it.tag} bg={it.low ? "#FDE3E3" : "#E0F0E6"} color={it.low ? C.red : C.greenDark} size={22} />
                </div>
              </div>
            );
          })}
        </div>
      </Phone>
    </Out>
  );
};

/** 8. Le lien et le QR code */
const Scene8: React.FC = () => {
  const frame = useCurrentFrame();
  const link = typed(SHOP_LINK, frame, 4, 0.8);
  // voix : « ou ton QR code » +0,78 s, « tes clients commandent directement » +2,06 s
  const qrPop = usePop(24, 12, 150);
  const chips = [
    { n: "WhatsApp", c: C.wa, d: 62 },
    { n: "Facebook", c: "#1877F2", d: 68 },
    { n: "TikTok", c: "#111111", d: 74 },
  ];
  return (
    <Out frames={FR[7]}>
      <Words text="Partage ton lien" top={250} size={100} />
      <div style={{ position: "absolute", top: 420, left: 60, right: 60, display: "flex", justifyContent: "center" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 16, padding: "24px 36px", borderRadius: 999, background: C.white, boxShadow: "0 18px 40px rgba(0,0,0,0.22)", fontFamily, fontWeight: 800, fontSize: 44, color: C.greenDark, transform: `scale(${usePop(4)})`, minWidth: 600, justifyContent: "center" }}>
          <span>🔗</span>
          <span>{link}</span>
        </div>
      </div>
      <div style={{ position: "absolute", top: 580, left: 0, right: 0, textAlign: "center", fontFamily, fontWeight: 800, fontSize: 70, color: C.mint, opacity: interpolate(frame, [18, 26], [0, 1], clamp) }}>
        ou ton QR code
      </div>
      <div style={{ position: "absolute", top: 700, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <div style={{ padding: 26, borderRadius: 48, background: C.white, boxShadow: "0 30px 70px rgba(0,0,0,0.3)", transform: `scale(${qrPop}) rotate(${(1 - qrPop) * -12}deg)`, textAlign: "center" }}>
          <QrSvg size={480} />
          <div style={{ fontFamily, fontWeight: 800, fontSize: 36, color: C.ink, marginTop: 6 }}>Awa Style</div>
          <div style={{ fontFamily, fontWeight: 500, fontSize: 26, color: C.muted }}>Scanne pour commander</div>
        </div>
      </div>
      <div style={{ position: "absolute", top: 1430, left: 0, right: 0, display: "flex", justifyContent: "center", gap: 20 }}>
        {chips.map((ch) => (
          <div key={ch.n} style={{ transform: `scale(${popAt(frame, ch.d)}) translateY(${Math.sin((frame + ch.d) / 10) * 6}px)` }}>
            <Chip label={ch.n} bg={ch.c} size={34} />
          </div>
        ))}
      </div>
    </Out>
  );
};

/** 9. La commande arrive, Telima livre, paiement à la livraison */
const Scene9: React.FC = () => {
  const frame = useCurrentFrame();
  // voix : « livre ton client » +1,16 s, « paie à la livraison » +2,22 s
  const t = interpolate(frame, [16, 64], [0, 1], { ...clamp, easing: Easing.inOut(Easing.quad) });
  const delivered = frame >= 66;
  const doneP = usePop(66, 10);
  return (
    <Out frames={FR[8]}>
      <div style={{ position: "absolute", top: 250, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <Notif
          delay={4}
          title="Telima · Nouvelle commande"
          body="Robe wax · Taille M · 15 000 FCFA"
          icon={<Img src={staticFile("logo.png")} style={{ width: 84, height: 84, borderRadius: 22, flexShrink: 0 }} />}
        />
      </div>
      <Words text="Telima livre ton client" top={520} size={92} delay={6} stagger={3} />
      <svg width={1080} height={400} style={{ position: "absolute", top: 820, left: 0 }}>
        <path d="M150,200 C380,40 700,360 930,200" fill="none" stroke="rgba(255,255,255,0.25)" strokeWidth={14} strokeLinecap="round" strokeDasharray="2 30" />
      </svg>
      <div style={{ position: "absolute", top: 930, left: 70 }}>
        <Icon3D name="convenience_store" size={170} delay={8} />
      </div>
      <div style={{ position: "absolute", top: 920, left: 840 }}>
        <Icon3D name="round_pushpin" size={160} delay={12} float={8} />
      </div>
      {(() => {
        // Trajet sur la courbe de Bézier ci-dessus
        const P = [
          { x: 150, y: 200 },
          { x: 380, y: 40 },
          { x: 700, y: 360 },
          { x: 930, y: 200 },
        ];
        const u = 1 - t;
        const x = u ** 3 * P[0].x + 3 * u * u * t * P[1].x + 3 * u * t * t * P[2].x + t ** 3 * P[3].x;
        const y = u ** 3 * P[0].y + 3 * u * u * t * P[1].y + 3 * u * t * t * P[2].y + t ** 3 * P[3].y;
        return (
          <div style={{ position: "absolute", left: x - 90, top: 820 + y - 150 }}>
            <Icon3D name="motor_scooter" size={180} delay={14} />
          </div>
        );
      })()}
      <div style={{ position: "absolute", top: 1310, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <div style={{ padding: "22px 46px", borderRadius: 999, background: delivered ? C.white : "rgba(255,255,255,0.18)", color: delivered ? C.greenDark : C.white, fontFamily, fontWeight: 800, fontSize: 52, transform: `scale(${delivered ? 0.9 + doneP * 0.1 : 1})` }}>
          {delivered ? "✓ Livré · payé à la livraison" : "En route…"}
        </div>
      </div>
    </Out>
  );
};

/** 10. Fin : logo, slogan, lien */
const Scene10: React.FC = () => {
  const frame = useCurrentFrame();
  const logo = usePop(2, 10, 150);
  // voix : « Un lien » +0,86 s, « une commande » +1,84 s, « livrée » +2,48 s, « Rendez-vous sur… » +3,28 s
  const pill = usePop(96, 12);
  return (
    <AbsoluteFill style={{ fontFamily }}>
      <div style={{ position: "absolute", top: 380, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <Img src={staticFile("logo.png")} style={{ width: 300, height: 300, borderRadius: 76, transform: `scale(${logo}) rotate(${(1 - logo) * -20}deg)`, boxShadow: "0 30px 70px rgba(0,0,0,0.35)" }} />
      </div>
      <div style={{ position: "absolute", top: 720, left: 0, right: 0, textAlign: "center", fontWeight: 800, fontSize: 140, letterSpacing: -5, color: C.white, opacity: interpolate(frame, [12, 22], [0, 1], clamp), transform: `translateY(${interpolate(frame, [12, 24], [30, 0], clamp)}px)` }}>
        Telima
      </div>
      <div style={{ position: "absolute", top: 885, left: 0, right: 0, textAlign: "center", fontWeight: 800, fontSize: 64, color: C.mint, opacity: interpolate(frame, [20, 30], [0, 1], clamp) }}>
        Boutiques
      </div>
      <Words text="Un lien. Une commande. Livrée." top={1030} size={74} delay={26} stagger={12} />
      <div style={{ position: "absolute", top: 1260, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 18, padding: "14px 18px 14px 32px", borderRadius: 999, background: C.greenDark, border: "3px solid rgba(255,255,255,0.35)", transform: `scale(${pill})` }}>
          <span style={{ color: C.white, fontWeight: 700, fontSize: 40 }}>🔗 Lien</span>
          <span style={{ padding: "14px 34px", borderRadius: 999, background: C.white, color: C.greenDark, fontWeight: 800, fontSize: 46 }}>{SITE}</span>
        </div>
      </div>
      <div style={{ position: "absolute", top: 1420, left: 0, right: 0, textAlign: "center", fontWeight: 600, fontSize: 36, color: "rgba(255,255,255,0.8)", opacity: interpolate(frame, [112, 124], [0, 1], clamp) }}>
        Restaurants aussi sur Telima
      </div>
    </AbsoluteFill>
  );
};

export const BoutiqueVideo: React.FC = () => {
  const scenes = [Scene1, Scene2, Scene3, Scene4, Scene5, Scene6, Scene7, Scene8, Scene9, Scene10];
  return (
    <AbsoluteFill>
      <Audio src={staticFile("voix-off-boutiques.mp3")} />
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
