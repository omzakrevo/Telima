import React from "react";
import { AbsoluteFill, Audio, Img, Series, interpolate, staticFile, useCurrentFrame } from "remotion";
import { Backdrop, C, Highlight, Out, Words, clamp, fontFamily, usePop } from "./BoutiqueVideo";
import { Caption, FPS, ICON_CHECK, PhotoCard, PopCard, ScreenPhone, StepBadge, Svg, Tap, sec } from "./EcranTelephone";

/*
 * Vidéo verticale 9:16 « Devenir livreur Telima », pas à pas, avec les VRAIS écrans de l'application
 * (video/public/ecrans/l*.jpg, produits par video/capture/livreur_commande_shots_test.dart) et la voix off « Léo »
 * (ElevenLabs) : public/voix-off-livreur.mp3, 52,3 s. Scènes calées sur la voix (horodatage mot à mot) :
 * si la voix change, reprendre CUTS et les secondes indiquées (secondes absolues dans la voix).
 */

export const LIVREUR_FPS = FPS;
const SITE = "telimatchi.com";
const CUTS = [0, 6.35, 10.7, 21.7, 35.4, 40.65, 48.2, 53.0];
const FR = CUTS.slice(1).map((c, i) => sec(c) - sec(CUTS[i]));
export const LIVREUR_TOTAL_FRAMES = sec(CUTS[CUTS.length - 1]);
/** Image relative au début de la scène [i] pour un instant absolu de la voix. */
const T = (i: number, x: number) => sec(x) - sec(CUTS[i]);

const Chip: React.FC<{ text: string; at: number; x: number; y: number; color?: string }> = ({ text, at, x, y, color = C.greenDark }) => {
  const frame = useCurrentFrame();
  const p = usePop(at, 11, 200);
  if (frame < at) return null;
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y + Math.sin((frame + at) / 12) * 5,
        padding: "16px 30px",
        borderRadius: 999,
        background: C.white,
        color,
        fontFamily,
        fontWeight: 800,
        fontSize: 42,
        boxShadow: "0 20px 46px rgba(0,0,0,0.28)",
        transform: `scale(${p}) rotate(${(1 - p) * 8}deg)`,
        opacity: Math.min(1, p * 1.6),
      }}
    >
      {text}
    </div>
  );
};

/** 1. Accroche (0 → 6,35 s) */
const Scene1: React.FC = () => {
  const frame = useCurrentFrame();
  const first = interpolate(frame, [T(0, 1.95), T(0, 2.2)], [1, 0], clamp);
  const second = interpolate(frame, [T(0, 2.1), T(0, 2.35)], [0, 1], clamp);
  return (
    <Out frames={FR[0]}>
      <div style={{ opacity: first }}>
        <Words text="Tu as une moto ?" top={300} size={112} stagger={4} />
        <PhotoCard src="moto-livreur" at={6} x={80} y={620} w={920} h={690} rotate={-3} />
      </div>
      <div style={{ opacity: second }}>
        <Words text="Deviens livreur" top={290} size={118} delay={T(0, 2.15)} stagger={5} />
        <Highlight text="Telima" top={450} delay={T(0, 3.0)} size={110} bg={C.orange} color={C.white} />
        <PhotoCard src="moto-livreur" at={T(0, 2.3)} x={60} y={680} w={640} h={480} rotate={-4} from="left" />
        <PhotoCard src="scooter-livraison" at={T(0, 3.6)} x={540} y={930} w={480} h={420} rotate={5} from="right" />
        <Highlight text="étape par étape" top={1480} delay={T(0, 5.0)} size={78} />
      </div>
    </Out>
  );
};

/** 2. Étape 1 : « Devenir livreur » à l'accueil (6,35 → 10,7 s) */
const Scene2: React.FC = () => (
  <Out frames={FR[1]}>
    <StepBadge n={1} of={5} />
    <Words text="Ouvre Telima" top={300} size={88} stagger={4} />
    <ScreenPhone img="l1-accueil" h={844} scroll={[[0, 0], [T(1, 8.3), 0], [T(1, 9.0), 90]]} rings={[{ x: 212, y: 783, w: 120, h: 42, at: T(1, 9.2) }]} />
    <Tap x={272} y={804} at={T(1, 9.6)} scrollY={90} />
    <Caption items={[{ at: T(1, 7.3), text: "L'application Telima" }, { at: T(1, 9.2), text: "« Devenir livreur »" }]} />
  </Out>
);

/** 3. Étape 2 : créer son compte (10,7 → 21,7 s) */
const Scene3: React.FC = () => (
  <Out frames={FR[2]}>
    <StepBadge n={2} of={5} />
    <Words text="Crée ton compte" top={300} size={88} stagger={4} />
    <ScreenPhone
      img="l2-inscription"
      h={1000}
      scroll={[[0, 0], [T(2, 19.6), 0], [T(2, 20.2), 120]]}
      rings={[
        { x: 18, y: 201, w: 394, h: 68, at: T(2, 12.8) },
        { x: 18, y: 271, w: 394, h: 68, at: T(2, 14.2) },
        { x: 18, y: 361, w: 394, h: 68, at: T(2, 15.5) },
        { x: 18, y: 431, w: 394, h: 68, at: T(2, 16.4) },
        { x: 14, y: 505, w: 402, h: 66, at: T(2, 17.6), color: C.white },
        { x: 18, y: 584, w: 394, h: 58, at: T(2, 20.3) },
      ]}
    />
    <Tap x={215} y={613} at={T(2, 20.9)} scrollY={120} />
    <Caption
      items={[
        { at: T(2, 12.8), n: "1", text: "Prénom et nom" },
        { at: T(2, 14.2), n: "2", text: "Téléphone" },
        { at: T(2, 15.5), n: "3", text: "Mot de passe" },
        { at: T(2, 16.4), n: "4", text: "Ta ville" },
        { at: T(2, 17.6), n: "5", text: "Je veux être livreur" },
        { at: T(2, 20.3), text: "Créer mon compte" },
      ]}
    />
  </Out>
);

/** 4. Étape 3 : le dossier livreur (21,7 → 35,4 s) */
const Scene4: React.FC = () => (
  <Out frames={FR[3]}>
    <StepBadge n={3} of={5} />
    <Words text="Complète ton dossier" top={300} size={82} stagger={4} />
    <ScreenPhone
      img="l3-dossier"
      h={1500}
      scroll={[[0, 0], [T(3, 26.4), 0], [T(3, 27.3), 200], [T(3, 31.2), 200], [T(3, 32.1), 440]]}
      rings={[
        { x: 18, y: 99, w: 394, h: 68, at: T(3, 24.1) },
        { x: 18, y: 174, w: 394, h: 54, at: T(3, 24.9) },
        { x: 18, y: 276, w: 394, h: 92, at: T(3, 27.0) },
        { x: 18, y: 516, w: 394, h: 56, at: T(3, 30.7) },
        { x: 18, y: 590, w: 394, h: 196, at: T(3, 32.0) },
        { x: 18, y: 796, w: 394, h: 60, at: T(3, 33.9) },
      ]}
    />
    <Chip text="Moto" at={T(3, 27.58)} x={40} y={1500} />
    <Chip text="Tricycle" at={T(3, 28.56)} x={230} y={1520} />
    <Chip text="Voiture" at={T(3, 29.22)} x={480} y={1500} />
    <Chip text="Utilitaire" at={T(3, 29.9)} x={720} y={1520} />
    <Tap x={230} y={826} at={T(3, 34.5)} scrollY={440} />
    <Caption
      items={[
        { at: T(3, 24.1), n: "1", text: "Numéro de CNIB" },
        { at: T(3, 24.9), n: "2", text: "Photo de la CNIB" },
        { at: T(3, 27.0), n: "3", text: "Ton véhicule" },
        { at: T(3, 30.7), n: "4", text: "Photo du véhicule" },
        { at: T(3, 32.0), n: "5", text: "Permis si nécessaire" },
        { at: T(3, 33.9), text: "Envoyer mon dossier" },
      ]}
    />
  </Out>
);

/** 5. Étape 4 : vérification puis approbation (35,4 → 40,65 s) */
const Scene5: React.FC = () => (
  <Out frames={FR[4]}>
    <StepBadge n={4} of={5} />
    <Words text="Vérification" top={300} size={92} stagger={4} />
    <ScreenPhone img="l5-verification" h={844} rings={[{ x: 16, y: 70, w: 398, h: 300, at: T(4, 36.4) }]} />
    <PopCard at={T(4, 38.4)} top={1180} rotate={-2}>
      <div style={{ display: "flex", alignItems: "center", gap: 26, padding: "28px 34px", borderRadius: 40, background: "rgba(255,255,255,0.97)", boxShadow: "0 24px 60px rgba(0,0,0,0.35)", fontFamily }}>
        <Img src={staticFile("logo.png")} style={{ width: 96, height: 96, borderRadius: 26 }} />
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 34, fontWeight: 700, color: C.muted }}>Telima · maintenant</div>
          <div style={{ fontSize: 46, fontWeight: 800, color: C.ink }}>Compte livreur approuvé</div>
          <div style={{ fontSize: 34, fontWeight: 600, color: C.muted }}>Tu peux recevoir des courses</div>
        </div>
        <div style={{ width: 84, height: 84, borderRadius: 42, background: C.green, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <Svg d={ICON_CHECK} size={58} color={C.white} />
        </div>
      </div>
    </PopCard>
    <Caption items={[{ at: T(4, 36.4), text: "L'équipe Telima vérifie" }, { at: T(4, 38.4), text: "Tu es notifié" }]} />
  </Out>
);

/** 6. Étape 5 : en ligne, demandes, revenus (40,65 → 48,2 s) */
const Scene6: React.FC = () => (
  <Out frames={FR[5]}>
    <StepBadge n={5} of={5} />
    <Words text="Passe en ligne !" top={300} size={88} stagger={4} />
    <ScreenPhone
      img="l7-en-ligne"
      h={1300}
      scroll={[[0, 0], [T(5, 42.6), 0], [T(5, 43.4), 380]]}
      rings={[
        { x: 16, y: 70, w: 398, h: 122, at: T(5, 41.7), color: C.white },
        { x: 16, y: 466, w: 398, h: 238, at: T(5, 43.4) },
        { x: 230, y: 648, w: 172, h: 54, at: T(5, 44.4) },
      ]}
    />
    <Tap x={317} y={675} at={T(5, 44.9)} scrollY={380} />
    <PopCard at={T(5, 45.8)} top={1250} rotate={-3} width={880}>
      <Img src={staticFile("ecrans/l8-carte-revenus.jpg")} style={{ width: 880, height: 880 * (260 / 796), borderRadius: 44, boxShadow: "0 30px 70px rgba(0,0,0,0.4)", border: "6px solid #fff", display: "block" }} />
    </PopCard>
    <Caption
      items={[
        { at: T(5, 41.7), text: "En ligne" },
        { at: T(5, 42.8), text: "Les demandes arrivent" },
        { at: T(5, 44.4), text: "Accepte la course" },
        { at: T(5, 45.8), text: "Suis tes revenus" },
      ]}
    />
  </Out>
);

/** 7. Fin (48,2 → 53 s) */
const Scene7: React.FC = () => {
  const frame = useCurrentFrame();
  const logo = usePop(T(6, 48.3), 10, 150);
  const pill = usePop(T(6, 50.4), 12);
  return (
    <AbsoluteFill style={{ fontFamily }}>
      <div style={{ position: "absolute", top: 330, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <Img src={staticFile("logo.png")} style={{ width: 300, height: 300, borderRadius: 76, transform: `scale(${logo}) rotate(${(1 - logo) * -20}deg)`, boxShadow: "0 30px 70px rgba(0,0,0,0.35)" }} />
      </div>
      <div style={{ position: "absolute", top: 670, left: 0, right: 0, textAlign: "center", fontWeight: 800, fontSize: 140, letterSpacing: -5, color: C.white, opacity: interpolate(frame, [T(6, 48.4), T(6, 48.7)], [0, 1], clamp) }}>
        Telima
      </div>
      <div style={{ position: "absolute", top: 835, left: 0, right: 0, textAlign: "center", fontWeight: 800, fontSize: 70, color: C.mint, opacity: interpolate(frame, [T(6, 48.6), T(6, 48.9)], [0, 1], clamp) }}>
        Livreurs
      </div>
      <Words text="Deviens livreur dès aujourd'hui" top={1000} size={78} delay={T(6, 48.96)} stagger={5} />
      <PhotoCard src="moto-livreur" at={T(6, 49.6)} x={250} y={1170} w={580} h={340} rotate={-2} from="right" />
      <div style={{ position: "absolute", top: 1560, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 18, padding: "14px 18px 14px 32px", borderRadius: 999, background: C.greenDark, border: "3px solid rgba(255,255,255,0.35)", transform: `scale(${pill})` }}>
          <span style={{ color: C.white, fontWeight: 700, fontSize: 40 }}>S'inscrire sur</span>
          <span style={{ padding: "14px 34px", borderRadius: 999, background: C.white, color: C.greenDark, fontWeight: 800, fontSize: 48 }}>{SITE}</span>
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const LivreurVideo: React.FC = () => {
  const scenes = [Scene1, Scene2, Scene3, Scene4, Scene5, Scene6, Scene7];
  return (
    <AbsoluteFill>
      <Audio src={staticFile("voix-off-livreur.mp3")} />
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
