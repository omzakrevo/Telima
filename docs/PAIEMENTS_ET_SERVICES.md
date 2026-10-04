# Paiements Orange Money / Moov Money, courses à faire et trajets

## Paiement Mobile Money manuel (mode « Manuel »)
1. Tableau de bord → **Paramètres** → Paiements → Mobile Money : **Manuel**, puis saisir le numéro
   Orange Money (et Moov Money) qui reçoit l'argent et le nom du titulaire → Enregistrer.
2. Le client choisit Orange Money : l'application affiche le montant exact et le numéro (bouton Copier,
   bouton « Ouvrir Orange Money *144# »). Il envoie l'argent, indique le numéro qui a payé et, s'il veut,
   l'ID de transaction du SMS, puis touche **J'AI FAIT LE PAIEMENT**.
3. L'administrateur reçoit une notification « Paiement Orange Money à vérifier ».
   Menu **Paiements à vérifier** : **Argent reçu** (le portefeuille est crédité ou la commande est lancée,
   le client est notifié) ou **Refuser** avec un motif (le client est notifié et peut réessayer).
4. Le tableau de bord affiche en haut le nombre de paiements à vérifier et de retraits à verser.

### Relais des SMS (aide à la vérification)
Sur le téléphone Android qui reçoit les paiements : **Paiements à vérifier** → activer
« Relais des SMS de paiement » et autoriser les SMS. Chaque SMS Orange Money / Moov Money reçu
(même application fermée) est transmis, analysé (montant, numéro, ID) et rapproché du paiement
déclaré : la carte passe en vert « SMS reçu correspondant ». **Un SMS ne valide jamais seul** :
l'administrateur garde la décision. Seuls les SMS Mobile Money sont transmis.

### Retraits des livreurs
**Paiements & retraits** → **Payé** : l'application affiche le numéro du livreur (Copier, *144#),
l'administrateur envoie l'argent puis saisit l'ID de transaction. Le livreur est notifié.

## Courses à faire
Le client décrit ce qu'il faut acheter (repas, pharmacie, marché, boutique…), un budget maximum
facultatif et l'adresse de livraison. Prix = tarif minimum + **frais de service** (Paramètres).
Le livreur achète où il trouve, saisit le montant payé + photo du ticket (le client est notifié),
puis livre. Le client rembourse les achats en espèces ou avec son portefeuille. Le livreur ne peut pas
partir livrer sans avoir saisi le montant des achats.

## Trajets (transport de personnes)
Moto-taxi (1 passager) ou voiture (jusqu'à 4). Prix = tarif du véhicule × **multiplicateur des trajets**
(Paramètres, 1 par défaut). Seuls les livreurs / chauffeurs ayant activé « Passagers » dans
« Je propose » (moto ou voiture) reçoivent les trajets. Le passager donne son code au chauffeur à l'arrivée.

## Notifications
Chaque action notifie les personnes concernées (bannière en haut de l'écran) : commande créée,
code de remise, livreur trouvé, étapes, achats effectués, paiement en vérification / validé / refusé,
gains, commissions, rechargements, retraits, évaluations, messages, assistance, changement de rôle,
code de récupération de compte. L'équipe (admin / opérateurs) reçoit : nouvelles commandes, paiements
à vérifier, SMS reçus, retraits, inscriptions, annulations, demandes d'assistance.
