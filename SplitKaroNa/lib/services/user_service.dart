import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_user.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'users';
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Create or update a user
  Future<void> setUser(String uid, Map<String, dynamic> data) async {
    await _firestore.collection(_collection).doc(uid).set(data, SetOptions(merge: true));
  }

  // Get user by ID
  Future<AppUser?> getUser(String uid) async {
    final doc = await _firestore.collection(_collection).doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromMap(doc.id, doc.data() as Map<String, dynamic>);
  }

  // Get user name by UID
  Future<String> getUserName(String uid) async {
    final user = await getUser(uid);
    return user?.name ?? user?.email ?? 'Unknown User';
  }

  // Get current authenticated user
  User? get currentUser => _auth.currentUser;

  // Update a user
  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    await _firestore.collection(_collection).doc(uid).update(data);
  }

  // Get multiple users by a list of UIDs
  Stream<List<AppUser>> getGroupMembers(List<String> uids) {
    if (uids.isEmpty) {
      return Stream.value([]);
    }
    // Firestore 'whereIn' query is limited to 10 items. Handle larger lists if necessary.
    return _firestore
        .collection(_collection)
        .where(FieldPath.documentId, whereIn: uids)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AppUser.fromMap(doc.id, doc.data() as Map<String, dynamic>))
            .toList() as List<AppUser>);
  }
} 