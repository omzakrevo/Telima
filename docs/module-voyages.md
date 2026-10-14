# Module Voyages — réservation de tickets de car, confirmation, e-ticket et livraison du ticket

## Principe
Une compagnie de transport publie ses départs (ville de départ et d'arrivée, date et heure, prix, nombre de places).
Le voyageur réserve, la compagnie **confirme**, et le voyageur reçoit un **e-ticket avec QR code**.
S'il le souhaite, un **livreur Telima lui apporte le ticket papier** : il paie alors en espèces au livreur (billets + livraison).

Deux façons de gérer une compagnie :
* **La compagnie elle-même** : elle s'inscrit depuis l'application (*Accueil → Ma compagnie*) et gère ses départs et ses réservations.
  Son inscription est **en attente** : l'équipe Telima la valide (*Admin → Voyages → Valider* ou *Refuser*) avant que le lien et les départs soient publics.
* **L'équipe Telima** : pour une compagnie pas encore inscrite, l'administration la saisit (*Admin → Voyages → Saisir une compagnie*),
  publie ses départs et confirme les réservations à sa place (après accord par téléphone avec la compagnie).
  Elle peut ensuite la confier au compte de la compagnie (*Confier à un compte*, par numéro de téléphone).

## Parcours
| Qui | Où | Actions |
|---|---|---|
| Voyageur | Accueil → *Voyages* (`/client/voyages`) | Recherche par ville de départ / d'arrivée (sans accents, « bobo » trouve Bobo-Dioulasso) et par jour |
| Tout le monde | `/v/<lien>` | Page publique d'une compagnie et ses prochains départs (sans compte) ; QR code téléchargeable |
| Voyageur connecté | `/voyage/<id du départ>` | Nombre de places (1 à 10), noms des voyageurs, e-ticket ou ticket livré, adresse et frais de livraison, message |
| Voyageur | `/client/voyages/bookings` | Mes tickets : étapes, **e-ticket QR** (téléchargeable en image), suivi du livreur, itinéraire vers la gare, annulation |
| Compagnie | Accueil → *Ma compagnie* (`/transport`) | Inscrire sa compagnie (jusqu'à 3), logo, gare sur la carte, livraison des tickets oui / non et distance maximale |
| Compagnie | `/transport/<id>` | **Réservations** (confirmer avec n° de place / n° de ticket / message, refuser, « Payé au guichet », « Embarqué »), **Départs** (ajouter, modifier, dupliquer, annuler), **Contrôle** (vérifier un ticket), **Mon lien** (copier, partager, QR code) |
| Administration | `/admin/transport` | Toutes les compagnies, saisie d'une compagnie, gestion à sa place, suspendre / rétablir, confier à un compte |

## Règles
* **Places** : bloquées dès la réservation, rendues si elle est refusée ou annulée. Le nombre de places disponibles ne peut être modifié
  que par les fonctions du serveur ; la compagnie ne peut pas descendre le total sous le nombre de places déjà réservées.
* **Prix** : relu côté serveur (prix du départ × nombre de voyageurs). Frais de livraison du ticket = tarif « document » de Telima
  (moto), de la gare au voyageur, dans la distance maximale fixée par la compagnie (20 km par défaut).
* **Réservations sans réponse** : une réservation non confirmée est annulée au bout de **2 h** (ou dès que le départ est passé), les places
  sont libérées et le voyageur est prévenu. Un voyageur ne peut pas avoir plus de **3 réservations en attente**. Le nettoyage tourne toutes
  les 15 min si l'extension `pg_cron` est active, sinon à la prochaine réservation sur le même départ.
* **Frais de réservation Telima** : **500 F par réservation** (pas par voyageur), payés en **Mobile Money** (Orange Money ou Moov Money)
  avec le circuit « Paiement manuel » existant : le voyageur déclare son paiement, l'équipe Telima le vérifie (*Paiements à vérifier → Argent reçu*).
  Tant que les frais ne sont pas reçus, la compagnie (ou l'équipe) **ne peut pas confirmer** la réservation. Le ticket, lui, se retire et se paie
  au guichet de la compagnie. Montant : fonction SQL `telima.travel_service_fee()` (et constante `travelServiceFee` côté application).
  L'équipe peut enregistrer des frais reçus hors application avec le bouton **Frais reçus** (action `fee_received`).
  Les frais ne sont pas remboursés automatiquement en cas de refus ou d'annulation (à décider).
* **Délais** : réservation possible jusqu'à 15 min avant le départ ; livraison du ticket seulement si le départ est dans plus de 3 h.
* **Annulation par le voyageur** : tant que ce n'est pas confirmé, ou pour un e-ticket confirmé jusqu'à 2 h avant le départ.
  Après, il appelle la compagnie (bouton dans l'application).
* **Confirmation avec livraison** : une livraison Telima est créée (gare → voyageur, catégorie « document »). Le livreur retire le
  ticket au guichet, l'apporte et **encaisse le prix des billets pour la compagnie** plus ses frais. La réservation suit la livraison
  (« Ticket en route », « Ticket livré »). Si la livraison est annulée, la réservation redevient un e-ticket payable au guichet.
* **Annulation d'un départ par la compagnie** : toutes les réservations en cours sont annulées et les voyageurs prévenus ;
  les livraisons de ticket pas encore prises par un livreur sont annulées.
* **Contrôle à l'embarquement** : le QR code contient `TELIMA-VOY:<code>:<secret>`. Le secret empêche de fabriquer un faux ticket
  à partir du seul code. La compagnie peut aussi saisir le code (`VOY-2026-000012`, ou seulement `12`). Un ticket déjà embarqué,
  annulé ou non confirmé est signalé. « Embarqué » marque aussi la réservation comme payée.
* **Notifications** : nouvelle réservation (au propriétaire de la compagnie, ou à l'équipe Telima si elle la gère), confirmation,
  refus, annulation, départ annulé, livraison du ticket annulée.

## Base de données (migrations `telima_18_voyages` puis `telima_19_voyages_durcissement`)
Tables : `transport_companies`, `travel_trips`, `travel_bookings` (statuts `pending`, `confirmed`, `out_for_delivery`, `delivered`,
`boarded`, `rejected`, `cancelled`). Compartiment public `telima-voyages` (logos).

Fonctions :
* Lecture publique (sans compte) : `search_travel_trips`, `travel_cities`, `transport_company_by_slug`, `travel_trip`.
* Voyageur : `travel_ticket_delivery_fee`, `create_travel_booking`, `cancel_travel_booking`.
* Compagnie ou équipe Telima : `register_transport_company`, `travel_booking_action` (confirm, reject, board, paid),
  `travel_trip_cancel`, `check_travel_ticket`, `transport_company_dashboard`.
* Administration : `admin_create_transport_company`, `admin_set_company_owner`, `admin_set_transport_company_status`.
* Déclencheurs : `tg_travel_trips_guard` (places, annulation), `tg_transport_companies_guard` (statut, propriétaire, lien),
  `tg_travel_follow_delivery` (la réservation suit la livraison du ticket).

Le scénario complet (inscription, départ, 3 réservations, refus de tricher sur les places, confirmation avec et sans livraison,
contrôle d'un vrai et d'un faux QR, embarquement, annulation de la livraison puis du départ, compagnie gérée par Telima)
a été vérifié sur la base de production dans une transaction annulée (aucune donnée laissée).

## Mise en production
* **Web** : rien à changer côté hébergement, les adresses `/v/…` et `/voyage/…` sont déjà renvoyées vers l'application.
* **Android** : l'ouverture directe des liens `/v/<lien>` dans l'application demande une **nouvelle version complète**
  (filtre d'intention ajouté dans `AndroidManifest.xml`, ce qu'un patch Shorebird ne peut pas livrer). Le reste du module passe en patch.

## Pistes suivantes
Lecture du QR code à la caméra dans l'onglet Contrôle, plan des places à choisir, paiement Mobile Money (Orange Money, Moov),
départs réguliers (tous les jours à 7 h) créés automatiquement, liste des passagers d'un départ à imprimer.
