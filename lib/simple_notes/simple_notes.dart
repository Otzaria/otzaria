/// מערכת הערות פשוטה
///
/// מערכת הערות חדשה המבוססת על קבצי טקסט ו-JSON במקום SQLite.
library simple_notes;

// Models
export 'models/simple_note.dart';
export 'models/annotation_mapping.dart';
export 'models/location_verification_result.dart';

// Data
export 'data/file_system_notes_provider.dart';

// Services
export 'services/location_verification_service.dart';

// Repository
export 'repository/simple_notes_repository.dart';

// Widgets
export 'widgets/simple_notes_screen.dart';
export 'widgets/create_note_dialog.dart';
