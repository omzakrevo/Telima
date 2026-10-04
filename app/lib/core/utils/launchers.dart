import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> callPhone(String phone) => launchUrl(Uri(scheme: 'tel', path: phone));

Future<void> sendSms(String phone, String body) =>
    launchUrl(Uri(scheme: 'sms', path: phone, queryParameters: {'body': body}));

Future<void> openWhatsApp(String phone, [String text = '']) => launchUrl(
      Uri.parse('https://wa.me/${phone.replaceAll('+', '')}${text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}'}'),
      mode: LaunchMode.externalApplication,
    );

Future<void> sendEmail(String email, String subject) =>
    launchUrl(Uri(scheme: 'mailto', path: email, queryParameters: {'subject': subject}));

/// Ouvre la navigation GPS (Google Maps / application par défaut) vers un point.
Future<void> openNavigation(LatLng to) => launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${to.latitude},${to.longitude}&travelmode=driving'),
      mode: LaunchMode.externalApplication,
    );
