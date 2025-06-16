import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense.dart';

class ExpenseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CollectionReference _expensesCollection = FirebaseFirestore.instance.collection('expenses');
  final String _collection = 'expenses';

  // Create a new expense
  Future<Expense> createExpense({
    required String groupId,
    required String title,
    required String description,
    required double amount,
    required String paidBy,
    required List<String> splitBetween,
    String? category,
  }) async {
    // Calculate split amounts
    final splitAmount = amount / splitBetween.length;
    final splitAmounts = Map.fromIterables(
      splitBetween,
      List.generate(splitBetween.length, (_) => splitAmount),
    );
    
    // Initialize paid status
    final paidStatus = Map.fromIterables(
      splitBetween,
      List.generate(splitBetween.length, (index) => 
        splitBetween[index] == paidBy ? true : false),
    );

    final docRef = await _firestore.collection(_collection).add({
      'groupId': groupId,
      'title': title,
      'description': description,
      'amount': amount,
      'paidBy': paidBy,
      'paidAt': FieldValue.serverTimestamp(),
      'splitBetween': splitBetween,
      'splitAmounts': splitAmounts,
      'paidStatus': paidStatus,
      'category': category,
    });

    // Add expense ID to group's expenses list
    await _firestore.collection('groups').doc(groupId).update({
      'expenses': FieldValue.arrayUnion([docRef.id]),
    });

    final doc = await docRef.get();
    return Expense.fromMap(doc.id, doc.data() as Map<String, dynamic>);
  }

  // Get all expenses for a group
  Stream<List<Expense>> getGroupExpenses(String groupId) {
    return _firestore
        .collection(_collection)
        .where('groupId', isEqualTo: groupId)
        .orderBy('paidAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Expense.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  // Get all expenses for a user
  Stream<List<Expense>> getUserExpenses(String userId) {
    return _firestore
        .collection(_collection)
        .where('splitBetween', arrayContains: userId)
        .orderBy('paidAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Expense.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  // Mark expense as paid by user
  Future<void> markExpenseAsPaid(String groupId, String expenseId, String userId) async {
    await _firestore.collection(_collection).doc(expenseId).update({
      'paidStatus.' + userId: true,
    });
  }

  // Update an existing expense
  Future<void> updateExpense({
    required String groupId,
    required String expenseId,
    required String title,
    required String description,
    required double amount,
    required List<String> splitBetween,
  }) async {
    // Calculate new split amounts
    final splitAmount = amount / splitBetween.length;
    final splitAmounts = Map.fromIterables(
      splitBetween,
      List.generate(splitBetween.length, (_) => splitAmount),
    );

    // Preserve existing paidStatus for members who are still in splitBetween
    // For new members, paidStatus will be false by default
    final existingExpenseDoc = await _firestore.collection(_collection).doc(expenseId).get();
    final existingPaidStatus = Map<String, bool>.from(existingExpenseDoc.data()?['paidStatus'] ?? {});
    final newPaidStatus = <String, bool>{};
    for (var memberId in splitBetween) {
      newPaidStatus[memberId] = existingPaidStatus[memberId] ?? false;
    }

    await _firestore.collection(_collection).doc(expenseId).update({
      'title': title,
      'description': description,
      'amount': amount,
      'splitBetween': splitBetween,
      'splitAmounts': splitAmounts,
      'paidStatus': newPaidStatus,
      'updatedAt': FieldValue.serverTimestamp(), // Add an updatedAt field
    });
  }

  // Delete expense
  Future<void> deleteExpense(String expenseId, String groupId) async {
    // Remove expense ID from group's expenses list
    await _firestore.collection('groups').doc(groupId).update({
      'expenses': FieldValue.arrayRemove([expenseId]),
    });
    
    // Delete the expense
    await _firestore.collection(_collection).doc(expenseId).delete();
  }

  // Get expense by ID
  Future<Expense?> getExpense(String expenseId) async {
    final doc = await _firestore.collection(_collection).doc(expenseId).get();
    if (!doc.exists) return null;
    return Expense.fromMap(doc.id, doc.data() as Map<String, dynamic>);
  }

  // Get all expenses for a user for "On This Day" feature
  Stream<List<Expense>> getExpensesOnThisDay(String userId) {
    final now = DateTime.now();
    final currentMonth = now.month;
    final currentDay = now.day;

    return _expensesCollection
        .where('splitBetween', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Expense.fromMap(doc.id, doc.data() as Map<String, dynamic>)).where((expense) {
        return expense.paidAt.month == currentMonth && expense.paidAt.day == currentDay;
      }).toList();
    });
  }
} 