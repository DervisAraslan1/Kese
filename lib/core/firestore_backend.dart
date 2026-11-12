import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';

import 'cloud_persistence.dart';

/// One account's data in Firestore: `users/{uid}` is the profile, and each
/// list is a collection under it.
class FirestoreBackend implements CloudBackend {
  FirestoreBackend(String uid, {FirebaseFirestore? firestore})
      : _user = (firestore ?? FirebaseFirestore.instance).collection('users').doc(uid);

  final DocumentReference<Json> _user;

  /// The phone's copy is the working copy, so it must never be trimmed to
  /// save space. Call before anything else touches Firestore.
  static void keepEverythingOnPhone() {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  // Ids come from the app, but data from an older version could carry anything.
  DocumentReference<Json> _item(String collection, String id) =>
      _user.collection(collection).doc(Uri.encodeComponent(id));

  @override
  Stream<CloudState> watch() {
    final controller = StreamController<CloudState>();
    final subscriptions = <StreamSubscription<Object?>>[];
    Json? profile;
    final items = <String, Map<String, Json>>{};
    // Which parts have reported, and whether the server has confirmed them.
    final confirmed = <String, bool>{};

    void emit() {
      if (confirmed.length <= cloudCollections.length) return;
      controller.add(CloudState(
        profile: profile,
        items: Map.of(items),
        fromServer: confirmed.values.every((fromServer) => fromServer),
      ));
    }

    controller.onListen = () {
      // Metadata changes are included because "the server agrees this is
      // empty" changes no data, and a new account waits for exactly that.
      subscriptions.add(_user.snapshots(includeMetadataChanges: true).listen(
        (snapshot) {
          profile = snapshot.data();
          confirmed[''] = !snapshot.metadata.isFromCache;
          emit();
        },
        onError: controller.addError,
      ));
      for (final collection in cloudCollections) {
        subscriptions.add(
          _user.collection(collection).snapshots(includeMetadataChanges: true).listen(
            (snapshot) {
              items[collection] = {
                for (final doc in snapshot.docs)
                  if (doc.data() case final data when data['id'] is String)
                    data['id'] as String: data,
              };
              confirmed[collection] = !snapshot.metadata.isFromCache;
              emit();
            },
            onError: controller.addError,
          ),
        );
      }
    };
    controller.onCancel = () => Future.wait([
          for (final subscription in subscriptions) subscription.cancel(),
        ]);
    return controller.stream;
  }

  @override
  Future<void> commit(List<CloudWrite> writes) {
    final firestore = _user.firestore;
    WriteBatch batchOf(List<CloudWrite> chunk) {
      final batch = firestore.batch();
      for (final write in chunk) {
        final collection = write.collection;
        final target = collection == null ? _user : _item(collection, write.id!);
        final data = write.data;
        if (data == null) {
          batch.delete(target);
        } else {
          batch.set(target, data);
        }
      }
      return batch;
    }

    return Future.wait([
      for (final chunk in writes.slices(400)) batchOf(chunk).commit(),
    ]);
  }
}
