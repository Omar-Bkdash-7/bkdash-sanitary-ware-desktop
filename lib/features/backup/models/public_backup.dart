/// One copy of the database kept in the public backup folder.
final class PublicBackup {
  const PublicBackup({
    required this.id,
    required this.name,
    required this.savedAt,
  });

  final String id;
  final String name;
  final DateTime savedAt;
}
