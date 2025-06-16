import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/group.dart';
import '../../services/expense_service.dart';
import '../../models/app_user.dart';
import '../../services/user_service.dart';
import '../../utils/snackbar_helper.dart';

class CreateExpensePage extends StatefulWidget {
  final Group group;

  const CreateExpensePage({super.key, required this.group});

  @override
  State<CreateExpensePage> createState() => _CreateExpensePageState();
}

class _CreateExpensePageState extends State<CreateExpensePage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _expenseService = ExpenseService();
  final UserService _userService = UserService();
  final List<String> _selectedMembers = [];
  final Map<String, String> _memberNames = {};
  bool _isLoading = false;
  String? _selectedCategory;

  final List<String> _categories = [
    'Food',
    'Travel',
    'Stay',
    'Entertainment',
    'Utilities',
    'Groceries',
    'Shopping',
    'Healthcare',
    'Education',
    'Transportation',
    'Rent',
    'Others',
  ];

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
    _selectedMembers.add(FirebaseAuth.instance.currentUser!.uid);
    _fetchMemberNames();

    // Add listeners to text controllers for smart categorization
    _titleController.addListener(_updateCategorySuggestion);
    _descriptionController.addListener(_updateCategorySuggestion);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _titleController.removeListener(_updateCategorySuggestion);
    _descriptionController.removeListener(_updateCategorySuggestion);
    _titleController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _updateCategorySuggestion() {
    setState(() {
      _selectedCategory = _suggestCategory(
        _titleController.text,
        _descriptionController.text,
      );
    });
  }

  String? _suggestCategory(String title, String description) {
    final text = '${title.toLowerCase()} ${description.toLowerCase()}';

    if (text.contains('food') || text.contains('restaurant') || text.contains('cafe')) {
      return 'Food';
    } else if (text.contains('flight') || text.contains('train') || text.contains('bus') || text.contains('taxi') || text.contains('fuel')) {
      return 'Travel';
    } else if (text.contains('hotel') || text.contains('accommodation') || text.contains('lodging')) {
      return 'Stay';
    } else if (text.contains('movie') || text.contains('concert') || text.contains('show') || text.contains('ticket') || text.contains('party')) {
      return 'Entertainment';
    } else if (text.contains('electricity') || text.contains('water bill') || text.contains('internet') || text.contains('phone bill')) {
      return 'Utilities';
    } else if (text.contains('grocery') || text.contains('supermarket') || text.contains('kirana')) {
      return 'Groceries';
    } else if (text.contains('shopping') || text.contains('clothes') || text.contains('mall')) {
      return 'Shopping';
    } else if (text.contains('doctor') || text.contains('hospital') || text.contains('pharmacy') || text.contains('medicine')) {
      return 'Healthcare';
    } else if (text.contains('tuition') || text.contains('books') || text.contains('course')) {
      return 'Education';
    } else if (text.contains('bus') || text.contains('metro') || text.contains('auto')) {
      return 'Transportation';
    } else if (text.contains('rent') || text.contains('house') || text.contains('apartment')) {
      return 'Rent';
    } 
    return null; // No suggestion
  }

  Future<void> _fetchMemberNames() async {
    for (String memberId in widget.group.members) {
      final user = await _userService.getUser(memberId);
      setState(() {
        _memberNames[memberId] = user?.name ?? user?.email ?? memberId;
      });
    }
  }

  Future<void> _createExpense() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        await _expenseService.createExpense(
          groupId: widget.group.id,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          amount: double.parse(_amountController.text),
          paidBy: FirebaseAuth.instance.currentUser!.uid,
          splitBetween: _selectedMembers,
          category: _selectedCategory,
        );
        if (mounted) {
          Navigator.pop(context);
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
                        'Add New Expense',
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
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _descriptionController,
                          decoration: _buildInputDecoration('Description', Icons.description),
                          style: const TextStyle(color: Colors.white),
                          maxLines: 3,
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
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          decoration: _buildInputDecoration('Category', Icons.category),
                          style: const TextStyle(color: Colors.white),
                          dropdownColor: Colors.grey[850],
                          value: _selectedCategory,
                          hint: Text(
                            'Select a category',
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedCategory = newValue;
                            });
                          },
                          items: _categories.map<DropdownMenuItem<String>>((String category) {
                            return DropdownMenuItem<String>(
                              value: category,
                              child: Text(category, style: const TextStyle(color: Colors.white)),
                            );
                          }).toList(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please select a category';
                            }
                            return null;
                          },
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
                              onChanged: (bool? value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedMembers.add(memberId);
                                  } else {
                                    _selectedMembers.remove(memberId);
                                  }
                                });
                              },
                              activeColor: Colors.blueAccent,
                              checkColor: Colors.white,
                              side: BorderSide(color: Colors.grey[600]!),
                            )),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _isLoading || _selectedMembers.isEmpty ? null : _createExpense,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 5,
                            shadowColor: Colors.blueAccent.withOpacity(0.4),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text(
                                  'Add Expense',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
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