import '../models/android_update.dart';

sealed class AndroidUpdateEvent {
  const AndroidUpdateEvent();
}

class AndroidUpdateInitialize extends AndroidUpdateEvent {
  const AndroidUpdateInitialize();
}

class AndroidUpdateCheck extends AndroidUpdateEvent {
  const AndroidUpdateCheck({this.automatic = false});
  final bool automatic;
}

class AndroidUpdateDownload extends AndroidUpdateEvent {
  const AndroidUpdateDownload();
}

class AndroidUpdateInstall extends AndroidUpdateEvent {
  const AndroidUpdateInstall();
}

class AndroidUpdateCancel extends AndroidUpdateEvent {
  const AndroidUpdateCancel();
}

class AndroidUpdateResumed extends AndroidUpdateEvent {
  const AndroidUpdateResumed();
}

class AndroidUpdateNativeChanged extends AndroidUpdateEvent {
  const AndroidUpdateNativeChanged(this.status);
  final AndroidNativeUpdateStatus status;
}

class AndroidUpdateDownloadProgress extends AndroidUpdateEvent {
  const AndroidUpdateDownloadProgress(
    this.operation,
    this.received,
    this.total,
  );
  final int operation;
  final int received;
  final int total;
}
