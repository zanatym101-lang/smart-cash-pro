import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/app_db.dart';
import 'notification_service.dart';

class CloudSyncService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Timer? _syncTimer;
  static bool _isSyncing = false;
  static final List<StreamSubscription> _subscriptions = [];

  static void startSync(String workspaceId) {
    if (_syncTimer != null) return;
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) => _syncOutbox(workspaceId));
    _syncOutbox(workspaceId);
    _startListening(workspaceId);
  }

  static void stopSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  static void _startListening(String workspaceId) {
    final collections = ['wallet', 'wallets', 'txn', 'transactions', 'claim', 'claims', 'customer', 'customers', 'ledger_event', 'ledger_events'];
    
    for (final col in collections) {
      final sub = _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection(col)
          .snapshots()
          .listen((snapshot) async {
        if (snapshot.docs.isEmpty) return;
        
        try {
          final resetEpoch = await AppDb.instance.getWorkspaceResetEpoch();

          // Convert to items
          final items = <Map<String, dynamic>>[];
          for (final d in snapshot.docs) {
            final data = d.data();
            data.forEach((key, value) {
              if (value is Timestamp) {
                data[key] = value.toDate().toIso8601String();
              }
            });

            // If reset epoch is present, verify document date / timestamp is not stale
            if (resetEpoch != null) {
              final docEpoch = data['created_at_epoch'] ?? data['createdAtEpoch'] ?? data['epoch'];
              if (docEpoch != null) {
                final intDocEpoch = int.tryParse(docEpoch.toString());
                if (intDocEpoch != null && intDocEpoch < resetEpoch) {
                  continue;
                }
              }
            }

            items.add(data);
          }

          if (items.isEmpty) return;

          // Normalize entity name
          String normalizedEntity = col;
          if (col == 'wallets') normalizedEntity = 'wallet';
          if (col == 'transactions') normalizedEntity = 'txn';
          if (col == 'claims') normalizedEntity = 'claim';
          if (col == 'customers') normalizedEntity = 'customer';
          if (col == 'ledger_events') normalizedEntity = 'ledger_event';

          await AppDb.instance.applyCloudUpdates(normalizedEntity, items);
        } catch (e) {
          debugPrint('Pull Sync Error: $e');
          NotificationService.show(title: 'خطأ في استقبال البيانات', body: e.toString());
        }
      }, onError: (e) {
        debugPrint('Snapshot Error: $e');
        NotificationService.show(title: 'خطأ في جلب البيانات', body: e.toString());
      });
      _subscriptions.add(sub);
    }
  }

  static Future<void> _syncOutbox(String workspaceId) async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final outboxItems = await AppDb.instance.listOutbox(limit: 50);
      
      for (final item in outboxItems) {
        final docRef = _firestore
            .collection('workspaces')
            .doc(workspaceId)
            .collection(item.entity)
            .doc(item.entityId);

        try {
          if (item.action == 'delete') {
            await docRef.delete();
          } else {
            if (item.payload != null && item.payload!.isNotEmpty) {
              final Map<String, dynamic> data = jsonDecode(item.payload!);
              data['cloud_updated_at'] = FieldValue.serverTimestamp();
              data['created_at_epoch'] = DateTime.now().millisecondsSinceEpoch;
              await docRef.set(data, SetOptions(merge: true));
            }
          }
          await AppDb.instance.markOutboxSent(item.id);
        } catch (e) {
          debugPrint('Failed to sync item ${item.id}: $e');
        }
      }
    } catch (e) {
      debugPrint('Sync Error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  static Future<void> clearCloudData() async {
    await purgeWorkspaceCloudCollections();
  }

  static Future<void> purgeWorkspaceCloudCollections([String? targetWorkspaceId]) async {
    final user = FirebaseAuth.instance.currentUser;
    final workspaceId = targetWorkspaceId ?? user?.uid;
    if (workspaceId == null || workspaceId.trim().isEmpty) return;

    final collections = [
      'wallets',
      'wallet',
      'transactions',
      'txn',
      'claims',
      'claim',
      'customers',
      'customer',
      'ledger_events',
      'ledger_event',
      'outbox',
      'syncOutbox',
    ];

    for (final col in collections) {
      try {
        final snap = await _firestore
            .collection('workspaces')
            .doc(workspaceId)
            .collection(col)
            .get();
        if (snap.docs.isEmpty) continue;

        final batch = _firestore.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } catch (e) {
        debugPrint('Error purging Firestore collection $col for workspace $workspaceId: $e');
      }
    }

    try {
      final nowEpoch = DateTime.now().millisecondsSinceEpoch;
      await _firestore.collection('workspaces').doc(workspaceId).set({
        'lastResetEpoch': nowEpoch,
        'lastResetAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error recording lastResetEpoch in Firestore: $e');
    }
  }
}
