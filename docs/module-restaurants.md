# Module Restaurants — lien partageable et commande directe

## Principe
Un restaurateur crée son restaurant dans l'application, saisit son menu et reçoit un lien public
`https://telimatchi.com/#/r/<lien>` à envoyer à ses clients (WhatsApp, Facebook, TikTok…).
Le menu est visible **sans compte** ; la commande demande de se connecter, puis le client revient sur la page du restaurant.

## Parcours
| Qui | Où | Actions |
|---|---|---|
| Restaurateur | Accueil → *Mon restaurant* (`/restaurant`) | Créer (jusqu'à 5), modifier, photos logo/couverture, rayon de livraison, minimum, délai |
| Restaurateur | `/restaurant/<id>` | Onglet Commandes (accepter, refuser, en préparation, prête, remise), onglet Menu (catégories, plats, photo, « épuisé »), onglet Mon lien (copier/partager), interrupteur Ouvert/Fermé |
| Client | `/client/restaurants` | Restaurants autour de moi, recherche nom/plat/quartier |
| Tout le monde | `/r/<lien>` | Page du restaurant, menu, panier |
| Client connecté | `/r/<lien>/order` | Retrait ou livraison, adresse, frais calculés, message, confirmation |
| Client | `/client/restaurants/orders` | Suivi (rafraîchi toutes les 15 s), annulation tant que non accepté |
| Administrateur | `/admin/restaurants` | Suspendre / rétablir (le lien cesse de fonctionner) |

## Base de données (migration `telima_13_restaurants`)
Tables : `restaurants`, `restaurant_menu_categories`, `restaurant_menu_items`, `restaurant_orders`, `restaurant_order_items`.
Fonctions : `register_restaurant`, `restaurant_by_slug` (public), `find_restaurants` (public), `restaurant_delivery_fee`,
`create_restaurant_order`, `restaurant_order_action`, `cancel_restaurant_order`, `restaurant_dashboard`, `admin_set_restaurant_status`.

* Les prix des plats sont relus côté serveur ; le client ne peut pas les modifier.
* Le restaurateur ne peut pas se valider, changer de propriétaire ni modifier son lien (déclencheur `tg_restaurants_guard`).
* Commande « prête » en livraison : création automatique d'une livraison Telima (moto) ; le statut de la commande suit celui de la livraison.
* Paiement : espèces uniquement (le livreur encaisse les plats pour le restaurant).
* Les anciennes tables `menu_*` / `food_orders` (module précédent, vides) sont conservées ; les nouveaux objets utilisent des noms distincts.

## Pistes suivantes
QR code imprimable du lien, réorganisation du menu par glisser-déposer, paiement Mobile Money, options de plats (taille, supplément),
notification sonore côté restaurateur.
