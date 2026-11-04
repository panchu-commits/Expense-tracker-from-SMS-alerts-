import '../models/transaction_model.dart';

class SmsParser {
  static TransactionModel? parse(
    String? body,
    String? sender,
    int timestamp, {
    String? id,
  }) {
    if (body == null || body.trim().isEmpty) return null;
    final text = body.toLowerCase();

    // Filter out OTPs, promotional messages, and non-transaction alerts
    if (text.contains('otp') ||
        text.contains('one time password') ||
        text.contains('verification code') ||
        text.contains('password') ||
        text.contains('mandate') ||
        text.contains('requested') ||
        text.contains('offer') ||
        text.contains('limit') ||
        text.contains('login')) {
      return null;
    }

    String type = '';
    if (text.contains('debited') ||
        text.contains('spent') ||
        text.contains('sent rs') ||
        text.contains('paid') ||
        text.contains('transferred to') ||
        text.contains('withdrawn') ||
        text.contains('purchase')) {
      type = 'EXPENSE';
    } else if (text.contains('credited') ||
        text.contains('received') ||
        text.contains('deposited') ||
        text.contains('refund')) {
      type = 'INCOME';
    } else {
      return null;
    }

    // Match INR / Rs. / ₹ amounts
    final amountRegex = RegExp(r'(?:inr|rs\.?|₹)\s*([\d,]+(?:\.\d{1,2})?)');
    final match = amountRegex.firstMatch(text);
    if (match == null) return null;

    final rawAmount = match.group(1)!.replaceAll(',', '');
    final double? amount = double.tryParse(rawAmount);
    if (amount == null || amount <= 0) return null;

    // Extract Bank Account or Card ending digits
    final acctRegex = RegExp(
      r'(?:a/c|acct|account|card|ending)\s*(?:no\.?|ending)?\s*[*xX]*(\d{3,4})',
    );
    final acctMatch = acctRegex.firstMatch(text);
    final String account = acctMatch != null
        ? 'XX${acctMatch.group(1)!}'
        : (sender ?? 'Bank/UPI');

    // Extract Merchant / UPI VPA / Beneficiary
    String merchant = type == 'EXPENSE' ? 'UPI / Bank Debit' : 'Bank Credit';
    final vpaRegex = RegExp(r'(?:vpa|to|at|from|info[:\s])\s*([a-zA-Z0-9\.\-_@]+)');
    final vpaMatch = vpaRegex.firstMatch(text);
    if (vpaMatch != null && vpaMatch.group(1)!.length > 2) {
      merchant = vpaMatch.group(1)!.toUpperCase();
    }

    // Auto-categorize based on keywords
    String category = 'Miscellaneous';
    if (text.contains('swiggy') ||
        text.contains('zomato') ||
        text.contains('food') ||
        text.contains('hotel') ||
        text.contains('restaurant') ||
        text.contains('cafe') ||
        text.contains('bakery')) {
      category = 'Food & Dining';
    } else if (text.contains('uber') ||
        text.contains('ola') ||
        text.contains('irctc') ||
        text.contains('rail') ||
        text.contains('fuel') ||
        text.contains('petrol') ||
        text.contains('hpcl') ||
        text.contains('bpcl') ||
        text.contains('iocl')) {
      category = 'Travel & Fuel';
    } else if (text.contains('amazon') ||
        text.contains('flipkart') ||
        text.contains('myntra') ||
        text.contains('meesho') ||
        text.contains('mart') ||
        text.contains('store')) {
      category = 'Shopping';
    } else if (text.contains('electricity') ||
        text.contains('kseb') ||
        text.contains('bescom') ||
        text.contains('water') ||
        text.contains('recharge') ||
        text.contains('jio') ||
        text.contains('airtel') ||
        text.contains('bsnl') ||
        text.contains('vi ')) {
      category = 'Bills & Utilities';
    } else if (text.contains('bookmyshow') ||
        text.contains('cinema') ||
        text.contains('movie') ||
        text.contains('netflix') ||
        text.contains('spotify')) {
      category = 'Entertainment';
    } else if (type == 'INCOME') {
      category = 'Income / Credit';
    }

    return TransactionModel(
      smsId: id ?? '${timestamp}_${amount.toStringAsFixed(2)}',
      type: type,
      amount: amount,
      category: category,
      merchant: merchant,
      account: account,
      timestamp: timestamp,
      notes: body.trim(),
      isManual: 0,
    );
  }
}
