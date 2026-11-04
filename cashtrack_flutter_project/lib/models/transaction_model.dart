class TransactionModel {
  final int? id;
  final String? smsId;
  final String type; // EXPENSE or INCOME
  final double amount;
  final String category;
  final String merchant;
  final String account;
  final int timestamp;
  final String notes;
  final int isManual;

  TransactionModel({
    this.id,
    this.smsId,
    required this.type,
    required this.amount,
    required this.category,
    required this.merchant,
    required this.account,
    required this.timestamp,
    required this.notes,
    required this.isManual,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'sms_id': smsId,
    'type': type,
    'amount': amount,
    'category': category,
    'merchant': merchant,
    'account': account,
    'timestamp': timestamp,
    'notes': notes,
    'is_manual': isManual,
  };

  factory TransactionModel.fromMap(Map<String, dynamic> map) => TransactionModel(
    id: map['id'] as int?,
    smsId: map['sms_id'] as String?,
    type: map['type'] as String,
    amount: (map['amount'] as num).toDouble(),
    category: map['category'] as String,
    merchant: map['merchant'] as String,
    account: map['account'] as String,
    timestamp: map['timestamp'] as int,
    notes: (map['notes'] ?? '') as String,
    isManual: map['is_manual'] as int,
  );
}
