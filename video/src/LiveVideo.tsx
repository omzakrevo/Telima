import React from "react";
import QRCode from "qrcode";
import { AbsoluteFill, Audio, Img, Series, interpolate, spring, staticFile, useCurrentFrame } from "remotion";
import { Backdrop, C, Highlight, Out, Words, clamp, fontFamily, usePop } from "./BoutiqueVideo";
import { Caption, FPS, PHONE_H, PHONE_W, PhoneFrame, PhotoCard, ScreenPhone, Tap, sec } from "./EcranTelephone";

/*
 * Vidéo verticale 9:16 « Vendre en live avec la boutique Telima » : pour les vendeurs qui font des lives (TikTok,
 * Facebook…). Écran de live d'illustration (interface générique, sans logo de réseau social) sur une photo libre de droit,
 * puis les VRAIS écrans de la boutique (video/public/ecrans/b*.jpg, capture/commerces_shots_test.dart) et la voix off
 * « Léo » (ElevenLabs) : public/voix-off-live.mp3, 36 s. Scènes calées sur la voix (horodatage mot à mot).
 * Boutique « Mode d'Awa » fictive : le QR code affiché mène au site telimatchi.com.
 */

export const LIVE_FPS = FPS;
const SITE = "telimatchi.com";
const CUTS = [0, 8.2, 10.5, 14.7, 18.9, 23.35, 28.85, 32.8, 36.9];
const FR = CUTS.slice(1).map((c, i) => sec(c) - sec(CUTS[i]));
export const LIVE_TOTAL_FRAMES = sec(CUTS[CUTS.length - 1]);
const T = (i: number, x: number) => sec(x) - sec(CUTS[i]);

// ───────────────────────── QR code ─────────────────────────
const qr = QRCode.create(`https://${SITE}`, { errorCorrectionLevel: "M" });
const QrSvg: React.FC<{ size: number }> = ({ size }) => {
  const n = qr.modules.size;
  const q = 2;
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

// ───────────────────────── Écran de live (illustration) ─────────────────────────
const COMMENTS: { at: number; who: string; text: string; color: string }[] = [
  { at: 2.9, who: "Fatim", text: "Elle est trop belle !", color: "#FFB4A2" },
  { at: 3.98, who: "Mariam", text: "Je prends la robe !", color: "#B5E48C" },
  { at: 4.5, who: "Rasmata", text: "Moi aussi !!", color: "#A0C4FF" },
  { at: 5.02, who: "Aïcha", text: "C'est combien ?", color: "#FFD6A5" },
  { at: 5.4, who: "Salif", text: "Tu livres à Gounghin ?", color: "#CDB4DB" },
  { at: 5.76, who: "Bintou", text: "Taille M !", color: "#9BF6FF" },
  { at: 6.15, who: "Awa", text: "Elle est encore dispo ?", color: "#FDFFB6" },
  { at: 6.5, who: "Nafi", text: "Je veux la bleue", color: "#FFC6FF" },
  { at: 6.85, who: "Kadi", text: "Prix ???", color: "#FFADAD" },
  { at: 7.2, who: "Ousséni", text: "Envoie le numéro", color: "#CAFFBF" },
];

const SCREEN_W = PHONE_W - 44;

const LiveScreen: React.FC<{ base: number; lostAt?: number; pinAt?: number; qrAt?: number; showComments?: boolean }> = ({ base, lostAt, pinAt, qrAt, showComments = true }) => {
  const frame = useCurrentFrame();
  const t = (x: number) => sec(x) - sec(base);
  const shown = COMMENTS.filter((c) => frame >= t(c.at));
  const lost = lostAt !== undefined ? interpolate(frame, [t(lostAt), t(lostAt) + 20], [0, 1], clamp) : 0;
  const pin = pinAt !== undefined ? spring({ frame: frame - t(pinAt), fps: FPS, config: { damping: 13, stiffness: 170 } }) : 0;
  const qrp = qrAt !== undefined ? spring({ frame: frame - t(qrAt), fps: FPS, config: { damping: 12, stiffness: 150 } }) : 0;
  const hearts = [0, 1, 2, 3, 4, 5];
  return (
    <AbsoluteFill>
      <Img src={staticFile("photos/femme-robe-wax.jpg")} style={{ position: "absolute", width: "100%", height: "100%", objectFit: "cover", objectPosition: "50% 30%", transform: `scale(${1.05 + Math.sin(frame / 40) * 0.01})` }} />
      <div style={{ position: "absolute", inset: 0, background: "linear-gradient(180deg, rgba(0,0,0,0.55) 0%, rgba(0,0,0,0) 22%, rgba(0,0,0,0) 45%, rgba(0,0,0,0.75) 100%)" }} />
      {/* en-tête du live */}
      <div style={{ position: "absolute", top: 78, left: 22, right: 22, display: "flex", alignItems: "center", gap: 12, fontFamily }}>
        <Img src={staticFile("photos/portant-robes.jpg")} style={{ width: 62, height: 62, borderRadius: 31, objectFit: "cover", border: "3px solid #fff" }} />
        <div style={{ color: "#fff", fontWeight: 800, fontSize: 28, lineHeight: 1.1 }}>
          Mode d’Awa
          <div style={{ fontWeight: 600, fontSize: 20, opacity: 0.85 }}>Gounghin · Ouaga</div>
        </div>
        <div style={{ marginLeft: "auto", display: "flex", gap: 10, alignItems: "center" }}>
          <span style={{ padding: "6px 14px", borderRadius: 10, background: "#FF2D55", color: "#fff", fontWeight: 800, fontSize: 22, letterSpacing: 1 }}>EN DIRECT</span>
          <span style={{ padding: "6px 14px", borderRadius: 10, background: "rgba(0,0,0,0.45)", color: "#fff", fontWeight: 700, fontSize: 22 }}>
            {(1.2 + Math.floor(frame / 15) * 0.1).toFixed(1).replace(".", ",")} k
          </span>
        </div>
      </div>
      {/* cœurs qui montent */}
      {hearts.map((h) => {
        const k = ((frame + h * 17) % 70) / 70;
        return (
          <div key={h} style={{ position: "absolute", right: 30 + (h % 3) * 16, bottom: 170 + k * 380, opacity: 1 - k, transform: `scale(${0.8 + (h % 2) * 0.4})` }}>
            <svg width={38} height={38} viewBox="0 0 24 24">
              <path fill={["#FF2D55", "#FF9500", "#FFD60A"][h % 3]} d="M12 21s-7.5-4.6-9.6-9.2C.9 8.4 3 5 6.4 5c2 0 3.6 1.2 4.4 2.7h2.4C14 6.2 15.6 5 17.6 5 21 5 23.1 8.4 21.6 11.8 19.5 16.4 12 21 12 21z" />
            </svg>
          </div>
        );
      })}
      {/* commentaires */}
      {showComments && (
        <div style={{ position: "absolute", left: 20, right: 110, bottom: 120, display: "flex", flexDirection: "column", gap: 10, fontFamily, opacity: 1 - lost * 0.75, filter: `blur(${lost * 2}px)` }}>
          {shown.slice(-6).map((c) => {
            const p = spring({ frame: frame - t(c.at), fps: FPS, config: { damping: 14, stiffness: 200 } });
            return (
              <div key={c.at} style={{ display: "flex", alignItems: "center", gap: 10, transform: `translateX(${(1 - p) * -60}px)`, opacity: Math.min(1, p * 1.6) }}>
                <span style={{ width: 40, height: 40, borderRadius: 20, background: c.color, color: C.ink, fontWeight: 800, fontSize: 20, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>{c.who[0]}</span>
                <span style={{ padding: "8px 16px", borderRadius: 18, background: "rgba(0,0,0,0.42)", color: "#fff", fontSize: 25, lineHeight: 1.2 }}>
                  <b style={{ color: c.color }}>{c.who}</b> {c.text}
                </span>
              </div>
            );
          })}
        </div>
      )}
      {/* commentaire épinglé : le lien de la boutique */}
      {pinAt !== undefined && frame >= t(pinAt) && (
        <div style={{ position: "absolute", left: 20, right: 20, bottom: 122, transform: `translateY(${(1 - pin) * 60}px) scale(${0.9 + 0.1 * pin})`, opacity: Math.min(1, pin * 1.6) }}>
          <div style={{ display: "flex", alignItems: "center", gap: 14, padding: "16px 18px", borderRadius: 24, background: "rgba(255,255,255,0.96)", boxShadow: "0 12px 30px rgba(0,0,0,0.35)", fontFamily }}>
            <span style={{ width: 54, height: 54, borderRadius: 16, background: C.orange, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
              <svg width={32} height={32} viewBox="0 0 24 24"><path fill="#fff" d="M16 3v2h-1v6l2 3v2h-4v5l-1 1-1-1v-5H7v-2l2-3V5H8V3z" /></svg>
            </span>
            <div style={{ lineHeight: 1.2 }}>
              <div style={{ fontSize: 20, fontWeight: 700, color: C.muted }}>Épinglé par Mode d’Awa</div>
              <div style={{ fontSize: 26, fontWeight: 800, color: C.ink }}>Commandez ici : {SITE}/b/mode-d-awa</div>
            </div>
          </div>
        </div>
      )}
      {/* QR code montré à l'écran */}
      {qrAt !== undefined && frame >= t(qrAt) && (
        <div style={{ position: "absolute", top: 230, left: "50%", marginLeft: -170, width: 340, padding: 20, borderRadius: 34, background: "#fff", boxShadow: "0 20px 50px rgba(0,0,0,0.45)", textAlign: "center", fontFamily, transform: `scale(${qrp}) rotate(${(1 - qrp) * -10}deg)` }}>
          <QrSvg size={300} />
          <div style={{ marginTop: 8, fontSize: 26, fontWeight: 800, color: C.greenDark }}>Scanne pour commander</div>
        </div>
      )}
      {/* barre du bas */}
      <div style={{ position: "absolute", left: 20, right: 20, bottom: 36, display: "flex", gap: 14, alignItems: "center", fontFamily }}>
        <div style={{ flex: 1, padding: "16px 22px", borderRadius: 999, background: "rgba(255,255,255,0.18)", border: "2px solid rgba(255,255,255,0.35)", color: "rgba(255,255,255,0.85)", fontSize: 24 }}>Ajouter un commentaire…</div>
        <span style={{ width: 66, height: 66, borderRadius: 33, background: C.orange, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <svg width={34} height={34} viewBox="0 0 24 24"><path fill="#fff" d="M7 7V6a5 5 0 0 1 10 0v1h3l-1 14H5L4 7zm2 0h6V6a3 3 0 0 0-6 0z" /></svg>
        </span>
      </div>
    </AbsoluteFill>
  );
};

/** Téléphone en mode live (même cadre réaliste que les écrans de l'application). */
const LivePhone: React.FC<{ base: number; top?: number; enter?: number; lostAt?: number; pinAt?: number; qrAt?: number; showComments?: boolean }> = ({ top = 470, enter = 0, ...rest }) => {
  const frame = useCurrentFrame();
  const pop = spring({ frame: frame - enter, fps: FPS, config: { damping: 15, stiffness: 130 } });
  if (frame < enter) return null;
  return (
    <div style={{ position: "absolute", top, left: (1080 - PHONE_W) / 2, width: PHONE_W, height: PHONE_H, transform: `translateY(${(1 - pop) * 900}px) rotate(${Math.sin(frame / 30) * 1.2 * pop}deg)` }}>
      <PhoneFrame screenBg="#000">
        <div style={{ position: "absolute", inset: 0, width: SCREEN_W }}>
          <LiveScreen {...rest} />
        </div>
      </PhoneFrame>
    </div>
  );
};

/** Pastille de moment (« AVANT LE LIVE »…). */
const Tag: React.FC<{ text: string; top?: number }> = ({ text, top = 222 }) => {
  const p = usePop(0, 11, 180);
  return (
    <div style={{ position: "absolute", top, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
      <div style={{ padding: "10px 30px", borderRadius: 999, background: C.orange, color: C.white, fontFamily, fontWeight: 800, fontSize: 40, letterSpacing: 3, boxShadow: "0 12px 28px rgba(0,0,0,0.25)", transform: `scale(${p}) rotate(${(1 - p) * -10}deg)` }}>{text}</div>
    </div>
  );
};

// ───────────────────────── Scènes ─────────────────────────

/** 1. Le live : les commentaires défilent, des commandes se perdent (0 → 8,2 s) */
const Scene1: React.FC = () => (
  <Out frames={FR[0]}>
    <Words text="Tu vends en live ?" top={240} size={104} stagger={4} />
    <LivePhone base={CUTS[0]} top={400} enter={4} lostAt={6.9} />
    <Highlight text="…et des commandes se perdent" top={1610} delay={T(0, 6.7)} size={62} bg={C.red} color={C.white} />
  </Out>
);

/** 2. « Avec ta boutique Telima, c'est fini ! » (8,2 → 10,5 s) */
const Scene2: React.FC = () => (
  <Out frames={FR[1]}>
    <Words text="Avec ta boutique Telima" top={240} size={90} stagger={4} />
    <ScreenPhone img="b8-page-client" h={1300} top={470} scroll={[[0, 0], [T(1, 9.4), 0], [T(1, 10.3), 220]]} />
    <Highlight text="c'est fini !" top={1630} delay={T(1, 9.6)} size={80} bg={C.orange} color={C.white} />
  </Out>
);

/** 3. Avant le live : les articles, photos, tailles, stock (10,5 → 14,7 s) */
const Scene3: React.FC = () => (
  <Out frames={FR[2]}>
    <Tag text="AVANT LE LIVE" />
    <Words text="Ajoute tes articles" top={300} size={86} stagger={4} />
    <ScreenPhone
      img="b5-catalogue"
      h={1100}
      rings={[
        { x: 16, y: 308, w: 398, h: 80, at: T(2, 11.44) },
        { x: 20, y: 314, w: 68, h: 68, at: T(2, 12.78) },
        { x: 92, y: 346, w: 250, h: 28, at: T(2, 13.48) },
      ]}
    />
    <Caption
      items={[
        { at: T(2, 11.44), n: "1", text: "Tes articles" },
        { at: T(2, 12.78), n: "2", text: "Les photos" },
        { at: T(2, 13.48), n: "3", text: "Les tailles" },
        { at: T(2, 14.14), n: "4", text: "Le stock" },
      ]}
    />
  </Out>
);

/** 4. Pendant le live : lien épinglé et QR code à l'écran (14,7 → 18,9 s) */
const Scene4: React.FC = () => (
  <Out frames={FR[3]}>
    <Tag text="PENDANT LE LIVE" />
    <Words text="Partage ton lien" top={300} size={90} stagger={4} />
    <LivePhone base={CUTS[3]} enter={0} pinAt={15.72} qrAt={17.24} showComments={false} />
    <Caption
      items={[
        { at: T(3, 15.72), n: "1", text: "Épingle ton lien" },
        { at: T(3, 17.24), n: "2", text: "Montre ton QR code" },
      ]}
    />
  </Out>
);

/** 5. Les clients choisissent taille et couleur et commandent (18,9 → 23,35 s) */
const Scene5: React.FC = () => (
  <Out frames={FR[4]}>
    <Tag text="TES CLIENTS" />
    <Words text="Ils commandent eux-mêmes" top={300} size={80} stagger={4} />
    <ScreenPhone
      img="b9-taille"
      h={1300}
      scroll={[[0, 0], [T(4, 20.2), 0], [T(4, 20.8), 560]]}
      rings={[
        { x: 16, y: 396, w: 398, h: 130, at: T(4, 19.26) },
        { x: 16, y: 1074, w: 398, h: 46, at: T(4, 20.98) },
        { x: 16, y: 1166, w: 398, h: 46, at: T(4, 21.54) },
        { x: 16, y: 1230, w: 398, h: 54, at: T(4, 22.18) },
      ]}
    />
    <Tap x={215} y={1257} at={T(4, 22.6)} scrollY={560} />
    <Caption
      items={[
        { at: T(4, 18.94), text: "Ils ouvrent ta boutique" },
        { at: T(4, 20.98), n: "1", text: "La taille" },
        { at: T(4, 21.54), n: "2", text: "La couleur" },
        { at: T(4, 22.18), n: "3", text: "Ajouter au panier" },
      ]}
    />
  </Out>
);

/** 6. Toutes les commandes au même endroit (23,35 → 28,85 s) */
const Scene6: React.FC = () => (
  <Out frames={FR[5]}>
    <Tag text="TES COMMANDES" />
    <Words text="Tout au même endroit" top={300} size={86} stagger={4} />
    <ScreenPhone
      img="b10-commandes-live"
      h={1500}
      scroll={[[0, 0], [T(5, 26.4), 0], [T(5, 27.0), 330]]}
      rings={[
        { x: 16, y: 186, w: 398, h: 64, at: T(5, 24.1) },
        { x: 16, y: 305, w: 398, h: 330, at: T(5, 24.66) },
        { x: 24, y: 482, w: 382, h: 34, at: T(5, 25.6) },
        { x: 16, y: 660, w: 398, h: 280, at: T(5, 27.14) },
        { x: 16, y: 952, w: 398, h: 330, at: T(5, 27.7) },
      ]}
    />
    <Caption
      items={[
        { at: T(5, 24.1), text: "Toutes tes commandes" },
        { at: T(5, 25.6), text: "Nom et numéro du client" },
        { at: T(5, 27.14), text: "Tu n'en oublies aucune" },
      ]}
    />
  </Out>
);

/** 7. Le stock se met à jour, un livreur Telima livre (28,85 → 32,8 s) */
const Scene7: React.FC = () => (
  <Out frames={FR[6]}>
    <Words text="Stock à jour" top={260} size={96} stagger={4} />
    <ScreenPhone img="b5-catalogue" h={1100} rings={[{ x: 92, y: 346, w: 250, h: 28, at: T(6, 29.08) }]} />
    <PhotoCard src="moto-livreur" at={T(6, 30.6)} x={240} y={1150} w={620} h={420} rotate={-3} from="right" label="Livreur Telima" />
    <Caption
      items={[
        { at: T(6, 29.08), text: "Le stock baisse tout seul" },
        { at: T(6, 30.64), text: "Un livreur Telima livre" },
      ]}
    />
  </Out>
);

/** 8. Fin (32,8 → 36,9 s) */
const Scene8: React.FC = () => {
  const frame = useCurrentFrame();
  const logo = usePop(T(7, 32.9), 10, 150);
  const pill = usePop(T(7, 34.6), 12);
  return (
    <AbsoluteFill style={{ fontFamily }}>
      <div style={{ position: "absolute", top: 300, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <Img src={staticFile("logo.png")} style={{ width: 280, height: 280, borderRadius: 72, transform: `scale(${logo}) rotate(${(1 - logo) * -20}deg)`, boxShadow: "0 30px 70px rgba(0,0,0,0.35)" }} />
      </div>
      <div style={{ position: "absolute", top: 620, left: 0, right: 0, textAlign: "center", fontWeight: 800, fontSize: 130, letterSpacing: -5, color: C.white, opacity: interpolate(frame, [T(7, 32.9), T(7, 33.2)], [0, 1], clamp) }}>
        Telima
      </div>
      <Words text="Vends en live, sans perdre une seule commande" top={790} size={70} delay={T(7, 33.3)} stagger={4} />
      <PhotoCard src="femme-robe-wax" at={T(7, 33.8)} x={100} y={1130} w={430} h={360} rotate={-4} from="left" />
      <PhotoCard src="moto-livreur" at={T(7, 34.1)} x={550} y={1140} w={430} h={340} rotate={4} from="right" />
      <div style={{ position: "absolute", top: 1580, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 18, padding: "14px 18px 14px 32px", borderRadius: 999, background: C.greenDark, border: "3px solid rgba(255,255,255,0.35)", transform: `scale(${pill})` }}>
          <span style={{ color: C.white, fontWeight: 700, fontSize: 40 }}>Crée ta boutique sur</span>
          <span style={{ padding: "14px 34px", borderRadius: 999, background: C.white, color: C.greenDark, fontWeight: 800, fontSize: 48 }}>{SITE}</span>
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const LiveVideo: React.FC = () => {
  const scenes = [Scene1, Scene2, Scene3, Scene4, Scene5, Scene6, Scene7, Scene8];
  return (
    <AbsoluteFill>
      <Audio src={staticFile("voix-off-live.mp3")} />
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
