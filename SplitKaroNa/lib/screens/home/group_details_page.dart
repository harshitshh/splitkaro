import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';  // Add this import for Clipboard
import '../../models/group.dart';
import '../../models/expense.dart';
import '../../models/app_user.dart';
import '../../services/expense_service.dart';
import '../../services/user_service.dart';
import 'create_expense_page.dart';
import 'edit_expense_page.dart';
import 'group_members_page.dart'; // Import GroupMembersPage to use its settlement logic
import 'package:flutter/rendering.dart';
import '../../utils/snackbar_helper.dart';
import '../../screens/chat/chat_screen.dart';

class GroupDetailsPage extends StatefulWidget {
  final Group group;

  const GroupDetailsPage({super.key, required this.group});

  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final _expenseService = ExpenseService();
  final UserService _userService = UserService();
  final _currencyFormat = NumberFormat.currency(symbol: '₹');
  final Map<String, String> _memberNames = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    _fetchMemberNames();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
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

  Map<String, double> _calculateBalances(List<Expense> expenses) {
    final Map<String, double> balances = {};

    // Initialize balances to 0.0 for all members
    for (String memberId in widget.group.members) {
      balances[memberId] = 0.0;
    }

    for (var expense in expenses) {
      // Payer's balance increases by the total amount paid (they are owed money)
      balances.update(
        expense.paidBy,
        (value) => value + expense.amount,
        ifAbsent: () => expense.amount,
      );

      // Each split participant's balance decreases by their share (they owe money)
      expense.splitAmounts.forEach((memberId, amount) {
        balances.update(
          memberId,
          (value) => value - amount,
          ifAbsent: () => -amount,
        );
      });
    }
    return balances;
  }

  Map<String, double> _calculateCategorySpending(List<Expense> expenses) {
    final Map<String, double> categorySpending = {};
    for (var expense in expenses) {
      if (expense.category != null) {
        categorySpending.update(
          expense.category!,
          (value) => value + expense.amount,
          ifAbsent: () => expense.amount,
        );
      }
    }
    return categorySpending;
  }

  Future<void> launchUPIPayment({
    required String upiId,
    required String name,
    required double amount,
    required String transactionNote,
  }) async {
    // First try to launch common UPI apps directly
    final List<String> upiApps = [
      'com.google.android.apps.nbu.paisa.user',  // Google Pay
      'net.one97.paytm',                         // Paytm
      'com.phonepe.app',                         // PhonePe
      'in.org.npci.upiapp',                     // BHIM
      'com.whatsapp',                           // WhatsApp
    ];

    print('Checking for installed UPI apps...');
    bool foundUpiApp = false;
    for (final app in upiApps) {
      final uri = Uri.parse('android-app://$app');
      if (await canLaunchUrl(uri)) {
        print('Found UPI app: $app');
        foundUpiApp = true;
        break;
      }
    }

    if (!foundUpiApp) {
      print('No common UPI apps found installed');
    }

    // Try different UPI URL formats
    final List<Map<String, String>> upiFormats = [
      {
        'name': 'Simple Format',
        'uri': 'upi://pay?pa=$upiId&pn=$name&am=${amount.toStringAsFixed(2)}',
      },
      {
        'name': 'Detailed Format',
        'uri': 'upi://pay?pa=$upiId&pn=$name&am=${amount.toStringAsFixed(2)}&tn=$transactionNote&cu=INR',
      },
      {
        'name': 'Transaction ID Format',
        'uri': 'upi://pay?pa=$upiId&pn=$name&am=${amount.toStringAsFixed(2)}&tr=${DateTime.now().millisecondsSinceEpoch}',
      },
      {
        'name': 'Minimal Format',
        'uri': 'upi://$upiId?am=${amount.toStringAsFixed(2)}',
      },
      {
        'name': 'Intent Format',
        'uri': 'intent://pay?pa=$upiId&pn=$name&am=${amount.toStringAsFixed(2)}#Intent;scheme=upi;package=com.google.android.apps.nbu.paisa.user;end',
      },
    ];

    print('\nPayment Details:');
    print('UPI ID: $upiId');
    print('Name: $name');
    print('Amount: $amount');
    print('Note: $transactionNote');
    print('\nAttempting to launch UPI payment...');

    bool launched = false;
    String? lastError;
    String? lastTriedFormat;

    for (final format in upiFormats) {
      final uri = Uri.parse(format['uri']!);
      lastTriedFormat = format['name'];
      
      print('\nTrying ${format['name']}:');
      print('URI: $uri');
      
      try {
        if (await canLaunchUrl(uri)) {
          print('Can launch this format');
          final success = await launchUrl(
            uri,
            mode: LaunchMode.externalNonBrowserApplication,
          );
          
          if (success) {
            print('Successfully launched UPI app');
            launched = true;
            break;
          } else {
            print('Failed to launch UPI app');
            lastError = 'Failed to launch UPI app';
          }
        } else {
          print('Cannot launch this format');
          lastError = 'No UPI app found to handle this format';
        }
      } catch (e) {
        print('Error launching this format: $e');
        lastError = e.toString();
      }
    }

    if (!launched && mounted) {
      final errorMessage = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Could not launch UPI app. Please try:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('1. Open your UPI app (Google Pay, PhonePe, etc.) manually'),
          const Text('2. Use the "Copy UPI ID" button below'),
          const Text('3. Paste the UPI ID in your UPI app'),
          const Text('4. Enter the amount manually'),
          if (lastTriedFormat != null) ...[
            const SizedBox(height: 8),
            Text('Last tried format: $lastTriedFormat', style: const TextStyle(color: Colors.orange)),
          ],
          if (lastError != null) ...[
            const SizedBox(height: 8),
            Text('Error: $lastError', style: const TextStyle(color: Colors.red)),
          ],
        ],
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: errorMessage,
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'Copy UPI ID',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: upiId));
              showInfoSnackBar(context, 'UPI ID copied to clipboard. Please paste it in your UPI app.');
            },
          ),
          backgroundColor: Colors.red[800],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      );
    }
  }

  Future<void> _settleTransactions(List<Expense> expenses) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final currentUserUid = currentUser.uid;
    final balances = _calculateBalances(expenses);

    // Check if current user has UPI ID (payer's UPI ID)
    AppUser? currentUserAppUser = await _userService.getUser(currentUserUid);
    if (currentUserAppUser == null || currentUserAppUser.upiId == null || currentUserAppUser.upiId!.isEmpty) {
      final newUpiId = await _showUpiIdInputDialog(context);
      if (newUpiId != null && newUpiId.isNotEmpty) {
        // Validate UPI ID format
        if (!_isValidUpiId(newUpiId)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Invalid UPI ID format. Please enter a valid UPI ID (e.g., name@bank)'),
              backgroundColor: Colors.red[800],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              duration: const Duration(seconds: 3),
            ),
          );
          return;
        }

        await _userService.updateUser(currentUserUid, {'upiId': newUpiId});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Your UPI ID has been saved.'),
              backgroundColor: Colors.blueGrey[800],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        currentUserAppUser = await _userService.getUser(currentUserUid);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Your UPI ID is required to make payments.'),
              backgroundColor: Colors.red[800],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    }

    // Use the static settlement calculation method from GroupMembersPage
    final settlementTransactions = GroupMembersPage.calculateSettlementTransactions(balances);

    if (settlementTransactions.isEmpty) {
      if (mounted) {
        showInfoSnackBar(context, 'Your balances are settled in this group.');
      }
      return;
    }

    // Find the first transaction where current user is involved
    var currentUserTransaction = settlementTransactions.firstWhere(
      (transaction) => transaction['from'] == currentUserUid || transaction['to'] == currentUserUid,
      orElse: () => <String, dynamic>{},
    );

    if (currentUserTransaction.isEmpty) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              backgroundColor: Colors.grey[850],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text("Settle All Dues", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Text("No immediate payments or receivables for you in this group.", style: TextStyle(color: Colors.grey[300])),
              actions: <Widget>[
                TextButton(
                  child: const Text("OK", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            );
          },
        );
      }
      return;
    }

    final fromUid = currentUserTransaction['from'] as String;
    final toUid = currentUserTransaction['to'] as String;
    final amount = currentUserTransaction['amount'] as double;

    if (fromUid == currentUserUid) {
      // Current user needs to pay someone
      final payeeUser = await _userService.getUser(toUid);
      if (payeeUser == null || payeeUser.upiId == null || payeeUser.upiId!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_memberNames[toUid] ?? toUid} does not have a UPI ID set. Cannot initiate payment.'),
              backgroundColor: Colors.red[800],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Validate payee's UPI ID
      if (!_isValidUpiId(payeeUser.upiId!)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_memberNames[toUid] ?? toUid} has an invalid UPI ID format. Please ask them to update it.'),
              backgroundColor: Colors.red[800],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      print('Initiating payment to:');
      print('Payee UPI ID: ${payeeUser.upiId}');
      print('Payee Name: ${_memberNames[toUid] ?? toUid}');
      print('Amount: $amount');

      await launchUPIPayment(
        upiId: payeeUser.upiId!,
        name: _memberNames[toUid] ?? toUid,
        amount: amount,
        transactionNote: 'Settlement for ${widget.group.name}',
      );
    } else if (toUid == currentUserUid) {
      // Someone needs to pay the current user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_memberNames[fromUid] ?? fromUid} owes you ${_currencyFormat.format(amount)}. Please ask them to pay.'),
            backgroundColor: Colors.blueGrey[800],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Helper method to validate UPI ID format
  bool _isValidUpiId(String upiId) {
    // Basic UPI ID validation: should contain @ and be at least 5 characters
    return upiId.contains('@') && upiId.length >= 5;
  }

  Future<String?> _showUpiIdInputDialog(BuildContext context) async {
    String? upiId;
    return showDialog<String>(
      context: context,
      barrierDismissible: false, // User must enter UPI ID
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Enter Your UPI ID',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'To facilitate payments, please enter your UPI ID. This will be saved to your profile.',
                  style: TextStyle(color: Colors.grey[300]),
                ),
                const SizedBox(height: 20),
                TextField(
                  onChanged: (value) {
                    upiId = value;
                  },
                  decoration: InputDecoration(
                    labelText: 'UPI ID (e.g., yourname@bank)',
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    filled: true,
                    fillColor: Colors.grey[800],
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[700]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blueAccent),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Save',
                style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(upiId);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserUid = FirebaseAuth.instance.currentUser!.uid;
    final bool isInsightsTab = _tabController.index == 1;

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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.group.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.fingerprint,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.group.id,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.people, color: Colors.white),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => GroupMembersPage(group: widget.group),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              groupId: widget.group.id,
                              groupName: widget.group.name,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Expenses'),
                  Tab(text: 'Insights'),
                ],
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey[600],
                indicatorColor: Colors.blueAccent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorWeight: 4.0,
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    StreamBuilder<List<Expense>>(
                      stream: _expenseService.getGroupExpenses(widget.group.id),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.red[900]?.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red[900]!),
                              ),
                              child: Text(
                                'Error: ${snapshot.error}',
                                style: TextStyle(color: Colors.red[300]),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }

                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          );
                        }

                        final expenses = snapshot.data ?? [];

                        if (expenses.isEmpty) {
                          return Center(
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.receipt_long_outlined,
                                    size: 80,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No expenses yet',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 20,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Add an expense to start splitting',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return FadeTransition(
                          opacity: _fadeAnimation,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: expenses.length,
                            itemBuilder: (context, index) {
                              final expense = expenses[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.grey[900]!,
                                        Colors.grey[850]!,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => EditExpensePage(
                                            group: widget.group,
                                            expense: expense,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            expense.title,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            expense.description,
                                            style: TextStyle(color: Colors.grey[400]),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Icon(Icons.person, size: 16, color: Colors.grey[600]),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Paid by: ${_memberNames[expense.paidBy] ?? expense.paidBy}',
                                                style: TextStyle(color: Colors.grey[500]),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                                              const SizedBox(width: 4),
                                              Text(
                                                DateFormat('MMM dd, yyyy - hh:mm a').format(expense.paidAt),
                                                style: TextStyle(color: Colors.grey[500]),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          if (expense.category != null)
                                            Row(
                                              children: [
                                                Icon(Icons.category, size: 16, color: Colors.grey[600]),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Category: ${expense.category}',
                                                  style: TextStyle(color: Colors.grey[500]),
                                                ),
                                              ],
                                            ),
                                          const SizedBox(height: 8),
                                          Align(
                                            alignment: Alignment.bottomRight,
                                            child: Text(
                                              _currencyFormat.format(expense.amount),
                                              style: const TextStyle(
                                                color: Colors.blueAccent,
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          ...expense.splitBetween.map((memberId) {
                                            final isPaid = expense.paidStatus[memberId] ?? false;
                                            final isCurrentUser = memberId == FirebaseAuth.instance.currentUser!.uid;
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    '${_memberNames[memberId] ?? memberId} owes',
                                                    style: TextStyle(color: Colors.grey[400]),
                                                  ),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        _currencyFormat.format(expense.splitAmounts[memberId] ?? 0.0),
                                                        style: TextStyle(
                                                          color: isPaid ? Colors.greenAccent : Colors.orangeAccent,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      if (isCurrentUser && !isPaid)
                                                        GestureDetector(
                                                          onTap: () async {
                                                            await _expenseService.markExpenseAsPaid(widget.group.id, expense.id, memberId);
                                                          },
                                                          child: const Padding(
                                                            padding: EdgeInsets.only(left: 8.0),
                                                            child: Icon(
                                                              Icons.check_circle_outline,
                                                              color: Colors.orangeAccent,
                                                              size: 20,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                    StreamBuilder<List<Expense>>(
                      stream: _expenseService.getGroupExpenses(widget.group.id),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Error: ${snapshot.error}',
                              style: TextStyle(color: Colors.red[300]),
                            ),
                          );
                        }

                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          );
                        }

                        final expenses = snapshot.data ?? [];
                        final categorySpending = _calculateCategorySpending(expenses);
                        final totalSpending = expenses.fold(0.0, (sum, item) => sum + item.amount);

                        if (categorySpending.isEmpty) {
                          return Center(
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.insights_outlined,
                                    size: 80,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No insights yet',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 20,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Add expenses to see your spending insights',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return FadeTransition(
                          opacity: _fadeAnimation,
                          child: Column(
                            children: [
                              Expanded(
                                child: ListView(
                                  padding: const EdgeInsets.all(16),
                                  children: [
                                    Text(
                                      'Total Group Spending: ${_currencyFormat.format(totalSpending)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 24),
                                    const Text(
                                      'Spending by Category:',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    ...categorySpending.entries.map((entry) {
                                      final category = entry.key;
                                      final amount = entry.value;
                                      final percentage = (amount / totalSpending) * 100;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              category,
                                              style: TextStyle(color: Colors.grey[300], fontSize: 16),
                                            ),
                                            Text(
                                              '${_currencyFormat.format(amount)} (${percentage.toStringAsFixed(1)}%)',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Align(
                                  alignment: Alignment.centerLeft, // Align button to the left
                                  child: FractionallySizedBox(
                                    widthFactor: 0.75, // Occupy 75% of the parent's width
                                    child: ElevatedButton(
                                      onPressed: () async {
                                        await _settleTransactions(expenses);
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        elevation: 5,
                                        minimumSize: const Size.fromHeight(50),
                                        shadowColor: Colors.green.withOpacity(0.4),
                                      ),
                                      child: const Text(
                                        'Settle all dues',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: isInsightsTab ? null : FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateExpensePage(group: widget.group),
            ),
          );
        },
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}