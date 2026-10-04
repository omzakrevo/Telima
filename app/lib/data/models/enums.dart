import 'package:flutter/material.dart';

T _byName<T extends Enum>(List<T> values, String? name, T fallback) =>
    values.firstWhere((e) => e.name == name, orElse: () => fallback);

enum UserRole {
  client('Client'),
  driver('Livreur'),
  admin('Administrateur'),
  operator('Opérateur');

  const UserRole(this.label);
  final String label;
  static UserRole parse(String? v) => _byName(values, v, UserRole.client);
  bool get isStaff => this == admin || this == operator;
}

enum DriverStatus {
  pending('En attente'),
  approved('Approuvé'),
  suspended('Suspendu'),
  rejected('Refusé');

  const DriverStatus(this.label);
  final String label;
  static DriverStatus parse(String? v) => _byName(values, v, DriverStatus.pending);
}

enum VehicleType {
  moto('Moto', Icons.two_wheeler),
  tricycle('Tricycle', Icons.electric_rickshaw),
  voiture('Voiture', Icons.directions_car),
  utilitaire('Utilitaire', Icons.local_shipping);

  const VehicleType(this.label, this.icon);
  final String label;
  final IconData icon;
  static VehicleType parse(String? v) => _byName(values, v, VehicleType.moto);
}

enum PackageCategory {
  document('Document', Icons.description_outlined),
  nourriture('Nourriture', Icons.restaurant),
  petit_colis('Petit colis', Icons.inventory_2_outlined),
  colis_moyen('Colis moyen', Icons.inventory_2),
  gros_colis('Gros colis', Icons.all_inbox),
  courses('Courses / Achats', Icons.shopping_basket_outlined),
  autre('Autre', Icons.category_outlined);

  const PackageCategory(this.label, this.icon);
  final String label;
  final IconData icon;
  static PackageCategory parse(String? v) => _byName(values, v, PackageCategory.petit_colis);
}

enum PackageSize {
  petit('Petit', 'Tient dans un sac'),
  moyen('Moyen', 'Carton moyen'),
  grand('Grand', 'Gros carton, sac de riz'),
  tres_grand('Très grand', 'Meuble, électroménager');

  const PackageSize(this.label, this.hint);
  final String label;
  final String hint;
  static PackageSize parse(String? v) => _byName(values, v, PackageSize.petit);
}

enum DeliveryStatus {
  created('Nouvelle demande', 1),
  searching('Recherche de livreur', 2),
  assigned('Livreur trouvé', 3),
  to_pickup('Livreur en route', 4),
  at_pickup('Livreur arrivé', 5),
  picked_up('Colis récupéré', 6),
  in_transit('Livraison en cours', 7),
  at_dropoff('Arrivé à destination', 8),
  handed_over('Colis remis', 9),
  completed('Livraison terminée', 10),
  cancelled('Annulée', 11);

  const DeliveryStatus(this.label, this.step);
  final String label;
  final int step;
  static DeliveryStatus parse(String? v) => _byName(values, v, DeliveryStatus.created);

  bool get isActive => this != completed && this != cancelled;
  bool get isFinished => this == completed || this == cancelled;
  bool get hasDriver => step >= 3 && step <= 10;
  bool get isPending => this == created || this == searching;
  bool get canCustomerCancel => step <= 5;
  bool get canDriverRelease => this == assigned || this == to_pickup || this == at_pickup;

  /// Phase avant la récupération : le livreur se dirige vers le point de départ.
  bool get headingToPickup => this == assigned || this == to_pickup || this == at_pickup;

  Color get color => switch (this) {
        created || searching => const Color(0xFFF2A007),
        assigned || to_pickup || at_pickup => const Color(0xFF2F6FDE),
        picked_up || in_transit || at_dropoff || handed_over => const Color(0xFF7C3AED),
        completed => const Color(0xFF0B7A4B),
        cancelled => const Color(0xFFD64545),
      };

  /// Étape suivante pour le livreur et libellé du bouton correspondant.
  DeliveryStatus? get nextForDriver => switch (this) {
        assigned => to_pickup,
        to_pickup => at_pickup,
        at_pickup => picked_up,
        picked_up => in_transit,
        in_transit => at_dropoff,
        _ => null,
      };

  String get driverActionLabel => switch (this) {
        assigned => 'Je pars récupérer le colis',
        to_pickup => 'Je suis arrivé au point de récupération',
        at_pickup => 'Colis récupéré',
        picked_up => 'Démarrer la livraison',
        in_transit => 'Arrivé à destination',
        at_dropoff => 'Remettre le colis',
        _ => '',
      };
}

enum PaymentMethod {
  cash('Espèces', Icons.payments_outlined),
  cash_on_delivery('Paiement à la livraison', Icons.handshake_outlined),
  orange_money('Orange Money', Icons.phone_android),
  moov_money('Moov Money', Icons.phone_iphone),
  wallet('Mon portefeuille', Icons.account_balance_wallet_outlined);

  const PaymentMethod(this.label, this.icon);
  final String label;
  final IconData icon;
  static PaymentMethod parse(String? v) => _byName(values, v, PaymentMethod.cash);
  bool get isMobileMoney => this == orange_money || this == moov_money;
}

enum PaymentStatus {
  pending('En attente'),
  paid('Payé'),
  failed('Échoué'),
  refunded('Remboursé'),
  cancelled('Annulé');

  const PaymentStatus(this.label);
  final String label;
  static PaymentStatus parse(String? v) => _byName(values, v, PaymentStatus.pending);
}

enum WalletTxType {
  earning('Gain'),
  commission('Commission'),
  withdrawal('Retrait'),
  withdrawal_refund('Retrait annulé'),
  topup('Rechargement'),
  payment('Paiement'),
  refund('Remboursement'),
  adjustment('Ajustement');

  const WalletTxType(this.label);
  final String label;
  static WalletTxType parse(String? v) => _byName(values, v, WalletTxType.adjustment);
}

enum WithdrawalStatus {
  pending('En attente'),
  paid('Payé'),
  rejected('Refusé');

  const WithdrawalStatus(this.label);
  final String label;
  static WithdrawalStatus parse(String? v) => _byName(values, v, WithdrawalStatus.pending);
}

enum ProofType {
  otp('Code de livraison'),
  photo('Photo'),
  signature('Signature'),
  name('Nom du réceptionnaire');

  const ProofType(this.label);
  final String label;
  static ProofType? tryParse(String? v) => v == null ? null : _byName(values, v, ProofType.otp);
}

enum BusinessType {
  boutique('Boutique'),
  restaurant('Restaurant'),
  pharmacie('Pharmacie'),
  entreprise('Entreprise'),
  vendeur_en_ligne('Vendeur Facebook / WhatsApp'),
  autre('Autre');

  const BusinessType(this.label);
  final String label;
  static BusinessType parse(String? v) => _byName(values, v, BusinessType.boutique);
}

enum MemberRole {
  owner('Propriétaire'),
  manager('Gérant'),
  member('Membre');

  const MemberRole(this.label);
  final String label;
  static MemberRole parse(String? v) => _byName(values, v, MemberRole.member);
}
