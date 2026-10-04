/// Hors navigateur : l'application est déjà installée, rien à proposer.
bool pwaIsStandalone() => true;
bool pwaCanPrompt() => false;
String pwaPlatform() => 'native';
Future<String> pwaPrompt() async => 'unavailable';
