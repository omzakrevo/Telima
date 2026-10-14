import { Composition } from "remotion";
import { RestaurantVideo, TOTAL_FRAMES, FPS } from "./RestaurantVideo";
import { BoutiqueVideo, BOUTIQUE_TOTAL_FRAMES, BOUTIQUE_FPS } from "./BoutiqueVideo";

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
    </>
  );
};
