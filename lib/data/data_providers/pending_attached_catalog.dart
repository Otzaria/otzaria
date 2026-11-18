/// קריאת קטלוג של מסד מצורף שעדיין רצה, כולל אחרי שבניית העץ ויתרה עליה.
class PendingAttachedCatalog<T> {
  PendingAttachedCatalog(this.future) {
    future.then((_) => done = true, onError: (_) => done = true);
  }

  final Future<T> future;
  bool done = false;
  bool timedOut = false;
}
