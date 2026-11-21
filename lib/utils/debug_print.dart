// מחוץ ל-Flutter (כלי `dart run`) אין package:flutter; שם מודפס ישירות.
export 'debug_print_stub.dart'
    if (dart.library.ui) 'package:flutter/foundation.dart'
    show debugPrint;
