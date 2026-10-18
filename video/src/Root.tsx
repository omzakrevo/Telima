import { Composition } from "remotion";
import { RestaurantVideo, TOTAL_FRAMES, FPS } from "./RestaurantVideo";
import { BoutiqueVideo, BOUTIQUE_TOTAL_FRAMES, BOUTIQUE_FPS } from "./BoutiqueVideo";
import { TicketsVideo, TICKETS_TOTAL_FRAMES, TICKETS_FPS } from "./TicketsVideo";
import { LivreurVideo, LIVREUR_TOTAL_FRAMES, LIVREUR_FPS } from "./LivreurVideo";
import { CommanderVideo, COMMANDER_TOTAL_FRAMES, COMMANDER_FPS } from "./CommanderVideo";
import { LiveVideo, LIVE_TOTAL_FRAMES, LIVE_FPS } from "./LiveVideo";
import { BoutiqueTutoVideo, BOUTIQUE_TUTO_TOTAL_FRAMES, RestaurantTutoVideo, RESTAURANT_TUTO_TOTAL_FRAMES, TUTO_FPS } from "./CommercesTuto";

export const Root: React.FC = () => {
  return (
    <>
    <Composition
      id="RestaurantsVertical"
      component={RestaurantVideo}
      durationInFrames={TOTAL_FRAMES}
      fps={FPS}
      width={1080}
      height={1920}
    />
    <Composition
      id="BoutiquesVertical"
      component={BoutiqueVideo}
      durationInFrames={BOUTIQUE_TOTAL_FRAMES}
      fps={BOUTIQUE_FPS}
      width={1080}
      height={1920}
    />
    <Composition
      id="TicketsVertical"
      component={TicketsVideo}
      durationInFrames={TICKETS_TOTAL_FRAMES}
      fps={TICKETS_FPS}
      width={1080}
      height={1920}
    />
    <Composition
      id="LivreurVertical"
      component={LivreurVideo}
      durationInFrames={LIVREUR_TOTAL_FRAMES}
      fps={LIVREUR_FPS}
      width={1080}
      height={1920}
    />
    <Composition
      id="CommanderVertical"
      component={CommanderVideo}
      durationInFrames={COMMANDER_TOTAL_FRAMES}
      fps={COMMANDER_FPS}
      width={1080}
      height={1920}
    />
    <Composition
      id="BoutiqueTutoVertical"
      component={BoutiqueTutoVideo}
      durationInFrames={BOUTIQUE_TUTO_TOTAL_FRAMES}
      fps={TUTO_FPS}
      width={1080}
      height={1920}
    />
    <Composition
      id="RestaurantTutoVertical"
      component={RestaurantTutoVideo}
      durationInFrames={RESTAURANT_TUTO_TOTAL_FRAMES}
      fps={TUTO_FPS}
      width={1080}
      height={1920}
    />
    <Composition
      id="LiveVertical"
      component={LiveVideo}
      durationInFrames={LIVE_TOTAL_FRAMES}
      fps={LIVE_FPS}
      width={1080}
      height={1920}
    />
    </>
  );
};
