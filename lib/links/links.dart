/// מודול קישורים - ייצוא כל המחלקות הקשורות לטיפול בקישורים
library;

// Export new architecture
export 'models/link.dart';
export 'models/link_types.dart';
export 'core/link_parser.dart';
export 'core/link_generator.dart';
export 'core/link_handler.dart';
export 'services/navigation_service.dart';
export 'services/sharing_service.dart';
export 'services/url_service.dart';
export 'ui/context_menu.dart';
export 'ui/search_integration.dart';
export 'utils/encoding.dart';
export 'utils/validation.dart';
export 'utils/text_processing.dart';

// Backward compatibility - export old Link class
export '../models/links.dart' show Link, getLinksforIndexs;