/// Build-time configuration. Override with:
///   flutter run --dart-define=API_URL=https://api.example.com
class AppConfig {
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:4000');
  static const appName = 'OnePe POS';
  static const version = '1.0.0';
}
