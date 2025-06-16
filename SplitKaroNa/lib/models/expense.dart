import 'package:cloud_firestore/cloud_firestore.dart';

class Expense {
  final String id;
  final String groupId;
  final String title;
  final String description;
  final double amount;
  final String paidBy;
  final DateTime paidAt;
  final List<String> splitBetween; // List of user IDs
  final Map<String, double> splitAmounts; // Map of user ID to amount
  final Map<String, bool> paidStatus; // Map of user ID to paid status
  final String? category; // New field for categorization

  Expense({
    required this.id,
    required this.groupId,
    required this.title,
    required this.description,
    required this.amount,
    required this.paidBy,
    required this.paidAt,
    required this.splitBetween,
    required this.splitAmounts,
    required this.paidStatus,
    this.category, // Make category optional
  });

  Map<String, dynamic> toMap() {
    return {
      'groupId': groupId,
      'title': title,
      'description': description,
      'amount': amount,
      'paidBy': paidBy,
      'paidAt': paidAt,
      'splitBetween': splitBetween,
      'splitAmounts': splitAmounts,
      'paidStatus': paidStatus,
      'category': category, // Add category to map
    };
  }

  factory Expense.fromMap(String id, Map<String, dynamic> map) {
    return Expense(
      id: id,
      groupId: map['groupId'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      amount: (map['amount'] ?? 0.0).toDouble(),
      paidBy: map['paidBy'] ?? '',
      paidAt: (map['paidAt'] as Timestamp).toDate(),
      splitBetween: List<String>.from(map['splitBetween'] ?? []),
      splitAmounts: Map<String, double>.from(map['splitAmounts'] ?? {}),
      paidStatus: Map<String, bool>.from(map['paidStatus'] ?? {}),
      category: map['category'], // Read category from map
    );
  }
} 