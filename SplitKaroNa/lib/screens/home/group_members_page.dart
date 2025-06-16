import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/group.dart';
import '../../models/expense.dart';
import '../../services/expense_service.dart';
import '../../models/app_user.dart';
import '../../services/user_service.dart';
import '../../services/group_service.dart';
import '../../utils/snackbar_helper.dart';

class GroupMembersPage extends StatefulWidget {
  final Group group;

  const GroupMembersPage({super.key, required this.group});

  @override
  State<GroupMembersPage> createState() => _GroupMembersPageState();

  // Make settlement calculation available statically
  static List<Map<String, dynamic>> calculateSettlementTransactions(Map<String, double> balances) {
    List<Map<String, dynamic>> transactions = [];
    
    List<MapEntry<String, double>> debtors = [];
    List<MapEntry<String, double>> creditors = [];
    
    balances.forEach((userId, amount) {
      if (amount < -0.01) { // Negative balance means they owe money (debtor)
        debtors.add(MapEntry(userId, -amount)); // Store as positive for easier calculation
      } else if (amount > 0.01) { // Positive balance means they are owed money (creditor)
        creditors.add(MapEntry(userId, amount));
      }
    });

    debtors.sort((a, b) => b.value.compareTo(a.value));
    creditors.sort((a, b) => b.value.compareTo(a.value));

    while (debtors.isNotEmpty && creditors.isNotEmpty) {
      var debtor = debtors.first;
      var creditor = creditors.first;
      
      double payment = debtor.value < creditor.value ? debtor.value : creditor.value;
      
      transactions.add({
        'from': debtor.key,  // Debtor pays to creditor
        'to': creditor.key,
        'amount': payment,
      });

      debtor = MapEntry(debtor.key, debtor.value - payment);
      creditor = MapEntry(creditor.key, creditor.value - payment);

      debtors.removeAt(0);
      creditors.removeAt(0);

      if (debtor.value > 0.01) {
        int insertIndex = debtors.indexWhere((d) => d.value < debtor.value);
        if (insertIndex == -1) {
          debtors.add(debtor);
        } else {
          debtors.insert(insertIndex, debtor);
        }
        debtors.sort((a, b) => b.value.compareTo(a.value));
      }
      
      if (creditor.value > 0.01) {
        int insertIndex = creditors.indexWhere((c) => c.value < creditor.value);
        if (insertIndex == -1) {
          creditors.add(creditor);
        } else {
          creditors.insert(insertIndex, creditor);
        }
        creditors.sort((a, b) => b.value.compareTo(a.value));
      }
    }

    return transactions;
  }
}

class _GroupMembersPageState extends State<GroupMembersPage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final _expenseService = ExpenseService();
  final UserService _userService = UserService();
  final _currencyFormat = NumberFormat.currency(symbol: '₹');
  
  // Cache for member names and data
  final Map<String, String> _memberNames = {};
  List<Expense>? _cachedExpenses;
  Map<String, double>? _cachedBalances;
  List<Map<String, dynamic>>? _cachedSettlements;
  bool _isLoading = true;
  bool _isRefreshing = false;

  // Add new properties for animations and UI state
  final _scrollController = ScrollController();
  bool _showScrollToTop = false;
  static const _scrollThreshold = 200.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
    _scrollController.addListener(_handleScroll);
    _initializeData();
  }

  void _handleScroll() {
    if (_scrollController.offset > _scrollThreshold && !_showScrollToTop) {
      setState(() => _showScrollToTop = true);
    } else if (_scrollController.offset <= _scrollThreshold && _showScrollToTop) {
      setState(() => _showScrollToTop = false);
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _initializeData() async {
    if (!_isRefreshing) {
      setState(() => _isLoading = true);
    }
    
    try {
      await Future.wait([
        _fetchMemberNames(),
        _preloadExpenses(),
      ]);
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
        _animationController.forward();
      }
    }
  }

  Future<void> _preloadExpenses() async {
    try {
      final expenses = await _expenseService.getGroupExpenses(widget.group.id).first;
      if (mounted) {
        setState(() {
          _cachedExpenses = expenses;
          _cachedBalances = _calculateBalances(expenses);
          _cachedSettlements = GroupMembersPage.calculateSettlementTransactions(_cachedBalances!);
        });
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e);
      }
    }
  }

  Future<void> _fetchMemberNames() async {
    final futures = widget.group.members.map((memberId) async {
      if (_memberNames.containsKey(memberId)) {
        return MapEntry(memberId, _memberNames[memberId]!);
      }
      final user = await _userService.getUser(memberId);
      return MapEntry(memberId, user?.name ?? user?.email ?? memberId);
    });
    
    final results = await Future.wait(futures);
    if (mounted) {
      setState(() {
        _memberNames.addAll(Map.fromEntries(results));
      });
    }
  }

  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    await _initializeData();
  }

  Map<String, double> _calculateBalances(List<Expense> expenses) {
    final Map<String, double> balances = {};

    // Initialize balances to 0.0 for all members
    for (String memberId in widget.group.members) {
      balances[memberId] = 0.0;
    }

    for (var expense in expenses) {
      // Payer's balance increases (they are owed money)
      balances.update(
        expense.paidBy,
        (value) => value + expense.amount,
        ifAbsent: () => expense.amount,
      );

      // Each split participant's balance decreases (they owe money)
      expense.splitAmounts.forEach((userId, amount) {
        balances.update(
          userId,
          (value) => value - amount,
          ifAbsent: () => -amount,
        );
      });
    }
    return balances;
  }

  Future<void> _confirmRemoveMember(BuildContext context, String memberId, String memberName, bool isCurrentUser, bool isOnlyMember) async {
    String confirmationMessage;
    if (isCurrentUser) {
      confirmationMessage = 'Are you sure you want to remove yourself from this group? You will no longer have access to its expenses and will be navigated back to the home page.';
    } else if (isOnlyMember) {
      confirmationMessage = 'Are you sure you want to remove $memberName from this group? As they are the only member left, this group will be deleted.';
    } else {
      confirmationMessage = 'Are you sure you want to remove $memberName from this group?';
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Remove Member',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            confirmationMessage,
            style: TextStyle(color: Colors.grey[300]),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
            ),
            TextButton(
              child: const Text(
                'Remove',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _removeMemberFromGroup(memberId, isCurrentUser, isOnlyMember);
    }
  }

  Future<void> _confirmLeaveGroup(BuildContext context, String memberId, String memberName, bool isOnlyMember) async {
    String confirmationMessage;
    if (isOnlyMember) {
      confirmationMessage = 'Are you sure you want to leave this group? As you are the only member left, this group will be deleted.';
    } else {
      confirmationMessage = 'Are you sure you want to leave this group? You will no longer have access to its expenses.';
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Leave Group',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            confirmationMessage,
            style: TextStyle(color: Colors.grey[300]),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
            ),
            TextButton(
              child: const Text(
                'Leave',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _leaveGroup(memberId, isOnlyMember);
    }
  }

  Future<void> _removeMemberFromGroup(String memberId, bool isCurrentUser, bool isOnlyMember) async {
    try {
      final groupService = GroupService();
      Group currentGroup = widget.group;

      List<String> updatedMembers = List.from(currentGroup.members);
      updatedMembers.remove(memberId);

      if (updatedMembers.isEmpty) {
        await _deleteGroup(currentGroup.id);
        if (mounted) {
          showInfoSnackBar(context, 'Group deleted as no members remained.');
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        await groupService.updateGroup(currentGroup.id, {'members': updatedMembers});
        if (mounted) {
          showInfoSnackBar(context, '${_memberNames[memberId] ?? memberId} has been removed from the group.');
          if (isCurrentUser && mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e);
      }
    }
  }

  Future<void> _leaveGroup(String memberId, bool isOnlyMember) async {
    try {
      final groupService = GroupService();
      Group currentGroup = widget.group;

      List<String> updatedMembers = List.from(currentGroup.members);
      updatedMembers.remove(memberId);

      if (updatedMembers.isEmpty) {
        await _deleteGroup(currentGroup.id);
        if (mounted) {
          showInfoSnackBar(context, 'You have left the group. Group deleted as no members remained.');
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        await groupService.updateGroup(currentGroup.id, {'members': updatedMembers});
        if (mounted) {
          showInfoSnackBar(context, 'You have left the group.');
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e);
      }
    }
  }

  Future<void> _deleteGroup(String groupId) async {
    try {
      final groupService = GroupService();
      await groupService.deleteGroup(groupId);
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserUid = FirebaseAuth.instance.currentUser!.uid;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // App Bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Back',
                        ),
                        Expanded(
                          child: Text(
                            'Members of ${widget.group.name}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (_isRefreshing)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.white),
                            onPressed: _refreshData,
                            tooltip: 'Refresh',
                          ),
                      ],
                    ),
                  ),
                ),

                // Content
                Expanded(
                  child: _isLoading && !_isRefreshing
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _refreshData,
                          child: ListView(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            children: [
                              if (widget.group.members.isEmpty)
                                _buildEmptyState()
                              else
                                _buildMembersList(currentUserUid),

                              if (_cachedSettlements != null && _cachedSettlements!.isNotEmpty)
                                _buildSettlementSection(),
                            ],
                          ),
                        ),
                ),
              ],
            ),

            // Scroll to top button
            if (_showScrollToTop)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.grey[850],
                  child: const Icon(Icons.arrow_upward, color: Colors.white),
                  onPressed: _scrollToTop,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersList(String currentUserUid) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Members',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...widget.group.members.map((memberId) {
          final isCurrentUser = memberId == currentUserUid;
          final isOnlyMember = widget.group.members.length == 1;
          return _buildMemberTile(
            memberId,
            _memberNames[memberId] ?? memberId,
            isCurrentUser,
            isOnlyMember,
          );
        }).toList(),
      ],
    );
  }

  Widget _buildMemberTile(String memberId, String memberName, bool isCurrentUser, bool isOnlyMember) {
    final balance = _cachedBalances?[memberId] ?? 0.0;
    final balanceColor = _getBalanceColor(balance);
    final isPositive = balance > 0.01;  // Positive means they are owed money
    final isNegative = balance < -0.01;  // Negative means they owe money

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey[850]!,
            Colors.grey[900]!,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.blueAccent.withOpacity(0.2),
                        Colors.blueAccent.withOpacity(0.1),
                      ],
                    ),
                  ),
                  child: CircleAvatar(
                    backgroundColor: Colors.transparent,
                    child: Icon(Icons.person, color: Colors.blueAccent[200], size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        memberName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_cachedBalances != null)
                        Row(
                          children: [
                            Icon(
                              isPositive ? Icons.arrow_downward : isNegative ? Icons.arrow_upward : Icons.check_circle,
                              color: balanceColor,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatBalance(balance),
                              style: TextStyle(
                                color: balanceColor,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (isCurrentUser)
                  _buildActionButton(
                    icon: Icons.exit_to_app,
                    color: Colors.blue[300]!,
                    tooltip: 'Leave Group',
                    onPressed: () => _confirmLeaveGroup(context, memberId, memberName, isOnlyMember),
                  )
                else
                  _buildActionButton(
                    icon: Icons.delete_outline,
                    color: Colors.red[300]!,
                    tooltip: 'Remove Member',
                    onPressed: () => _confirmRemoveMember(context, memberId, memberName, isCurrentUser, isOnlyMember),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildSettlementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text(
          'Settlement Summary',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ..._cachedSettlements!.map(_buildSettlementTile).toList(),
      ],
    );
  }

  Widget _buildSettlementTile(Map<String, dynamic> transaction) {
    final fromId = transaction['from'] as String;
    final toId = transaction['to'] as String;
    final amount = transaction['amount'] as double;
    final currentUserUid = FirebaseAuth.instance.currentUser!.uid;
    final isInvolved = fromId == currentUserUid || toId == currentUserUid;
    final isReceiving = toId == currentUserUid;
    final color = _getSettlementColor(isReceiving);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey[850]!,
            Colors.grey[900]!,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(
            isReceiving ? Icons.arrow_downward : Icons.arrow_upward,
            color: color,
          ),
        ),
        title: Text(
          isInvolved
              ? isReceiving
                  ? '${_memberNames[fromId] ?? fromId} pays you'
                  : 'You pay ${_memberNames[toId] ?? toId}'
              : '${_memberNames[fromId] ?? fromId} pays ${_memberNames[toId] ?? toId}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Text(
          _currencyFormat.format(amount),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_alt_outlined,
              size: 64,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 16),
            Text(
              'No members yet',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Share the group ID to add members',
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

  Color _getBalanceColor(double balance) {
    if (balance > 0.01) return Colors.green[300]!;  // Green for being owed money (positive balance)
    if (balance < -0.01) return Colors.red[300]!;  // Red for owing money (negative balance)
    return Colors.grey[400]!;
  }

  Color _getSettlementColor(bool isReceiving) {
    return isReceiving ? Colors.green[300]! : Colors.red[300]!;  // Green for receiving, red for paying
  }

  String _formatBalance(double balance) {
    if (balance > 0.01) return 'Gets back ${_currencyFormat.format(balance)}';  // Positive balance means they are owed money
    if (balance < -0.01) return 'Owes ${_currencyFormat.format(-balance)}';  // Negative balance means they owe money
    return 'Settled';
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handlePayment(BuildContext context, String fromId, String toId, double amount) async {
    final currentUserUid = FirebaseAuth.instance.currentUser!.uid;
    if (fromId != currentUserUid && toId != currentUserUid) {
      showInfoSnackBar(context, 'You can only initiate payments for transactions you are involved in.');
      return;
    }

    final payeeId = fromId == currentUserUid ? toId : fromId;
    final payeeUser = await _userService.getUser(payeeId);
    if (payeeUser == null || payeeUser.upiId == null || payeeUser.upiId!.isEmpty) {
      showErrorSnackBar(context, '${_memberNames[payeeId] ?? payeeId} does not have a UPI ID set. Cannot initiate payment.');
      return;
    }

    final upiUrl = 'upi://pay?pa=${payeeUser.upiId}&pn=${payeeUser.name}&am=${amount.toStringAsFixed(2)}&cu=INR';
    final uri = Uri.parse(upiUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        showErrorSnackBar(context, 'Could not launch UPI app.');
      }
    }
  }
} 