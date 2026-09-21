/// Curated, professional typefaces bundled with Tonyo for offline use.
///
/// Persist [name] rather than the display label so saved preferences stay stable.
enum TonyoFont {
  system('System default', 'Familiar and native to your device.', null),
  inter('Inter', 'Clean and precise, with clear numbers.', 'Inter'),
  sourceSans3(
    'Source Sans 3',
    'Open and readable, with a refined feel.',
    'SourceSans3',
  ),
  lato('Lato', 'Balanced and polished, with a softer touch.', 'Lato');

  const TonyoFont(this.label, this.description, this.family);

  final String label;
  final String description;
  final String? family;
}
