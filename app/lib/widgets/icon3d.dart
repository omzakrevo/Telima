import 'package:flutter/material.dart';

import 'motion.dart';

/// Illustrations 3D (Fluent Emoji de Microsoft, licence MIT — voir assets/3d/LICENSE-fluent-emoji.txt).
class Ico3D {
  static const _d = 'assets/3d/';
  static const package = '${_d}package.webp';
  static const scooter = '${_d}motor_scooter.webp';
  static const truck = '${_d}delivery_truck.webp';
  static const moneyBag = '${_d}money_bag.webp';
  static const purse = '${_d}purse.webp';
  static const bell = '${_d}bell.webp';
  static const receipt = '${_d}receipt.webp';
  static const headphone = '${_d}headphone.webp';
  static const store = '${_d}convenience_store.webp';
  static const pin = '${_d}round_pushpin.webp';
  static const map = '${_d}world_map.webp';
  static const locked = '${_d}locked.webp';
  static const stopwatch = '${_d}stopwatch.webp';
  static const phone = '${_d}mobile_phone.webp';
  static const chartUp = '${_d}chart_increasing.webp';
  static const barChart = '${_d}bar_chart.webp';
  static const check = '${_d}check_mark_button.webp';
  static const hourglass = '${_d}hourglass_not_done.webp';
  static const people = '${_d}busts_in_silhouette.webp';
  static const person = '${_d}bust_in_silhouette.webp';
  static const gear = '${_d}gear.webp';
  static const star = '${_d}star.webp';
  static const card = '${_d}credit_card.webp';
  static const clipboard = '${_d}clipboard.webp';
  static const cross = '${_d}cross_mark.webp';
  static const chat = '${_d}speech_balloon.webp';
  static const key = '${_d}key.webp';
  static const pencil = '${_d}pencil.webp';
  static const door = '${_d}door.webp';
  static const shield = '${_d}shield.webp';
  static const rocket = '${_d}rocket.webp';
  static const gift = '${_d}wrapped_gift.webp';
  static const taxi = '${_d}taxi.webp';
  static const car = '${_d}automobile.webp';
  static const bags = '${_d}shopping_bags.webp';
  static const cart = '${_d}shopping_cart.webp';
  static const pill = '${_d}pill.webp';
  static const food = '${_d}pot_of_food.webp';
}

/// Icône 3D avec ombre portée douce (effet de relief) et flottement optionnel.
class Icon3D extends StatelessWidget {
  const Icon3D(this.asset, {super.key, this.size = 40, this.float = false, this.shadow = true});
  final String asset;
  final double size;
  final bool float;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget img = Image.asset(
      asset,
      width: size,
      height: size,
      cacheWidth: (size * dpr).round().clamp(32, 320),
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
    );
    if (shadow) {
      img = Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        Positioned(
          bottom: -size * 0.04,
          child: Container(
            width: size * 0.62,
            height: size * 0.12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: size * 0.14)],
            ),
          ),
        ),
        img,
      ]);
    }
    return float ? Floating(amplitude: size * 0.06, child: img) : img;
  }
}
