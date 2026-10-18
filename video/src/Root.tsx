import { Composition } from "remotion";
import { RestaurantVideo, TOTAL_FRAMES, FPS } from "./RestaurantVideo";
import { BoutiqueVideo, BOUTIQUE_TOTAL_FRAMES, BOUTIQUE_FPS } from "./BoutiqueVideo";
import { TicketsVideo, TICKETS_TOTAL_FRAMES, TICKETS_FPS } from "./TicketsVideo";
import { LivreurVideo, LIVREUR_TOTAL_FRAMES, LIVREUR_FPS } from "./LivreurVideo";
import { CommanderVideo, COMMANDER_TOTAL_FRAMES, COMMANDER_FPS } from "./CommanderVideo";

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
    </>
  );
};
