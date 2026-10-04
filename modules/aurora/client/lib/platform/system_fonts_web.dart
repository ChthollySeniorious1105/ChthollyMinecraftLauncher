import 'system_fonts.dart';

/// Browsers do not expose installed fonts without a permission prompt; the web client keeps the bundled font.
Future<List<SystemFont>> listSystemFonts() async => const [];
