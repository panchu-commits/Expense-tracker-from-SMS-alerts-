import 'dart:io';
import 'package:flutter/material.dart';
import 'package:telephony/telephony.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/transaction_model.dart';
import 'services/db_helper.dart';
import 'services/sms_parser.dart';

@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  final tx = SmsParser.parse(
    message.body,
    message.address,
    message.date ?? DateTime.now().millisecondsSinceEpoch,
    id: message.id?.toString(),
  );
  if (tx != null) {
    await DBHelper.instance.insertTransaction(tx);
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      title: 'CashTrack',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Telephony telephony = Telephony.instance;
  List<TransactionModel> _transactions = [];
  double _totalIncome = 0.0;
  double _totalExpense = 0.0;
  double _monthlyBudget = 25000.0;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;

  static const List<String> _categories = [
    'Food & Dining',
    'Travel & Fuel',
    'Shopping',
    'Bills & Utilities',
    'Entertainment',
    'Income / Credit',
    'Miscellaneous',
  ];

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadBudget();
    await _initSMSListener();
    await _fetchTransactions();
  }

  Future<void> _loadBudget() async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _monthlyBudget = sp.getDouble('monthly_budget') ?? 25000.0;
    });
  }

  Future<void> _initSMSListener() async {
    bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
    if (permissionsGranted ?? false) {
      telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) async {
          final tx = SmsParser.parse(
            message.body,
            message.address,
            message.date ?? DateTime.now().millisecondsSinceEpoch,
            id: message.id?.toString(),
          );
          if (tx != null) {
            await DBHelper.instance.insertTransaction(tx);
            _fetchTransactions();
          }
        },
        onBackgroundMessage: backgroundMessageHandler,
      );

      final sp = await SharedPreferences.getInstance();
      if (!(sp.getBool('historical_imported') ?? false)) {
        await _importHistoricalSms();
        await sp.setBool('historical_imported', true);
      }
    }
  }

  Future<void> _importHistoricalSms() async {
    setState(() => _loading = true);
    final sixMonthsAgo =
        DateTime.now().subtract(const Duration(days: 180)).millisecondsSinceEpoch;
    List<SmsMessage> messages = await telephony.getInboxSms(
      columns: [SmsColumn.ID, SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
    );

    for (var msg in messages) {
      if ((msg.date ?? 0) >= sixMonthsAgo) {
        final tx = SmsParser.parse(
          msg.body,
          msg.address,
          msg.date ?? 0,
          id: msg.id?.toString(),
        );
        if (tx != null) {
          await DBHelper.instance.insertTransaction(tx);
        }
      }
    }
    await _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    final items = await DBHelper.instance.getMonthlyTransactions(
      _selectedMonth.year,
      _selectedMonth.month,
    );
    double inc = 0.0;
    double exp = 0.0;

    for (var i in items) {
      if (i.type == 'INCOME') inc += i.amount;
      if (i.type == 'EXPENSE') exp += i.amount;
    }

    if (mounted) {
      setState(() {
        _transactions = items;
        _transactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _totalIncome = inc;
        _totalExpense = exp;
        _loading = false;
      });
    }
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + offset);
      _loading = true;
    });
    _fetchTransactions();
  }

  Future<void> _exportCSV() async {
    final all = await DBHelper.instance.getAllTransactions();
    List<List<dynamic>> rows = [
      ['ID', 'Date', 'Type', 'Amount (INR)', 'Category', 'Merchant/Party', 'Account/Mode', 'Source', 'Notes']
    ];

    for (var item in all) {
      rows.add([
        item.id,
        DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.timestamp)),
        item.type,
        item.amount.toStringAsFixed(2),
        item.category,
        item.merchant,
        item.account,
        item.isManual == 1 ? 'Manual' : 'Auto-SMS',
        item.notes,
      ]);
    }

    String csvData = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/CashTrack_Backup_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');
    await file.writeAsString(csvData);
    await Share.shareXFiles([XFile(file.path)], text: 'CashTrack Expense & Revenue Backup (CSV/Excel)');
  }

  void _showTransactionSheet({TransactionModel? existing}) {
    final amountController = TextEditingController(
      text: existing != null ? existing.amount.toStringAsFixed(2) : '',
    );
    final merchantController = TextEditingController(
      text: existing != null ? existing.merchant : '',
    );
    final accountController = TextEditingController(
      text: existing != null ? existing.account : 'Cash / UPI',
    );
    final notesController = TextEditingController(
      text: existing != null ? existing.notes : '',
    );
    String type = existing?.type ?? 'EXPENSE';
    String category = existing != null && _categories.contains(existing.category)
        ? existing.category
        : _categories.first;
    DateTime txDate = existing != null
        ? DateTime.fromMillisecondsSinceEpoch(existing.timestamp)
        : DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      existing == null ? 'Add Transaction' : 'Edit Transaction',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (existing != null && existing.id != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                          await DBHelper.instance.deleteTransaction(existing.id!);
                          if (mounted) Navigator.pop(ctx);
                          _fetchTransactions();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('Expense (Debit)'),
                      selected: type == 'EXPENSE',
                      onSelected: (_) => setModalState(() => type = 'EXPENSE'),
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('Revenue (Income)'),
                      selected: type == 'INCOME',
                      onSelected: (_) => setModalState(() {
                        type = 'INCOME';
                        category = 'Income / Credit';
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹)',
                    prefixIcon: Icon(Icons.currency_rupee),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: merchantController,
                  decoration: const InputDecoration(
                    labelText: 'Merchant / Description',
                    prefixIcon: Icon(Icons.storefront),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category),
                  ),
                  items: _categories
                      .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                      .toList(),
                  onChanged: (val) => setModalState(() => category = val!),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: accountController,
                  decoration: const InputDecoration(
                    labelText: 'Payment Mode (Cash, UPI, Card)',
                    prefixIcon: Icon(Icons.account_balance_wallet),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text('Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(txDate)}'),
                  trailing: TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: txDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (picked != null) {
                        setModalState(() {
                          txDate = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                            txDate.hour,
                            txDate.minute,
                          );
                        });
                      }
                    },
                    child: const Text('Change'),
                  ),
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes / Reference',
                    prefixIcon: Icon(Icons.notes),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    final amt = double.tryParse(amountController.text.trim());
                    if (amt != null && amt > 0) {
                      final model = TransactionModel(
                        id: existing?.id,
                        smsId: existing?.smsId,
                        type: type,
                        amount: amt,
                        category: category,
                        merchant: merchantController.text.trim().isEmpty
                            ? (type == 'EXPENSE' ? 'Cash Expense' : 'Manual Income')
                            : merchantController.text.trim(),
                        account: accountController.text.trim().isEmpty
                            ? 'Manual'
                            : accountController.text.trim(),
                        timestamp: txDate.millisecondsSinceEpoch,
                        notes: notesController.text.trim(),
                        isManual: existing?.isManual ?? 1,
                      );
                      if (existing == null) {
                        await DBHelper.instance.insertTransaction(model);
                      } else {
                        await DBHelper.instance.updateTransaction(model);
                      }
                      if (mounted) Navigator.pop(ctx);
                      _fetchTransactions();
                    }
                  },
                  child: Text(existing == null ? 'Save Transaction' : 'Update Transaction'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double budgetPercent =
        _monthlyBudget > 0 ? (_totalExpense / _monthlyBudget) : 0.0;
    final double netBalance = _totalIncome - _totalExpense;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CashTrack'),
        actions: [
          IconButton(
            tooltip: 'Sync SMS Inbox',
            icon: const Icon(Icons.sync),
            onPressed: _importHistoricalSms,
          ),
          IconButton(
            tooltip: 'Export CSV / Excel',
            icon: const Icon(Icons.download),
            onPressed: _exportCSV,
          ),
          IconButton(
            tooltip: 'Monthly Budget',
            icon: const Icon(Icons.tune),
            onPressed: () {
              final budgetCtrl = TextEditingController(
                text: _monthlyBudget.toStringAsFixed(0),
              );
              showDialog(
                context: context,
                builder: (dCtx) => AlertDialog(
                  title: const Text('Set Monthly Expense Budget (₹)'),
                  content: TextField(
                    controller: budgetCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(prefixText: '₹ '),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dCtx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        final val = double.tryParse(budgetCtrl.text.trim());
                        if (val != null && val > 0) {
                          final sp = await SharedPreferences.getInstance();
                          await sp.setDouble('monthly_budget', val);
                          setState(() => _monthlyBudget = val);
                        }
                        if (mounted) Navigator.pop(dCtx);
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchTransactions,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => _changeMonth(-1),
                      ),
                      Text(
                        DateFormat('MMMM yyyy').format(_selectedMonth),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => _changeMonth(1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Card(
                    color: Colors.blueGrey.shade900,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Revenue / Inflow', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                                  Text(
                                    '₹${_totalIncome.toStringAsFixed(2)}',
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('Expenses / Debit', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                                  Text(
                                    '₹${_totalExpense.toStringAsFixed(2)}',
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(height: 24, color: Colors.white24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Net Cash Flow:', style: TextStyle(color: Colors.white70)),
                              Text(
                                '${netBalance >= 0 ? '+' : ''}₹${netBalance.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: netBalance >= 0 ? Colors.greenAccent : Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: budgetPercent > 1.0 ? 1.0 : budgetPercent,
                            color: budgetPercent >= 1.0
                                ? Colors.redAccent
                                : (budgetPercent >= 0.8 ? Colors.orangeAccent : Colors.tealAccent),
                            backgroundColor: Colors.white12,
                            minHeight: 8,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Budget Used: ₹${_totalExpense.toStringAsFixed(0)} / ₹${_monthlyBudget.toStringAsFixed(0)} (${(budgetPercent * 100).toStringAsFixed(1)}%)',
                            style: TextStyle(
                              color: budgetPercent >= 0.8 ? Colors.amberAccent : Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (budgetPercent >= 0.8)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Card(
                        color: budgetPercent >= 1.0 ? Colors.red.shade100 : Colors.orange.shade100,
                        child: ListTile(
                          leading: Icon(
                            Icons.warning_amber_rounded,
                            color: budgetPercent >= 1.0 ? Colors.red.shade900 : Colors.orange.shade900,
                          ),
                          title: Text(
                            budgetPercent >= 1.0
                                ? 'Monthly budget exceeded!'
                                : 'You have used over 80% of your monthly budget.',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  if (_totalExpense > 0) ...[
                    const SizedBox(height: 16),
                    const Text('Category Spending Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 170,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 36,
                          sections: _generatePieChartSections(),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Transactions (Tap to Edit)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('${_transactions.length} records', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_transactions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'No transactions recorded for this month. Tap + to add manually or Sync SMS.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ..._transactions.map(
                    (t) => Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        onTap: () => _showTransactionSheet(existing: t),
                        leading: CircleAvatar(
                          backgroundColor: t.type == 'INCOME' ? Colors.green.shade100 : Colors.red.shade100,
                          child: Icon(
                            t.type == 'INCOME' ? Icons.south_west : Icons.north_east,
                            color: t.type == 'INCOME' ? Colors.green.shade800 : Colors.red.shade800,
                          ),
                        ),
                        title: Text(t.merchant, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${t.category} • ${t.account} • ${DateFormat('dd MMM, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(t.timestamp))}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Text(
                          '${t.type == 'INCOME' ? '+' : '-'}₹${t.amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: t.type == 'INCOME' ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 64),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTransactionSheet(),
        icon: const Icon(Icons.add),
        label: const Text('Add Entry'),
      ),
    );
  }

  List<PieChartSectionData> _generatePieChartSections() {
    Map<String, double> categorySums = {};
    for (var tx in _transactions.where((x) => x.type == 'EXPENSE')) {
      categorySums[tx.category] = (categorySums[tx.category] ?? 0.0) + tx.amount;
    }

    final colors = [
      Colors.teal,
      Colors.orange,
      Colors.indigo,
      Colors.pink,
      Colors.amber.shade700,
      Colors.cyan,
      Colors.blueGrey,
    ];
    int idx = 0;

    return categorySums.entries.map((e) {
      final color = colors[idx % colors.length];
      idx++;
      final pct = (_totalExpense > 0) ? (e.value / _totalExpense * 100) : 0.0;
      return PieChartSectionData(
        value: e.value,
        color: color,
        title: pct >= 8 ? '${e.key.split(' ').first} ${pct.toStringAsFixed(0)}%' : '',
        titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
        radius: 52,
      );
    }).toList();
  }
}
