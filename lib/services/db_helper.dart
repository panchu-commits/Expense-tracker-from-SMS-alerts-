import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction_model.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;

  DBHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('cashtrack.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sms_id TEXT UNIQUE,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            category TEXT NOT NULL,
            merchant TEXT NOT NULL,
            account TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            notes TEXT,
            is_manual INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> insertTransaction(TransactionModel tx) async {
    final db = await instance.database;
    return await db.insert(
      'transactions',
      tx.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> updateTransaction(TransactionModel tx) async {
    final db = await instance.database;
    return await db.update(
      'transactions',
      tx.toMap(),
      where: 'id = ?',
      whereArgs: [tx.id],
    );
  }

  Future<List<TransactionModel>> getMonthlyTransactions(int year, int month) async {
    final db = await instance.database;
    final start = DateTime(year, month, 1).millisecondsSinceEpoch;
    final end = DateTime(year, month + 1, 0, 23, 59, 59, 999).millisecondsSinceEpoch;

    final result = await db.query(
      'transactions',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [start, end],
      orderBy: 'timestamp DESC',
    );
    return result.map((e) => TransactionModel.fromMap(e)).toList();
  }

  Future<List<TransactionModel>> getAllTransactions() async {
    final db = await instance.database;
    final result = await db.query('transactions', orderBy: 'timestamp DESC');
    return result.map((e) => TransactionModel.fromMap(e)).toList();
  }

  Future<int> deleteTransaction(int id) async {
    final db = await instance.database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }
}
