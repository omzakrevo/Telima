import { Composition } from "remotion";
import { RestaurantVideo, TOTAL_FRAMES, FPS } from "./RestaurantVideo";

export const Root: React.FC = () => {
  return (
    <Composition
      id="RestaurantsVertical"
      component={RestaurantVideo}
      durationInFrames={TOTAL_FRAMES}
      fps={FPS}
      width={1080}
      height={1920}
    />
  );
};
