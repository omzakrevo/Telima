import React from "react";
import { AbsoluteFill, Audio, Easing, Img, Series, interpolate, staticFile, useCurrentFrame } from "remotion";
import { Backdrop, C, Highlight, Icon3D, Out, Words, clamp, fontFamily, usePop } from "./BoutiqueVideo";
import { Caption, FPS, Ring, ScreenPhone, StepBadge, Svg, Tap, ICON_SCOOTER, sec } from "./EcranTelephone";

/*
 * Vidéos verticales 9:16 « pas à pas » : créer sa boutique (BoutiqueTutoVertical) et créer son restaurant
 * (RestaurantTutoVertical) sur Telima, avec les VRAIS écrans de l'application (video/public/ecrans/x1-*, b*-*, r*-*,
 * produits par video/capture/commerces_shots_test.dart ; cartes OpenStreetMap posées par video/capture/poser_tuiles.py)
 * et la voix off « Léo » (ElevenLabs). Les scènes sont calées sur la voix (horodatage mot à mot) :
 * si la voix change, reprendre CUTS et les secondes indiquées (secondes absolues dans la voix).
 */

export const TUTO_FPS = FPS;
const SITE = "telimatchi.com";

const Chip: React.FC<{ text: string; at: number; x: number; y: number; bg?: string; color?: string }> = ({ text, at, x, y, bg = C.white, color = C.greenDark }) => {
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
        background: bg,
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

/** Affiche `children` seulement entre `from` et `to` (images de la scène). */
const Between: React.FC<{ from?: number; to?: number; children: React.ReactNode }> = ({ from = 0, to = 1e9, children }) => {
  const frame = useCurrentFrame();
  return frame >= from && frame < to ? <AbsoluteFill>{children}</AbsoluteFill> : null;
};

type Cfg = {
  audio: string;
  cuts: number[];
  // accroche
  hookQ: string;
  hookIcon: string;
  hookA: string;
  hookAt: number;
  hookB: string;
  hookBAt: number;
  hookStepAt: number;
  // étape 1 : accueil → Plus → Ma boutique / Mon restaurant → Créer
  plusAt: number;
  itemLabel: string;
  itemRing: Ring;
  itemAt: number;
  emptyImg: string;
  createAt: number;
  createLabel: string;
  // étape 2 : formulaire
  formImg: string;
  formTitle: string;
  form: { at: number; n?: string; text: string; ring: [number, number, number, number] }[];
  formScroll: [number, number][];
  formTapAt: number;
  // étape 5 : commandes
  ordersImg: string;
  orderAcceptAt: number;
  orderPrepAt: number;
  orderDriverAt: number;
  orderRingH: number;
  acceptY: number;
  prepY: number;
  // fin
  outroAt: number;
  outroSub: string;
  outroLine: string;
  outroLineAt: number;
};

const makeT = (cuts: number[]) => (i: number, x: number) => sec(x) - sec(cuts[i]);

const Hook: React.FC<{ c: Cfg; frames: number }> = ({ c, frames }) => {
  const frame = useCurrentFrame();
  const T = makeT(c.cuts);
  const first = interpolate(frame, [T(0, c.hookAt - 0.25), T(0, c.hookAt)], [1, 0], clamp);
  const second = interpolate(frame, [T(0, c.hookAt - 0.1), T(0, c.hookAt + 0.15)], [0, 1], clamp);
  return (
    <Out frames={frames}>
      <div style={{ opacity: first }}>
        <Words text={c.hookQ} top={280} size={100} stagger={3} />
        <div style={{ position: "absolute", top: 760, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
          <Icon3D name={c.hookIcon} size={480} delay={4} float={10} />
        </div>
      </div>
      <div style={{ opacity: second }}>
        <Words text={c.hookA} top={300} size={112} delay={T(0, c.hookAt)} stagger={5} />
        <Highlight text={c.hookB} top={470} delay={T(0, c.hookBAt)} size={100} bg={C.orange} color={C.white} />
        <div style={{ position: "absolute", top: 760, left: 0, right: 0, display: "flex", justifyContent: "center", gap: 50 }}>
          <Icon3D name={c.hookIcon} size={300} delay={T(0, c.hookAt + 0.2)} float={12} />
          <Icon3D name="convenience_store" size={260} delay={T(0, c.hookBAt + 0.3)} float={9} style={{ marginTop: 50 }} />
        </div>
        <Highlight text="étape par étape" top={1430} delay={T(0, c.hookStepAt)} size={78} />
      </div>
    </Out>
  );
};

const Step1: React.FC<{ c: Cfg; frames: number }> = ({ c, frames }) => {
  const T = makeT(c.cuts);
  const swap = T(1, c.createAt - 0.25);
  return (
    <Out frames={frames}>
      <StepBadge n={1} of={5} />
      <Words text="Sur l'accueil" top={300} size={92} stagger={4} />
      <Between to={swap}>
        <ScreenPhone
          img="x1-plus"
          h={932}
          scroll={[[0, 0], [T(1, c.plusAt + 0.3), 0], [T(1, c.plusAt + 0.8), 175]]}
          rings={[
            { x: 337, y: 294, w: 74, h: 94, at: T(1, c.plusAt) },
            { ...c.itemRing, at: T(1, c.itemAt) },
          ]}
        />
        <Tap x={373} y={340} at={T(1, c.plusAt + 0.2)} scrollY={0} />
        <Tap x={c.itemRing.x + c.itemRing.w / 2} y={c.itemRing.y + c.itemRing.h / 2} at={T(1, c.itemAt + 0.35)} scrollY={175} />
      </Between>
      <Between from={swap}>
        <ScreenPhone img={c.emptyImg} h={932} enter={swap} scroll={[[0, 175]]} rings={[{ x: 240, y: 858, w: 176, h: 60, at: T(1, c.createAt) }]} />
        <Tap x={328} y={888} at={T(1, c.createAt + 0.5)} scrollY={175} />
      </Between>
      <Caption
        items={[
          { at: T(1, c.plusAt), n: "1", text: "Touche « Plus »" },
          { at: T(1, c.itemAt), n: "2", text: `« ${c.itemLabel} »` },
          { at: T(1, c.createAt), n: "3", text: c.createLabel },
        ]}
      />
    </Out>
  );
};

const Step2: React.FC<{ c: Cfg; frames: number }> = ({ c, frames }) => {
  const T = makeT(c.cuts);
  return (
    <Out frames={frames}>
      <StepBadge n={2} of={5} />
      <Words text={c.formTitle} top={300} size={84} stagger={4} />
      <ScreenPhone
        img={c.formImg}
        h={2000}
        scroll={c.formScroll.map(([t, y]) => [T(2, t), y] as [number, number])}
        rings={c.form.map((f) => ({ x: f.ring[0], y: f.ring[1], w: f.ring[2], h: f.ring[3], at: T(2, f.at) }))}
      />
      <Tap x={215} y={1671} at={T(2, c.formTapAt)} scrollY={1000} />
      <Caption items={c.form.map((f) => ({ at: T(2, f.at), n: f.n, text: f.text }))} />
    </Out>
  );
};

const Step5: React.FC<{ c: Cfg; frames: number }> = ({ c, frames }) => {
  const frame = useCurrentFrame();
  const T = makeT(c.cuts);
  const ride = interpolate(frame, [T(5, c.orderDriverAt), T(5, c.orderDriverAt + 1.8)], [-300, 1340], { ...clamp, easing: Easing.inOut(Easing.cubic) });
  return (
    <Out frames={frames}>
      <StepBadge n={5} of={5} />
      <Words text="Les commandes arrivent" top={300} size={80} stagger={4} />
      <ScreenPhone
        img={c.ordersImg}
        h={1300}
        scroll={[[0, 0], [T(5, c.orderPrepAt - 0.4), 0], [T(5, c.orderPrepAt + 0.1), 240]]}
        rings={[
          { x: 16, y: 300, w: 398, h: c.orderRingH, at: T(5, c.cuts[5] + 0.7) },
          { x: 230, y: c.acceptY, w: 184, h: 54, at: T(5, c.orderAcceptAt) },
          { x: 16, y: c.prepY, w: 398, h: 270, at: T(5, c.orderPrepAt) },
        ]}
      />
      <Tap x={322} y={c.acceptY + 27} at={T(5, c.orderAcceptAt + 0.25)} scrollY={0} />
      <div style={{ position: "absolute", top: 1440, left: ride, display: "flex", alignItems: "flex-end" }}>
        <Svg d={ICON_SCOOTER} size={190} color="rgba(255,255,255,0.95)" />
        <Icon3D name="package" size={96} style={{ marginLeft: -66, marginBottom: 90 }} />
      </div>
      <Caption
        items={[
          { at: T(5, c.cuts[5] + 0.7), text: "Nouvelle commande" },
          { at: T(5, c.orderAcceptAt), n: "1", text: "Tu acceptes" },
          { at: T(5, c.orderPrepAt), n: "2", text: "Tu prépares" },
          { at: T(5, c.orderDriverAt), n: "3", text: "Un livreur Telima livre" },
        ]}
      />
    </Out>
  );
};

const Outro: React.FC<{ c: Cfg; i: number }> = ({ c, i }) => {
  const frame = useCurrentFrame();
  const T = makeT(c.cuts);
  const logo = usePop(T(i, c.outroAt + 0.1), 10, 150);
  const pill = usePop(T(i, c.outroAt + 2.0), 12);
  return (
    <AbsoluteFill style={{ fontFamily }}>
      <div style={{ position: "absolute", top: 330, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <Img src={staticFile("logo.png")} style={{ width: 300, height: 300, borderRadius: 76, transform: `scale(${logo}) rotate(${(1 - logo) * -20}deg)`, boxShadow: "0 30px 70px rgba(0,0,0,0.35)" }} />
      </div>
      <div style={{ position: "absolute", top: 670, left: 0, right: 0, textAlign: "center", fontWeight: 800, fontSize: 140, letterSpacing: -5, color: C.white, opacity: interpolate(frame, [T(i, c.outroAt + 0.1), T(i, c.outroAt + 0.4)], [0, 1], clamp) }}>
        Telima
      </div>
      <div style={{ position: "absolute", top: 835, left: 0, right: 0, textAlign: "center", fontWeight: 800, fontSize: 70, color: C.mint, opacity: interpolate(frame, [T(i, c.outroAt + 0.3), T(i, c.outroAt + 0.6)], [0, 1], clamp) }}>
        {c.outroSub}
      </div>
      <Words text={c.outroLine} top={1000} size={80} delay={T(i, c.outroLineAt)} stagger={5} />
      <div style={{ position: "absolute", top: 1300, left: 0, right: 0, display: "flex", justifyContent: "center", gap: 60 }}>
        <Icon3D name={c.hookIcon} size={170} delay={T(i, c.outroLineAt + 0.6)} float={8} />
        <Icon3D name="motor_scooter" size={170} delay={T(i, c.outroLineAt + 0.8)} float={8} />
      </div>
      <div style={{ position: "absolute", top: 1560, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 18, padding: "14px 18px 14px 32px", borderRadius: 999, background: C.greenDark, border: "3px solid rgba(255,255,255,0.35)", transform: `scale(${pill})` }}>
          <span style={{ color: C.white, fontWeight: 700, fontSize: 40 }}>Créer sur</span>
          <span style={{ padding: "14px 34px", borderRadius: 999, background: C.white, color: C.greenDark, fontWeight: 800, fontSize: 48 }}>{SITE}</span>
        </div>
      </div>
    </AbsoluteFill>
  );
};

/** Formulaire commun boutique / restaurant (mêmes positions à l'écran, 430 px CSS). */
const formRings = (labels: string[], times: number[]) => {
  const rects: [number, number, number, number][] = [
    [16, 151, 398, 62], // nom
    [16, 219, 398, 70], // type / spécialités
    [16, 415, 398, 62], // téléphone
    [16, 483, 398, 62], // quartier
    [16, 551, 398, 70], // horaires
    [16, 640, 398, 172], // photos
    [16, 826, 398, 172], // service
    [16, 1148, 398, 330], // position
    [16, 1643, 398, 56], // bouton
  ];
  return labels.map((text, k) => ({ at: times[k], n: k < 5 ? String(k + 1) : undefined, text, ring: rects[k] }));
};

// ───────────────────────── Boutique ─────────────────────────

const BOUTIQUE: Cfg = {
  audio: "voix-off-boutique-tuto.mp3",
  cuts: [0, 6.8, 12.65, 24.95, 31.75, 38.05, 43.95, 48.6],
  hookQ: "Tu vends des habits ?",
  hookIcon: "shopping_bags",
  hookA: "Crée ta boutique",
  hookAt: 2.8,
  hookB: "sur Telima",
  hookBAt: 3.4,
  hookStepAt: 5.3,
  plusAt: 8.7,
  itemLabel: "Ma boutique",
  itemRing: { x: 112, y: 652, w: 108, h: 112, at: 0 },
  itemAt: 9.86,
  emptyImg: "b2-vide",
  createAt: 11.08,
  createLabel: "Créer une boutique",
  formImg: "b3-formulaire",
  formTitle: "Ta boutique",
  form: formRings(
    ["Nom de la boutique", "Type de boutique", "Téléphone", "Quartier", "Horaires", "Logo et couverture", "Retrait ou livraison", "Place-la sur la carte", "Créer ma boutique"],
    [13.7, 14.8, 15.6, 16.5, 17.3, 18.2, 19.24, 21.5, 23.2],
  ),
  formScroll: [[0, 0], [17.4, 0], [18.1, 300], [20.9, 300], [21.5, 1000]],
  formTapAt: 23.8,
  ordersImg: "b7-commandes",
  orderAcceptAt: 40.44,
  orderPrepAt: 41.18,
  orderDriverAt: 42.08,
  orderRingH: 330,
  acceptY: 585,
  prepY: 660,
  outroAt: 43.95,
  outroSub: "Boutiques",
  outroLine: "Ta boutique en ligne",
  outroLineAt: 44.86,
};

const BoutiqueStep3: React.FC<{ frames: number }> = ({ frames }) => {
  const T = makeT(BOUTIQUE.cuts);
  return (
    <Out frames={frames}>
      <StepBadge n={3} of={5} />
      <Words text="Ajoute tes articles" top={300} size={84} stagger={4} />
      <ScreenPhone
        img="b4-article"
        h={1500}
        scroll={[[0, 560], [T(3, 29.6), 560], [T(3, 30.1), 760]]}
        rings={[
          { x: 16, y: 617, w: 398, h: 64, at: T(3, 27.3) },
          { x: 16, y: 696, w: 398, h: 182, at: T(3, 27.96) },
          { x: 16, y: 917, w: 398, h: 64, at: T(3, 28.74) },
          { x: 16, y: 985, w: 398, h: 94, at: T(3, 29.42) },
          { x: 16, y: 1073, w: 398, h: 94, at: T(3, 30.1) },
          { x: 16, y: 1161, w: 398, h: 94, at: T(3, 30.92) },
        ]}
      />
      <Caption
        items={[
          { at: T(3, 27.3), n: "1", text: "Le nom" },
          { at: T(3, 27.96), n: "2", text: "Les photos" },
          { at: T(3, 28.74), n: "3", text: "Le prix" },
          { at: T(3, 29.42), n: "4", text: "Les tailles" },
          { at: T(3, 30.1), n: "5", text: "Les couleurs" },
          { at: T(3, 30.92), n: "6", text: "Le stock" },
        ]}
      />
    </Out>
  );
};

const BoutiqueStep4: React.FC<{ frames: number }> = ({ frames }) => {
  const T = makeT(BOUTIQUE.cuts);
  return (
    <Out frames={frames}>
      <StepBadge n={4} of={5} />
      <Words text="Partage ton lien" top={300} size={90} stagger={4} />
      <ScreenPhone
        img="b6-lien"
        h={1100}
        rings={[
          { x: 16, y: 192, w: 398, h: 100, at: T(4, 32.7) },
          { x: 230, y: 302, w: 184, h: 56, at: T(4, 33.92) },
          { x: 34, y: 362, w: 382, h: 54, at: T(4, 36.58) },
        ]}
      />
      <Tap x={318} y={330} at={T(4, 34.3)} scrollY={0} />
      <Chip text="WhatsApp" at={T(4, 34.54)} x={60} y={1500} bg="#25D366" color={C.white} />
      <Chip text="Facebook" at={T(4, 35.22)} x={390} y={1530} bg="#1877F2" color={C.white} />
      <Chip text="TikTok" at={T(4, 35.86)} x={720} y={1500} bg={C.ink} color={C.white} />
      <Caption
        items={[
          { at: T(4, 32.7), text: "Ton lien est prêt" },
          { at: T(4, 33.92), text: "Partage-le" },
          { at: T(4, 36.58), text: "QR code à imprimer" },
        ]}
      />
    </Out>
  );
};

export const BOUTIQUE_TUTO_FR = BOUTIQUE.cuts.slice(1).map((c, i) => sec(c) - sec(BOUTIQUE.cuts[i]));
export const BOUTIQUE_TUTO_TOTAL_FRAMES = sec(BOUTIQUE.cuts[BOUTIQUE.cuts.length - 1]);

export const BoutiqueTutoVideo: React.FC = () => {
  const FR = BOUTIQUE_TUTO_FR;
  const scenes = [
    <Hook c={BOUTIQUE} frames={FR[0]} />,
    <Step1 c={BOUTIQUE} frames={FR[1]} />,
    <Step2 c={BOUTIQUE} frames={FR[2]} />,
    <BoutiqueStep3 frames={FR[3]} />,
    <BoutiqueStep4 frames={FR[4]} />,
    <Step5 c={BOUTIQUE} frames={FR[5]} />,
    <Outro c={BOUTIQUE} i={6} />,
  ];
  return (
    <AbsoluteFill>
      <Audio src={staticFile(BOUTIQUE.audio)} />
      <Backdrop />
      <Series>
        {scenes.map((s, i) => (
          <Series.Sequence key={i} durationInFrames={FR[i]}>
            {s}
          </Series.Sequence>
        ))}
      </Series>
    </AbsoluteFill>
  );
};

// ───────────────────────── Restaurant ─────────────────────────

const RESTAURANT: Cfg = {
  audio: "voix-off-restaurant-tuto.mp3",
  cuts: [0, 6.05, 11.8, 25.35, 31.05, 36.6, 42.5, 47.0],
  hookQ: "Tu as un restaurant ou un maquis ?",
  hookIcon: "pot_of_food",
  hookA: "Mets ton menu",
  hookAt: 1.92,
  hookB: "sur Telima",
  hookBAt: 2.6,
  hookStepAt: 4.74,
  plusAt: 7.88,
  itemLabel: "Mon restaurant",
  itemRing: { x: 312, y: 526, w: 104, h: 112, at: 0 },
  itemAt: 8.98,
  emptyImg: "r2-vide",
  createAt: 10.18,
  createLabel: "Créer un restaurant",
  formImg: "r3-formulaire",
  formTitle: "Ton restaurant",
  form: formRings(
    ["Nom du restaurant", "Tes spécialités", "Téléphone", "Quartier", "Horaires", "Logo et couverture", "Retrait ou livraison", "Place-le sur la carte", "Créer mon restaurant"],
    [12.84, 13.96, 15.04, 15.92, 16.78, 17.52, 19.8, 21.68, 23.32],
  ),
  formScroll: [[0, 0], [16.9, 0], [17.5, 300], [21.1, 300], [21.7, 1000]],
  formTapAt: 23.9,
  ordersImg: "r8-commandes",
  orderAcceptAt: 38.82,
  orderPrepAt: 39.52,
  orderDriverAt: 40.42,
  orderRingH: 300,
  acceptY: 555,
  prepY: 630,
  outroAt: 42.5,
  outroSub: "Restaurants",
  outroLine: "Ton restaurant en ligne",
  outroLineAt: 43.38,
};

const RestaurantStep3: React.FC<{ frames: number }> = ({ frames }) => {
  const T = makeT(RESTAURANT.cuts);
  const swap = T(3, 28.1);
  return (
    <Out frames={frames}>
      <StepBadge n={3} of={5} />
      <Words text="Ton menu" top={300} size={96} stagger={4} />
      <Between to={swap}>
        <ScreenPhone img="r4-categorie" h={1100} scroll={[[0, 120]]} rings={[{ x: 84, y: 440, w: 262, h: 200, at: T(3, 27.14) }]} />
      </Between>
      <Between from={swap}>
        <ScreenPhone
          img="r5-plat"
          h={1300}
          enter={swap}
          scroll={[[0, 520]]}
          rings={[
            { x: 104, y: 838, w: 310, h: 64, at: T(3, 28.82) },
            { x: 16, y: 832, w: 90, h: 90, at: T(3, 29.58) },
            { x: 16, y: 921, w: 398, h: 64, at: T(3, 30.18) },
          ]}
        />
      </Between>
      <Caption
        items={[
          { at: T(3, 27.14), n: "1", text: "Tes catégories" },
          { at: T(3, 28.82), n: "2", text: "Tes plats" },
          { at: T(3, 29.58), n: "3", text: "La photo" },
          { at: T(3, 30.18), n: "4", text: "Le prix" },
        ]}
      />
    </Out>
  );
};

const RestaurantStep4: React.FC<{ frames: number }> = ({ frames }) => {
  const T = makeT(RESTAURANT.cuts);
  const swap = T(4, 33.85);
  return (
    <Out frames={frames}>
      <StepBadge n={4} of={5} />
      <Words text="Partage ton lien" top={300} size={90} stagger={4} />
      <Between to={swap}>
        <ScreenPhone
          img="r7-lien"
          h={1100}
          rings={[
            { x: 16, y: 192, w: 398, h: 100, at: T(4, 31.84) },
            { x: 34, y: 362, w: 382, h: 54, at: T(4, 33.02) },
          ]}
        />
      </Between>
      <Between from={swap}>
        <ScreenPhone
          img="r9-page-client"
          h={1300}
          enter={swap}
          scroll={[[0, 0], [T(4, 34.9), 0], [T(4, 35.6), 300]]}
          rings={[{ x: 16, y: 505, w: 398, h: 400, at: T(4, 35.2) }]}
        />
      </Between>
      <Caption
        items={[
          { at: T(4, 31.84), text: "Ton lien" },
          { at: T(4, 33.02), text: "Ton QR code" },
          { at: T(4, 33.96), text: "Tes clients voient ton menu" },
          { at: T(4, 35.2), text: "Et commandent directement" },
        ]}
      />
    </Out>
  );
};

export const RESTAURANT_TUTO_FR = RESTAURANT.cuts.slice(1).map((c, i) => sec(c) - sec(RESTAURANT.cuts[i]));
export const RESTAURANT_TUTO_TOTAL_FRAMES = sec(RESTAURANT.cuts[RESTAURANT.cuts.length - 1]);

export const RestaurantTutoVideo: React.FC = () => {
  const FR = RESTAURANT_TUTO_FR;
  const scenes = [
    <Hook c={RESTAURANT} frames={FR[0]} />,
    <Step1 c={RESTAURANT} frames={FR[1]} />,
    <Step2 c={RESTAURANT} frames={FR[2]} />,
    <RestaurantStep3 frames={FR[3]} />,
    <RestaurantStep4 frames={FR[4]} />,
    <Step5 c={RESTAURANT} frames={FR[5]} />,
    <Outro c={RESTAURANT} i={6} />,
  ];
  return (
    <AbsoluteFill>
      <Audio src={staticFile(RESTAURANT.audio)} />
      <Backdrop />
      <Series>
        {scenes.map((s, i) => (
          <Series.Sequence key={i} durationInFrames={FR[i]}>
            {s}
          </Series.Sequence>
        ))}
      </Series>
    </AbsoluteFill>
  );
};
