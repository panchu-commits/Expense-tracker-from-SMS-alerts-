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
                  leading: const Icon(Icons
