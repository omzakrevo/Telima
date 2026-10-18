import React from "react";
import { AbsoluteFill, Audio, Img, Series, interpolate, staticFile, useCurrentFrame } from "remotion";
import { Backdrop, C, Highlight, Out, Words, clamp, fontFamily, usePop } from "./BoutiqueVideo";
import { Caption, FPS, PhotoCard, ScreenPhone, StepBadge, Tap, sec } from "./EcranTelephone";

/*
 * Vidéo verticale 9:16 « Commander une livraison sur Telima », pas à pas, avec les VRAIS écrans de l'application
 * (video/public/ecrans/c*.jpg, produits par video/capture/livreur_commande_shots_test.dart, cartes OpenStreetMap posées
 * par video/capture/poser_tuiles.py) et la voix off « Léo » (ElevenLabs) : public/voix-off-commande.mp3, 46,2 s.
 * Scènes calées sur la voix (horodatage mot à mot) : si la voix change, reprendre CUTS et les secondes indiquées.
 */

export const COMMANDER_FPS = FPS;
const SITE = "telimatchi.com";
const CUTS = [0, 7.3, 9.8, 16.8, 21.2, 26.4, 36.65, 41.9, 46.9];
const FR = CUTS.slice(1).map((c, i) => sec(c) - sec(CUTS[i]));
export const COMMANDER_TOTAL_FRAMES = sec(CUTS[CUTS.length - 1]);
const T = (i: number, x: number) => sec(x) - sec(CUTS[i]);

/** 1. Accroche (0 → 7,3 s) */
const Scene1: React.FC = () => {
  const frame = useCurrentFrame();
  const first = interpolate(frame, [T(0, 1.0), T(0, 1.25)], [1, 0], clamp);
  const second = interpolate(frame, [T(0, 1.15), T(0, 1.4)], [0, 1], clamp);
  return (
    <Out frames={FR[0]}>
      <div style={{ opacity: first }}>
        <Words text="Un colis à envoyer ?" top={300} size={110} stagger={3} />
        <PhotoCard src="smartphone-main" at={4} x={80} y={620} w={920} h={620} rotate={-3} />
      </div>
      <div style={{ opacity: second }}>
        <Words text="Un livreur vient le chercher" top={270} size={96} delay={T(0, 1.4)} stagger={4} />
        <Highlight text="et le dépose à destination" top={560} delay={T(0, 3.3)} size={66} bg={C.orange} color={C.white} />
        <PhotoCard src="moto-livreur" at={T(0, 2.0)} x={60} y={720} w={660} h={490} rotate={-4} from="left" />
        <PhotoCard src="smartphone-main" at={T(0, 3.9)} x={560} y={980} w={460} h={380} rotate={5} from="right" />
        <Highlight text="étape par étape" top={1480} delay={T(0, 6.0)} size={78} />
      </div>
    </Out>
  );
};

/** 2. Accueil : « Envoyer un colis » (7,3 → 9,8 s) */
const Scene2: React.FC = () => (
  <Out frames={FR[1]}>
    <Words text="Sur l'accueil" top={250} size={96} stagger={4} />
    <ScreenPhone img="c1-accueil" h={844} scroll={[[0, 0], [T(1, 7.9), 0], [T(1, 8.4), 80]]} rings={[{ x: 37, y: 536, w: 130, h: 44, at: T(1, 8.5) }]} />
    <Tap x={100} y={558} at={T(1, 9.0)} scrollY={80} />
    <Caption items={[{ at: T(1, 8.5), text: "« Envoyer un colis »" }]} />
  </Out>
);

/** 3. Étape 1 : point de récupération (9,8 → 16,8 s) */
const Scene3: React.FC = () => (
  <Out frames={FR[2]}>
    <StepBadge n={1} of={4} />
    <Words text="Point de récupération" top={300} size={80} stagger={4} />
    <ScreenPhone
      img="c2-recuperation"
      h={1000}
      scroll={[[0, 0], [T(2, 14.2), 0], [T(2, 14.9), 150]]}
      rings={[
        { x: 16, y: 221, w: 398, h: 52, at: T(2, 12.3) },
        { x: 16, y: 280, w: 398, h: 130, at: T(2, 13.9) },
        { x: 16, y: 479, w: 398, h: 134, at: T(2, 14.9) },
      ]}
    />
    <Caption
      items={[
        { at: T(2, 12.3), n: "1", text: "Ma position" },
        { at: T(2, 13.9), n: "2", text: "Ou sur la carte" },
        { at: T(2, 14.9), n: "3", text: "Nom et téléphone" },
      ]}
    />
  </Out>
);

/** 4. Étape 2 : destination (16,8 → 21,2 s) */
const Scene4: React.FC = () => (
  <Out frames={FR[3]}>
    <StepBadge n={2} of={4} />
    <Words text="La destination" top={300} size={88} stagger={4} />
    <ScreenPhone
      img="c3-destination"
      h={1000}
      scroll={[[0, 0], [T(3, 18.2), 0], [T(3, 18.8), 150]]}
      rings={[
        { x: 16, y: 290, w: 398, h: 194, at: T(3, 17.9) },
        { x: 16, y: 490, w: 398, h: 134, at: T(3, 18.9) },
      ]}
    />
    <Caption
      items={[
        { at: T(3, 17.9), n: "1", text: "Le lieu de livraison" },
        { at: T(3, 18.9), n: "2", text: "Le destinataire" },
      ]}
    />
  </Out>
);

/** 5. Étape 3 : le colis (21,2 → 26,4 s) */
const Scene5: React.FC = () => (
  <Out frames={FR[4]}>
    <StepBadge n={3} of={4} />
    <Words text="Le colis" top={300} size={96} stagger={4} />
    <ScreenPhone
      img="c4-colis"
      h={1100}
      scroll={[[0, 0], [T(4, 23.4), 0], [T(4, 23.9), 330]]}
      rings={[
        { x: 286, y: 182, w: 126, h: 104, at: T(4, 23.0) },
        { x: 30, y: 628, w: 196, h: 40, at: T(4, 23.9) },
        { x: 16, y: 800, w: 398, h: 52, at: T(4, 24.4) },
        { x: 16, y: 856, w: 398, h: 60, at: T(4, 25.5) },
      ]}
    />
    <Caption
      items={[
        { at: T(4, 23.0), n: "1", text: "Le type" },
        { at: T(4, 23.9), n: "2", text: "La taille" },
        { at: T(4, 24.4), n: "3", text: "La quantité" },
        { at: T(4, 25.5), n: "4", text: "Fragile ?" },
      ]}
    />
  </Out>
);

/** 6. Étape 4 : transport, prix, paiement, confirmation (26,4 → 36,65 s) */
const Scene6: React.FC = () => {
  const frame = useCurrentFrame();
  const price = usePop(T(5, 29.1), 10, 160);
  return (
    <Out frames={FR[5]}>
      <StepBadge n={4} of={4} />
      <Words text="Prix et paiement" top={300} size={88} stagger={4} />
      <ScreenPhone
        img="c5-confirmation"
        h={1500}
        scroll={[[0, 250], [T(5, 30.2), 250], [T(5, 30.8), 560], [T(5, 34.4), 560], [T(5, 35.0), 740]]}
        rings={[
          { x: 16, y: 380, w: 398, h: 84, at: T(5, 27.4) },
          { x: 16, y: 515, w: 398, h: 136, at: T(5, 28.8) },
          { x: 16, y: 722, w: 398, h: 66, at: T(5, 30.9) },
          { x: 16, y: 802, w: 398, h: 66, at: T(5, 31.9) },
          { x: 16, y: 874, w: 398, h: 152, at: T(5, 32.9) },
          { x: 16, y: 1428, w: 398, h: 56, at: T(5, 35.3) },
        ]}
      />
      <Tap x={230} y={1456} at={T(5, 35.8)} scrollY={740} />
      <div
        style={{
          position: "absolute",
          top: 1460,
          right: 40,
          padding: "16px 34px",
          borderRadius: 999,
          background: C.orange,
          color: C.white,
          fontFamily,
          fontWeight: 800,
          fontSize: 50,
          boxShadow: "0 16px 36px rgba(0,0,0,0.3)",
          transform: `scale(${price}) rotate(${4 * price}deg)`,
          opacity: frame < T(5, 29.1) || frame > T(5, 30.7) ? 0 : 1,
        }}
      >
        2 000 FCFA
      </div>
      <Caption
        items={[
          { at: T(5, 27.4), n: "1", text: "Moyen de transport" },
          { at: T(5, 28.8), n: "2", text: "Le prix, avant de confirmer" },
          { at: T(5, 30.9), n: "3", text: "Espèces" },
          { at: T(5, 31.9), n: "3", text: "Ou à la livraison" },
          { at: T(5, 32.9), n: "3", text: "Orange Money · Moov Money" },
          { at: T(5, 35.3), text: "Confirmer la livraison" },
        ]}
      />
    </Out>
  );
};

/** 7. Suivi en direct et code de livraison (36,65 → 41,9 s) */
const Scene7: React.FC = () => (
  <Out frames={FR[6]}>
    <Words text="Suis ton livreur" top={250} size={92} stagger={4} />
    <ScreenPhone
      img="c6-suivi"
      h={1500}
      scroll={[[0, 60], [T(6, 39.0), 60], [T(6, 39.6), 330]]}
      rings={[
        { x: 16, y: 160, w: 398, h: 284, at: T(6, 37.4) },
        { x: 16, y: 728, w: 398, h: 200, at: T(6, 39.7) },
      ]}
    />
    <Caption
      items={[
        { at: T(6, 37.4), text: "En direct sur la carte" },
        { at: T(6, 39.7), text: "Remis avec ton code" },
      ]}
    />
  </Out>
);

/** 8. Fin (41,9 → 46,9 s) */
const Scene8: React.FC = () => {
  const frame = useCurrentFrame();
  const logo = usePop(T(7, 42.0), 10, 150);
  const pill = usePop(T(7, 44.4), 12);
  return (
    <AbsoluteFill style={{ fontFamily }}>
      <div style={{ position: "absolute", top: 330, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <Img src={staticFile("logo.png")} style={{ width: 300, height: 300, borderRadius: 76, transform: `scale(${logo}) rotate(${(1 - logo) * -20}deg)`, boxShadow: "0 30px 70px rgba(0,0,0,0.35)" }} />
      </div>
      <div style={{ position: "absolute", top: 670, left: 0, right: 0, textAlign: "center", fontWeight: 800, fontSize: 140, letterSpacing: -5, color: C.white, opacity: interpolate(frame, [T(7, 42.0), T(7, 42.3)], [0, 1], clamp) }}>
        Telima
      </div>
      <div style={{ position: "absolute", top: 835, left: 0, right: 0, textAlign: "center", fontWeight: 800, fontSize: 70, color: C.mint, opacity: interpolate(frame, [T(7, 42.2), T(7, 42.5)], [0, 1], clamp) }}>
        Livraison de colis
      </div>
      <Words text="Tes colis livrés en toute simplicité" top={1000} size={74} delay={T(7, 42.66)} stagger={5} />
      <PhotoCard src="moto-livreur" at={T(7, 43.4)} x={250} y={1170} w={580} h={340} rotate={-2} from="right" />
      <div style={{ position: "absolute", top: 1560, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 18, padding: "14px 18px 14px 32px", borderRadius: 999, background: C.greenDark, border: "3px solid rgba(255,255,255,0.35)", transform: `scale(${pill})` }}>
          <span style={{ color: C.white, fontWeight: 700, fontSize: 40 }}>Commander sur</span>
          <span style={{ padding: "14px 34px", borderRadius: 999, background: C.white, color: C.greenDark, fontWeight: 800, fontSize: 48 }}>{SITE}</span>
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const CommanderVideo: React.FC = () => {
  const scenes = [Scene1, Scene2, Scene3, Scene4, Scene5, Scene6, Scene7, Scene8];
  return (
    <AbsoluteFill>
      <Audio src={staticFile("voix-off-commande.mp3")} />
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
