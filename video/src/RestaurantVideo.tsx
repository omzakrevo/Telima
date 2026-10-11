import React from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  Series,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { loadFont } from "@remotion/google-fonts/PlusJakartaSans";

const { fontFamily } = loadFont("normal", {
  weights: ["500", "700", "800"],
  subsets: ["latin", "latin-ext"],
});

export const FPS = 30;
const s = (sec: number) => Math.round(sec * FPS);

/** À compléter avant diffusion : numéro affiché à la fin de la vidéo (laisser vide pour ne rien afficher). */
const CONTACT_PHONE = "";
const SITE = "telimatchi.com";

const C = {
  green: "#3D8B5F",
  greenDark: "#2B6B48",
  orange: "#F08A3C",
  surface: "#F6FAF7",
  ink: "#1C2420",
  muted: "#7A8580",
  white: "#FFFFFF",
  red: "#D64545",
};

// Durées des scènes (secondes) : total 70 s
const SCENES = [6, 6, 10, 8, 10, 10, 8, 6, 6];
export const TOTAL_FRAMES = SCENES.reduce((a, b) => a + s(b), 0);

// ───────────────────────── Briques communes ─────────────────────────

const usePop = (delay = 0, damping = 12) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - delay, fps, config: { damping, stiffness: 140 } });
};

const typed = (text: string, frame: number, start: number, perChar = 2) =>
  text.slice(0, Math.max(0, Math.min(text.length, Math.floor((frame - start) / perChar))));

const Icon3D: React.FC<{ name: string; size: number; delay?: number; float?: number; rotate?: number; style?: React.CSSProperties }> = ({
  name,
  size,
  delay = 0,
  float = 0,
  rotate = 0,
  style,
}) => {
  const frame = useCurrentFrame();
  const pop = usePop(delay);
  const dy = float ? Math.sin((frame + delay * 3) / 14) * float : 0;
  return (
    <Img
      src={staticFile(`${name}.webp`)}
      style={{
        width: size,
        height: size,
        transform: `translateY(${dy}px) scale(${pop}) rotate(${rotate}deg)`,
        ...style,
      }}
    />
  );
};

const Heading: React.FC<{ children: React.ReactNode; color?: string; size?: number; top?: number }> = ({
  children,
  color = C.ink,
  size = 84,
  top = 150,
}) => {
  const frame = useCurrentFrame();
  const pop = usePop(4, 14);
  const opacity = interpolate(frame, [0, 10], [0, 1], { extrapolateRight: "clamp" });
  return (
    <div
      style={{
        position: "absolute",
        top,
        left: 70,
        right: 70,
        textAlign: "center",
        fontFamily,
        fontWeight: 800,
        fontSize: size,
        lineHeight: 1.08,
        color,
        opacity,
        transform: `translateY(${(1 - pop) * 60}px)`,
      }}
    >
      {children}
    </div>
  );
};

const Caption: React.FC<{ text: string; dark?: boolean }> = ({ text, dark }) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [8, 22], [0, 1], { extrapolateRight: "clamp" });
  return (
    <div
      style={{
        position: "absolute",
        left: 60,
        right: 60,
        bottom: 90,
        padding: "30px 38px",
        borderRadius: 40,
        background: dark ? "rgba(255,255,255,0.16)" : "rgba(28,36,32,0.88)",
        color: C.white,
        fontFamily,
        fontWeight: 500,
        fontSize: 40,
        lineHeight: 1.3,
        textAlign: "center",
        opacity,
      }}
    >
      {text}
    </div>
  );
};

const Shell: React.FC<{ frames: number; background: string; caption: string; darkCaption?: boolean; children: React.ReactNode }> = ({
  frames,
  background,
  caption,
  darkCaption,
  children,
}) => {
  const frame = useCurrentFrame();
  const fadeOut = interpolate(frame, [frames - 8, frames], [1, 0], { extrapolateLeft: "clamp" });
  return (
    <AbsoluteFill style={{ background, opacity: fadeOut, fontFamily }}>
      {children}
      <Caption text={caption} dark={darkCaption} />
    </AbsoluteFill>
  );
};

const Phone: React.FC<{ children: React.ReactNode; top?: number; width?: number; height?: number }> = ({
  children,
  top = 380,
  width = 640,
  height = 1060,
}) => {
  const pop = usePop(2, 14);
  return (
    <div
      style={{
        position: "absolute",
        top,
        left: (1080 - width) / 2,
        width,
        height,
        borderRadius: 76,
        background: C.ink,
        padding: 14,
        boxSizing: "border-box",
        boxShadow: "0 50px 90px rgba(0,0,0,0.28)",
        transform: `translateY(${(1 - pop) * 160}px) scale(${0.9 + pop * 0.1})`,
        opacity: pop,
      }}
    >
      <div style={{ width: "100%", height: "100%", borderRadius: 64, background: C.surface, overflow: "hidden", position: "relative", padding: "74px 26px 26px", boxSizing: "border-box" }}>
        <div style={{ position: "absolute", top: 18, left: "50%", marginLeft: -70, width: 140, height: 32, borderRadius: 20, background: C.ink }} />
        {children}
      </div>
    </div>
  );
};

const Chip: React.FC<{ label: string; bg: string; color?: string; size?: number }> = ({ label, bg, color = C.white, size = 34 }) => (
  <span
    style={{
      display: "inline-block",
      padding: "12px 26px",
      borderRadius: 999,
      background: bg,
      color,
      fontFamily,
      fontWeight: 700,
      fontSize: size,
    }}
  >
    {label}
  </span>
);

const Card: React.FC<{ children: React.ReactNode; delay?: number; style?: React.CSSProperties }> = ({ children, delay = 0, style }) => {
  const pop = usePop(delay, 14);
  return (
    <div
      style={{
        background: C.white,
        borderRadius: 30,
        padding: "22px 26px",
        boxShadow: "0 8px 24px rgba(28,36,32,0.08)",
        transform: `translateX(${(1 - pop) * 120}px)`,
        opacity: pop,
        fontFamily,
        ...style,
      }}
    >
      {children}
    </div>
  );
};

// ───────────────────────── Scènes ─────────────────────────

const Scene1: React.FC = () => {
  const frame = useCurrentFrame();
  const ring = Math.sin(frame * 0.9) * 14;
  const badgePop = usePop(20);
  const bubbles = [
    { x: 80, y: 560, d: 10 },
    { x: 700, y: 520, d: 22 },
    { x: 330, y: 700, d: 36 },
    { x: 760, y: 820, d: 48 },
    { x: 120, y: 900, d: 58 },
    { x: 470, y: 560, d: 70 },
  ];
  const count = Math.min(99, Math.floor(interpolate(frame, [10, 120], [1, 99], { extrapolateRight: "clamp" })));
  return (
    <Shell frames={s(SCENES[0])} background="linear-gradient(180deg,#FFF3E6 0%,#FFD9B5 100%)" caption="Votre téléphone sonne, WhatsApp déborde… et vous perdez des commandes.">
      <Heading>Trop de commandes à gérer ?</Heading>
      {bubbles.map((b, i) => (
        <div key={i} style={{ position: "absolute", left: b.x, top: b.y }}>
          <Icon3D name="speech_balloon" size={210} delay={b.d} float={8} rotate={i % 2 ? 8 : -8} />
        </div>
      ))}
      <div style={{ position: "absolute", left: 340, top: 1000, width: 400, height: 400, transform: `rotate(${ring}deg)` }}>
        <Icon3D name="mobile_phone" size={400} delay={4} />
      </div>
      <div
        style={{
          position: "absolute",
          left: 640,
          top: 980,
          minWidth: 140,
          padding: "14px 26px",
          borderRadius: 999,
          background: C.red,
          color: C.white,
          fontFamily,
          fontWeight: 800,
          fontSize: 56,
          textAlign: "center",
          transform: `scale(${badgePop})`,
        }}
      >
        {count}+
      </div>
    </Shell>
  );
};

const Scene2: React.FC = () => {
  const frame = useCurrentFrame();
  const logo = usePop(6, 10);
  const wobble = Math.sin(frame / 10) * 6;
  return (
    <Shell frames={s(SCENES[1])} background={`linear-gradient(180deg,${C.green} 0%,${C.greenDark} 100%)`} caption="Avec Telima, votre restaurant a sa propre vitrine, en ligne, en quelques minutes." darkCaption>
      <div style={{ position: "absolute", top: 260, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <Img src={staticFile("logo.png")} style={{ width: 360, height: 360, borderRadius: 90, transform: `scale(${logo})`, boxShadow: "0 30px 60px rgba(0,0,0,0.3)" }} />
      </div>
      <div style={{ position: "absolute", top: 700, left: 0, right: 0, textAlign: "center", fontFamily, fontWeight: 800, fontSize: 96, color: C.white, opacity: interpolate(frame, [22, 40], [0, 1], { extrapolateRight: "clamp" }) }}>
        Telima
      </div>
      <div style={{ position: "absolute", top: 830, left: 80, right: 80, textAlign: "center", fontFamily, fontWeight: 700, fontSize: 64, color: "#CFEBDA", opacity: interpolate(frame, [34, 52], [0, 1], { extrapolateRight: "clamp" }) }}>
        pour les restaurants
      </div>
      <div style={{ position: "absolute", top: 1060, left: 0, right: 0, display: "flex", justifyContent: "center", transform: `rotate(${wobble}deg)` }}>
        <Icon3D name="pot_of_food" size={380} delay={30} float={10} />
      </div>
    </Shell>
  );
};

const Scene3: React.FC = () => {
  const frame = useCurrentFrame();
  const logoPop = usePop(14);
  const phaseB = frame >= 140;
  const name = typed("Chez Awa", frame, 24, 3);
  const items = [
    { n: "Riz gras + poulet", p: "2 500 FCFA", d: 150 },
    { n: "Tô sauce gombo", p: "1 500 FCFA", d: 175 },
    { n: "Brochettes (5)", p: "1 000 FCFA", d: 200 },
  ];
  const soldOut = frame > 250;
  return (
    <Shell frames={s(SCENES[2])} background={`linear-gradient(180deg,${C.surface} 0%,#E3F1E9 100%)`} caption="Créez votre restaurant, ajoutez vos plats, vos photos, vos prix. Un plat n'est plus disponible ? Un geste : épuisé.">
      <Heading size={76}>{phaseB ? "2. Ajoutez votre menu" : "1. Créez votre restaurant"}</Heading>
      <Phone top={360}>
        {!phaseB ? (
          <div>
            <div style={{ height: 220, borderRadius: 30, background: `linear-gradient(135deg,${C.orange},#F7B26F)`, display: "flex", alignItems: "center", justifyContent: "center" }}>
              <Icon3D name="pot_of_food" size={150} delay={8} float={6} />
            </div>
            <div style={{ marginTop: -60, marginLeft: 30 }}>
              <Img src={staticFile("logo.png")} style={{ width: 120, height: 120, borderRadius: 60, border: "6px solid white", transform: `scale(${logoPop})` }} />
            </div>
            <div style={{ marginTop: 34, fontFamily, color: C.muted, fontWeight: 500, fontSize: 30 }}>Nom du restaurant</div>
            <div style={{ marginTop: 10, padding: "22px 26px", background: C.white, borderRadius: 24, fontFamily, fontWeight: 700, fontSize: 44, color: C.ink, minHeight: 50 }}>
              {name}
              <span style={{ opacity: Math.floor(frame / 8) % 2 ? 0 : 1 }}>|</span>
            </div>
            <div style={{ marginTop: 26, display: "flex", gap: 14 }}>
              <Chip label="Livraison" bg={C.green} />
              <Chip label="Retrait" bg="#D6E8DD" color={C.greenDark} />
            </div>
          </div>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
            <div style={{ fontFamily, fontWeight: 800, fontSize: 42, color: C.ink }}>Menu · Chez Awa</div>
            {items.map((it, i) => {
              const out = soldOut && i === 1;
              return (
                <Card key={it.n} delay={it.d - 140} style={{ display: "flex", alignItems: "center", gap: 20, opacity: out ? 0.55 : 1 }}>
                  <div style={{ width: 90, height: 90, borderRadius: 24, background: "#FFE5CC", display: "flex", alignItems: "center", justifyContent: "center" }}>
                    <Img src={staticFile("pot_of_food.webp")} style={{ width: 66, height: 66 }} />
                  </div>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontWeight: 700, fontSize: 34, color: C.ink }}>{it.n}</div>
                    <div style={{ fontWeight: 800, fontSize: 32, color: C.green }}>{it.p}</div>
                  </div>
                  {out ? <Chip label="Épuisé" bg={C.red} size={28} /> : <Chip label="Dispo" bg={C.green} size={28} />}
                </Card>
              );
            })}
          </div>
        )}
      </Phone>
    </Shell>
  );
};

const Scene4: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const link = typed("telimatchi.com/r/chez-awa", frame, 20, 3);
  const channels = [
    { n: "WhatsApp", c: "#25D366", d: 100 },
    { n: "Facebook", c: "#1877F2", d: 118 },
    { n: "TikTok", c: "#111111", d: 136 },
  ];
  return (
    <Shell frames={s(SCENES[3])} background={`linear-gradient(180deg,#EAF6EF 0%,${C.surface} 100%)`} caption="Vous recevez votre lien personnel. Partagez-le sur WhatsApp, Facebook, TikTok. Vos clients voient votre menu sans créer de compte.">
      <Heading>3. Partagez votre lien</Heading>
      <div
        style={{
          position: "absolute",
          top: 520,
          left: 50,
          right: 50,
          padding: "40px 30px",
          borderRadius: 60,
          background: C.white,
          boxShadow: "0 24px 60px rgba(61,139,95,0.25)",
          fontFamily,
          fontWeight: 800,
          fontSize: 52,
          textAlign: "center",
          color: C.greenDark,
          transform: `scale(${usePop(6)})`,
          minHeight: 70,
        }}
      >
        {link}
        <span style={{ opacity: Math.floor(frame / 8) % 2 ? 0 : 1 }}>|</span>
      </div>
      <div style={{ position: "absolute", top: 780, left: 0, right: 0, display: "flex", justifyContent: "center", gap: 24 }}>
        {channels.map((ch) => (
          <div key={ch.n} style={{ transform: `scale(${spring({ frame: frame - ch.d, fps, config: { damping: 12, stiffness: 140 } })}) translateY(${Math.sin((frame + ch.d) / 12) * 8}px)` }}>
            <Chip label={ch.n} bg={ch.c} size={38} />
          </div>
        ))}
      </div>
      {[0, 1, 2, 3].map((i) => {
        const t = ((frame + i * 25) % 100) / 100;
        return (
          <div key={i} style={{ position: "absolute", left: 130 + i * 230, top: 1200 - t * 330, opacity: Math.sin(t * Math.PI) }}>
            <Icon3D name={i % 2 ? "speech_balloon" : "mobile_phone"} size={170} delay={100} />
          </div>
        );
      })}
    </Shell>
  );
};

const Scene5: React.FC = () => {
  const frame = useCurrentFrame();
  const qty = frame < 70 ? 0 : frame < 110 ? 1 : frame < 150 ? 2 : 3;
  const delivery = frame >= 200;
  const total = qty === 0 ? 0 : qty === 1 ? 2500 : qty === 2 ? 4000 : 5000;
  const fmt = (n: number) => n.toLocaleString("fr-FR").replace(/ | /g, " ");
  return (
    <Shell frames={s(SCENES[4])} background={`linear-gradient(180deg,${C.surface} 0%,#FFF1E3 100%)`} caption="Vos clients choisissent leurs plats, remplissent leur panier et commandent en quelques secondes, en retrait ou en livraison.">
      <Heading size={74}>Commander n'a jamais été aussi simple</Heading>
      <Phone top={420}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div style={{ fontFamily, fontWeight: 800, fontSize: 40, color: C.ink }}>Chez Awa</div>
          <div style={{ position: "relative" }}>
            <Icon3D name="shopping_cart" size={80} delay={4} />
            {qty > 0 && (
              <div style={{ position: "absolute", top: -10, right: -14, minWidth: 40, height: 40, borderRadius: 20, background: C.orange, color: C.white, fontFamily, fontWeight: 800, fontSize: 28, textAlign: "center", lineHeight: "40px" }}>
                {qty}
              </div>
            )}
          </div>
        </div>
        <div style={{ marginTop: 22, display: "flex", flexDirection: "column", gap: 18 }}>
          {[
            { n: "Riz gras + poulet", p: "2 500 FCFA", add: 70 },
            { n: "Tô sauce gombo", p: "1 500 FCFA", add: 110 },
            { n: "Brochettes (5)", p: "1 000 FCFA", add: 150 },
          ].map((it, i) => (
            <Card key={it.n} delay={8 + i * 8} style={{ display: "flex", alignItems: "center", gap: 18 }}>
              <div style={{ flex: 1 }}>
                <div style={{ fontWeight: 700, fontSize: 33, color: C.ink }}>{it.n}</div>
                <div style={{ fontWeight: 800, fontSize: 30, color: C.green }}>{it.p}</div>
              </div>
              <div
                style={{
                  width: 66,
                  height: 66,
                  borderRadius: 33,
                  background: frame >= it.add ? C.green : "#D6E8DD",
                  color: frame >= it.add ? C.white : C.greenDark,
                  fontFamily,
                  fontWeight: 800,
                  fontSize: 44,
                  textAlign: "center",
                  lineHeight: "62px",
                  transform: `scale(${frame >= it.add && frame < it.add + 8 ? 1.25 : 1})`,
                }}
              >
                {frame >= it.add ? "✓" : "+"}
              </div>
            </Card>
          ))}
        </div>
        <div style={{ marginTop: 26, display: "flex", gap: 12 }}>
          <Chip label="Retrait" bg={!delivery ? C.green : "#D6E8DD"} color={!delivery ? C.white : C.greenDark} size={32} />
          <Chip label="Livraison" bg={delivery ? C.green : "#D6E8DD"} color={delivery ? C.white : C.greenDark} size={32} />
        </div>
        <div style={{ position: "absolute", left: 26, right: 26, bottom: 30, padding: "26px 20px", borderRadius: 40, background: C.orange, color: C.white, fontFamily, fontWeight: 800, fontSize: 38, textAlign: "center" }}>
          Commander · {fmt(total)} FCFA
        </div>
      </Phone>
    </Shell>
  );
};

const Scene6: React.FC = () => {
  const frame = useCurrentFrame();
  const bell = Math.sin(frame * 1.1) * (frame < 60 ? 16 : 0);
  const steps = [
    { n: "Acceptée", at: 70 },
    { n: "En préparation", at: 140 },
    { n: "Prête", at: 210 },
  ];
  return (
    <Shell frames={s(SCENES[5])} background={`linear-gradient(180deg,#FFF8EF 0%,${C.surface} 100%)`} caption="Vous recevez la commande sur votre téléphone. Vous l'acceptez, vous la préparez et vous la marquez prête.">
      <Heading size={76}>Vous gardez le contrôle</Heading>
      <Phone top={380}>
        <div style={{ display: "flex", alignItems: "center", gap: 16, transform: `rotate(${bell}deg)`, transformOrigin: "30px 10px" }}>
          <Icon3D name="bell" size={90} delay={2} />
          <div style={{ fontFamily, fontWeight: 800, fontSize: 40, color: C.ink }}>Nouvelle commande !</div>
        </div>
        <Card delay={10} style={{ marginTop: 26 }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <div style={{ fontWeight: 800, fontSize: 38, color: C.ink }}>Commande #1042</div>
            <div style={{ fontWeight: 800, fontSize: 36, color: C.green }}>5 000 FCFA</div>
          </div>
          <div style={{ marginTop: 10, fontWeight: 500, fontSize: 30, color: C.muted }}>3 plats · Livraison</div>
        </Card>
        <div style={{ marginTop: 28, display: "flex", flexDirection: "column", gap: 16 }}>
          {steps.map((st, i) => {
            const on = frame >= st.at;
            const pop = spring({ frame: frame - st.at, fps: FPS, config: { damping: 10 } });
            return (
              <div
                key={st.n}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 20,
                  padding: "22px 26px",
                  borderRadius: 30,
                  background: on ? C.green : C.white,
                  color: on ? C.white : C.muted,
                  fontFamily,
                  fontWeight: 800,
                  fontSize: 38,
                  transform: `scale(${on ? 1 + (1 - Math.min(1, pop)) * 0.08 : 1})`,
                  boxShadow: "0 8px 24px rgba(28,36,32,0.08)",
                }}
              >
                <span style={{ width: 54, height: 54, borderRadius: 27, background: on ? "rgba(255,255,255,0.25)" : "#E6EDE8", textAlign: "center", lineHeight: "54px" }}>{on ? "✓" : i + 1}</span>
                {st.n}
              </div>
            );
          })}
        </div>
      </Phone>
    </Shell>
  );
};

const Scene7: React.FC = () => {
  const frame = useCurrentFrame();
  // Trajet : restaurant (bas gauche) → client (haut droite) en passant par des virages
  const pts = [
    { x: 190, y: 1200 },
    { x: 190, y: 980 },
    { x: 520, y: 980 },
    { x: 520, y: 760 },
    { x: 880, y: 760 },
    { x: 880, y: 520 },
  ];
  const t = interpolate(frame, [30, 200], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.inOut(Easing.quad) });
  const lens = pts.slice(1).map((p, i) => Math.hypot(p.x - pts[i].x, p.y - pts[i].y));
  const total = lens.reduce((a, b) => a + b, 0);
  let d = t * total;
  let pos = pts[0];
  for (let i = 0; i < lens.length; i++) {
    if (d <= lens[i]) {
      const k = d / lens[i];
      pos = { x: pts[i].x + (pts[i + 1].x - pts[i].x) * k, y: pts[i].y + (pts[i + 1].y - pts[i].y) * k };
      break;
    }
    d -= lens[i];
    pos = pts[i + 1];
  }
  const path = pts.map((p, i) => `${i ? "L" : "M"}${p.x},${p.y}`).join(" ");
  const eta = Math.max(0, Math.round(8 - t * 8));
  return (
    <Shell frames={s(SCENES[6])} background="linear-gradient(180deg,#E3F1E9 0%,#CFE6D8 100%)" caption="Une commande prête ? Un livreur Telima vient la chercher et la livre. Votre client suit tout en direct.">
      <Heading size={78}>Livraison suivie en direct</Heading>
      <svg width={1080} height={1920} style={{ position: "absolute", inset: 0 }}>
        {[0, 1, 2, 3, 4, 5, 6, 7].map((i) => (
          <line key={`h${i}`} x1={0} x2={1080} y1={420 + i * 150} y2={420 + i * 150} stroke="#BBD8C6" strokeWidth={3} />
        ))}
        {[0, 1, 2, 3, 4, 5, 6].map((i) => (
          <line key={`v${i}`} y1={420} y2={1500} x1={i * 180} x2={i * 180} stroke="#BBD8C6" strokeWidth={3} />
        ))}
        <path d={path} fill="none" stroke="#FFFFFF" strokeWidth={30} strokeLinecap="round" strokeLinejoin="round" />
        <path d={path} fill="none" stroke={C.green} strokeWidth={12} strokeLinecap="round" strokeLinejoin="round" strokeDasharray={total} strokeDashoffset={total * (1 - t)} />
      </svg>
      <div style={{ position: "absolute", left: pts[0].x - 80, top: pts[0].y - 40 }}>
        <Icon3D name="convenience_store" size={160} delay={4} />
      </div>
      <div style={{ position: "absolute", left: pts[5].x - 70, top: pts[5].y - 130 }}>
        <Icon3D name="round_pushpin" size={140} delay={14} float={8} />
      </div>
      <div style={{ position: "absolute", left: pos.x - 85, top: pos.y - 100 }}>
        <Icon3D name="motor_scooter" size={170} delay={20} />
      </div>
      <div style={{ position: "absolute", top: 1360, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <div style={{ padding: "22px 44px", borderRadius: 999, background: C.white, boxShadow: "0 12px 30px rgba(0,0,0,0.15)", fontFamily, fontWeight: 800, fontSize: 44, color: C.greenDark }}>
          {eta > 0 ? `Arrivée dans ${eta} min` : "Livré !"}
        </div>
      </div>
    </Shell>
  );
};

const Scene8: React.FC = () => {
  const frame = useCurrentFrame();
  const bars = [90, 140, 200, 260, 340];
  const orders = Math.floor(interpolate(frame, [16, 120], [0, 24], { extrapolateRight: "clamp" }));
  return (
    <Shell frames={s(SCENES[7])} background={`linear-gradient(180deg,${C.surface} 0%,#E3F1E9 100%)`} caption="Plus de commandes, moins de stress, et un restaurant que tout le monde trouve.">
      <Heading size={80}>Plus de clients, moins de stress</Heading>
      <div style={{ position: "absolute", top: 520, left: 70, right: 70, padding: "34px 40px", borderRadius: 50, background: C.white, boxShadow: "0 20px 50px rgba(28,36,32,0.12)" }}>
        <div style={{ fontFamily, fontWeight: 700, fontSize: 36, color: C.muted }}>Commandes du jour</div>
        <div style={{ fontFamily, fontWeight: 800, fontSize: 120, color: C.green, lineHeight: 1.1 }}>{orders}</div>
        <div style={{ display: "flex", alignItems: "flex-end", gap: 22, height: 360, marginTop: 10 }}>
          {bars.map((b, i) => {
            const h = interpolate(frame, [10 + i * 8, 60 + i * 8], [0, b], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.out(Easing.cubic) });
            return <div key={i} style={{ flex: 1, height: h, borderRadius: 22, background: i === bars.length - 1 ? C.orange : C.green }} />;
          })}
        </div>
      </div>
      <div style={{ position: "absolute", top: 1230, left: 0, right: 0, display: "flex", justifyContent: "center", gap: 20 }}>
        {[0, 1, 2, 3, 4].map((i) => (
          <Icon3D key={i} name="star" size={120} delay={70 + i * 8} float={6} />
        ))}
      </div>
    </Shell>
  );
};

const Scene9: React.FC = () => {
  const frame = useCurrentFrame();
  const logo = usePop(4, 10);
  const btn = usePop(40, 10);
  return (
    <Shell frames={s(SCENES[8])} background={`linear-gradient(180deg,${C.green} 0%,${C.greenDark} 100%)`} caption="Restaurants, rejoignez Telima. Clients, commandez vos plats préférés directement dans l'application." darkCaption>
      <div style={{ position: "absolute", top: 200, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <Img src={staticFile("logo.png")} style={{ width: 260, height: 260, borderRadius: 66, transform: `scale(${logo})`, boxShadow: "0 24px 50px rgba(0,0,0,0.3)" }} />
      </div>
      <div style={{ position: "absolute", top: 520, left: 60, right: 60, textAlign: "center", fontFamily, fontWeight: 800, fontSize: 90, lineHeight: 1.1, color: C.white, opacity: interpolate(frame, [16, 32], [0, 1], { extrapolateRight: "clamp" }) }}>
        Restaurants, rejoignez Telima
      </div>
      <div style={{ position: "absolute", top: 800, left: 60, right: 60, textAlign: "center", fontFamily, fontWeight: 700, fontSize: 54, color: "#CFEBDA", opacity: interpolate(frame, [28, 44], [0, 1], { extrapolateRight: "clamp" }) }}>
        Clients, commandez vos plats directement dans l'application
      </div>
      <div style={{ position: "absolute", top: 1060, left: 0, right: 0, display: "flex", justifyContent: "center", transform: `scale(${btn})` }}>
        <div style={{ padding: "34px 70px", borderRadius: 999, background: C.orange, color: C.white, fontFamily, fontWeight: 800, fontSize: 56 }}>Télécharger l'application</div>
      </div>
      <div style={{ position: "absolute", top: 1230, left: 0, right: 0, textAlign: "center", fontFamily, fontWeight: 800, fontSize: 58, color: C.white, opacity: interpolate(frame, [60, 76], [0, 1], { extrapolateRight: "clamp" }) }}>
        {SITE}
        {CONTACT_PHONE ? <div style={{ marginTop: 14, fontSize: 52, color: "#CFEBDA" }}>{CONTACT_PHONE}</div> : null}
      </div>
    </Shell>
  );
};

export const RestaurantVideo: React.FC = () => {
  const scenes = [Scene1, Scene2, Scene3, Scene4, Scene5, Scene6, Scene7, Scene8, Scene9];
  return (
    <AbsoluteFill style={{ background: C.surface }}>
      <Series>
        {scenes.map((Scene, i) => (
          <Series.Sequence key={i} durationInFrames={s(SCENES[i])}>
            <Scene />
          </Series.Sequence>
        ))}
      </Series>
    </AbsoluteFill>
  );
};
