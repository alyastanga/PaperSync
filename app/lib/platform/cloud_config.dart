/// The only Supabase values the app is allowed to hold.
class CloudConfig {
  const CloudConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;

  static const fromEnvironment = CloudConfig(
    url: String.fromEnvironment('SUPABASE_URL'),
    anonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  bool get enabled => url.isNotEmpty && anonKey.isNotEmpty;
}
