import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';
import '../models/group.dart';

class GroupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'groups';
  final CollectionReference _groupsCollection = FirebaseFirestore.instance.collection('groups');

  // Generate a 6-digit alphanumeric group ID
  String _generateGroupId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random random = Random();
    return String.fromCharCodes(Iterable.generate(
      6, (_) => chars.codeUnitAt(random.nextInt(chars.length)),
    ));
  }

  // Create a new group with a generated ID
  Future<Group> createGroup(String name, String createdBy, List<String> members) async {
    String groupId = _generateGroupId();
    final docRef = _firestore.collection(_collection).doc(groupId);
    
    // Ensure the generated ID is unique (unlikely to collide with 6 chars)
    // For very high scale, a more robust check might be needed.
    await docRef.set({
      'name': name,
      'createdBy': createdBy,
      'members': members,
      'createdAt': FieldValue.serverTimestamp(),
      'expenses': [],
    });

    final doc = await docRef.get();
    return Group.fromMap(doc.id, doc.data() as Map<String, dynamic>);
  }

  // Get all groups for a user
  Stream<List<Group>> getUserGroups(String userId) {
    return _firestore
        .collection(_collection)
        .where('members', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Group.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  // Add member to group
  Future<void> addMemberToGroup(String groupId, String userId) async {
    await _firestore.collection(_collection).doc(groupId).update({
      'members': FieldValue.arrayUnion([userId]),
    });
  }

  // Remove member from group
  Future<void> removeMemberFromGroup(String groupId, String userId) async {
    await _firestore.collection(_collection).doc(groupId).update({
      'members': FieldValue.arrayRemove([userId]),
    });
  }

  // Delete group
  Future<void> deleteGroup(String groupId) async {
    await _firestore.collection(_collection).doc(groupId).delete();
  }

  // Get group by ID
  Future<Group?> getGroup(String groupId) async {
    final doc = await _firestore.collection(_collection).doc(groupId).get();
    if (!doc.exists) return null;
    return Group.fromMap(doc.id, doc.data() as Map<String, dynamic>);
  }

  // Join a group using its ID
  Future<void> joinGroup(String groupId, String userId) async {
    final groupDoc = await _firestore.collection(_collection).doc(groupId).get();

    if (!groupDoc.exists) {
      throw Exception('Group with ID $groupId not found.');
    }

    final groupData = groupDoc.data() as Map<String, dynamic>;
    List<String> currentMembers = List<String>.from(groupData['members']);

    if (currentMembers.contains(userId)) {
      if (kDebugMode) {
        print('User $userId is already a member of group $groupId');
      }
      // Optionally, you can throw an exception or just do nothing if already a member
      return;
    }

    await _firestore.collection(_collection).doc(groupId).update({
      'members': FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> updateGroup(String groupId, Map<String, dynamic> updates) async {
    try {
      await _groupsCollection.doc(groupId).update(updates);
    } catch (e) {
      print('Error updating group: $e');
      rethrow;
    }
  }
} 