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
