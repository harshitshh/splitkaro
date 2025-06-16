import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String name;
  final String email;
  final String? upiId;

  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    this.upiId,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'upiId': upiId,
    };
  }

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      name: map['name'] as String,
      email: map['email'] as String,
      upiId: map['upiId'] as String?,
    );
  }

  factory AppUser.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser.fromMap(doc.id, data);
  }
} 