import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Send a message to a group
  Future<void> sendMessage(String groupId, String messageText) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      // Get user details
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      if (userData == null) throw Exception('User data not found');

      final message = Message(
        id: '',  // Will be set by Firestore
        senderId: user.uid,
        senderName: userData['name'] ?? 'Unknown User',
        content: messageText,
        timestamp: DateTime.now(),
      );

      await _firestore.collection('groups').doc(groupId).collection('messages').add(message.toMap());
    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  // Get messages stream for a group
  Stream<List<Message>> getMessages(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .orderBy('timestamp', descending: false)  // Show oldest messages first
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Message.fromFirestore(doc)).toList());
  }
} 