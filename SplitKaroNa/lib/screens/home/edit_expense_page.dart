import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/group.dart';
import '../../models/expense.dart';
import '../../services/expense_service.dart';
import '../../models/app_user.dart';
import '../../services/user_service.dart';
import '../../utils/snackbar_helper.dart';

class EditExpensePage extends StatefulWidget {
  final Group group;
  final Expense expense;

  const EditExpensePage({super.key, required this.group, required this.expense});

  @override
  State<EditExpensePage> createState() => _EditExpensePageState();
}

class _EditExpensePageState extends State<EditExpensePage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _amountController;
  final _expenseService = ExpenseService();
  final UserService _userService = UserService();
  final List<String> _selectedMembers = [];
  final Map<String, String> _memberNames = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );
    _animationController.forward();

    _titleController = TextEditingController(text: widget.expense.title);
    _descriptionController = TextEditingController(text: widget.expense.description);
    _amountController = TextEditingController(text: widget.expense.amount.toStringAsFixed(2));

    // Initialize selected members from existing expense splits
    _selectedMembers.addAll(widget.expense.splitAmounts.keys);

    _fetchMemberNames();
  }

  Future<void> _fetchMemberNames() async {
    for (String memberId in widget.group.members) {
      final user = await _userService.getUser(memberId);
      if (mounted) {
        setState(() {
          _memberNames[memberId] = user?.name ?? user?.email ?? memberId;
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _updateExpense() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        await _expenseService.updateExpense(
          groupId: widget.group.id,
          expenseId: widget.expense.id,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          amount: double.parse(_amountController.text),
          splitBetween: _selectedMembers,
        );
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expense updated successfully!')),
          );
        }
      } catch (e) {
        if (mounted) {
          showErrorSnackBar(context, e);
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  InputDecoration _buildInputDecoration(String labelText, IconData icon) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: TextStyle(color: Colors.grey[400]),
      prefixIcon: Icon(icon, color: Colors.grey[600]),
      filled: true,
      fillColor: Colors.grey[850],
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[700]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.blueAccent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserUid = FirebaseAuth.instance.currentUser!.uid;
    final bool canEdit = currentUserUid == widget.expense.paidBy;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black,
              Colors.grey[900]!,
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        'Edit Expense',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (!canEdit)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Text(
                              'You can only edit expenses you have created. You can mark as paid if applicable from the group details page.',
                              style: TextStyle(color: Colors.orange[300]),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        TextFormField(
                          controller: _titleController,
                          decoration: _buildInputDecoration('Title', Icons.text_fields),
                          style: const TextStyle(color: Colors.white),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a title';
                            }
                            return null;
                          },
                          enabled: canEdit,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _descriptionController,
                          decoration: _buildInputDecoration('Description', Icons.description),
                          style: const TextStyle(color: Colors.white),
                          maxLines: 3,
                          enabled: canEdit,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _amountController,
                          decoration: _buildInputDecoration('Amount (₹)', Icons.currency_rupee),
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter an amount';
                            }
                            if (double.tryParse(value) == null) {
                              return 'Please enter a valid amount';
                            }
                            return null;
                          },
                          enabled: canEdit,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Split Between:',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...widget.group.members.map((memberId) => CheckboxListTile(
                              title: Text(
                                _memberNames[memberId] ?? memberId,
                                style: const TextStyle(color: Colors.white),
                              ),
                              value: _selectedMembers.contains(memberId),
                              onChanged: canEdit ? (bool? value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedMembers.add(memberId);
                                  } else {
                                    _selectedMembers.remove(memberId);
                                  }
                                });
                              } : null, // Disable checkbox if not allowed to edit
                              activeColor: Colors.blueAccent,
                              checkColor: Colors.white,
                              side: BorderSide(color: Colors.grey[600]!),
                            )),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _isLoading || _selectedMembers.isEmpty || !canEdit ? null : _updateExpense,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber[900],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Update Expense',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[800],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}