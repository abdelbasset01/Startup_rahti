import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:image_picker/image_picker.dart';
import 'package:fl_chart/fl_chart.dart';

class RevenueDashboardPage extends StatefulWidget {
  const RevenueDashboardPage({super.key});

  @override
  State<RevenueDashboardPage> createState() => _RevenueDashboardPageState();
}

class _RevenueDashboardPageState extends State<RevenueDashboardPage> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  bool _isLoading = true;
  double _totalRevenue = 0; 
  double _totalCommission = 0;
  double _paidCommission = 0;
  double get _unpaidCommission => (_totalCommission - _paidCommission) > 0 ? (_totalCommission - _paidCommission) : 0.0;

  // Data structure: year -> month -> day -> { revenue, commission }
  final Map<int, Map<int, Map<int, Map<String, double>>>> _revenueData = {};
  
  List<int> _availableYears = [];
  int? _selectedYear;
  int? _selectedMonth; // 1-12. If null, show Year view (all months)

  static const List<String> _arabicMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];

  @override
  void initState() {
    super.initState();
    _fetchRevenueData();
  }

  Future<void> _fetchRevenueData() async {
    if (currentUser == null) return;
    setState(() => _isLoading = true);

    try {
      final String uid = currentUser!.uid;
      
      final tripsSnap = await FirebaseDatabase.instance
          .ref()
          .child('trips')
          .orderByChild('driverId')
          .equalTo(uid)
          .get();

      final historySnap = await FirebaseDatabase.instance
          .ref()
          .child('history')
          .child(uid)
          .child('trips')
          .get();

      List<Map<dynamic, dynamic>> allTrips = [];

      if (tripsSnap.exists) {
        final data = tripsSnap.value as Map<dynamic, dynamic>;
        allTrips.addAll(data.values.map((e) => e as Map<dynamic, dynamic>));
      }

      if (historySnap.exists) {
        final data = historySnap.value as Map<dynamic, dynamic>;
        allTrips.addAll(data.values.map((e) => e as Map<dynamic, dynamic>));
      }

      final paymentsSnap = await FirebaseDatabase.instance.ref().child('commission_payments').child(uid).get();
      double paidAmount = 0.0;
      if (paymentsSnap.exists) {
         final data = paymentsSnap.value as Map<dynamic, dynamic>;
         data.forEach((key, val) {
            String status = val['status']?.toString() ?? 'pending';
            if (status != 'rejected') {
               paidAmount += (val['amount'] as num?)?.toDouble() ?? 0.0;
            }
         });
      }

      _revenueData.clear();
      _totalRevenue = 0;
      _totalCommission = 0;
      _paidCommission = paidAmount;
      final Set<int> yearsSet = {};

      for (var trip in allTrips) {
        String? dateStr = trip['date']?.toString();
        if (dateStr == null || dateStr.isEmpty) continue;

        DateTime? parsedDate;
        if (dateStr.contains('-')) {
          parsedDate = DateTime.tryParse(dateStr);
        } else if (dateStr.contains('/')) {
          final parts = dateStr.split('/');
          if (parts.length == 3) {
            int d = int.tryParse(parts[0]) ?? 1;
            int m = int.tryParse(parts[1]) ?? 1;
            int y = int.tryParse(parts[2]) ?? 2024;
            parsedDate = DateTime(y, m, d);
          }
        }
        
        if (parsedDate == null) continue;

        double price = (trip['price'] as num?)?.toDouble() ?? 0.0;
        double commission = (trip['commissionAmount'] as num?)?.toDouble() ?? (price * 0.10);

        _totalRevenue += (price - commission); // Net driver earnings
        _totalCommission += commission;

        int y = parsedDate.year;
        int m = parsedDate.month;
        int d = parsedDate.day;

        yearsSet.add(y);

        _revenueData[y] ??= {};
        _revenueData[y]![m] ??= {};
        _revenueData[y]![m]![d] ??= {'revenue': 0.0, 'commission': 0.0};
        
        _revenueData[y]![m]![d]!['revenue'] = _revenueData[y]![m]![d]!['revenue']! + price;
        _revenueData[y]![m]![d]!['commission'] = _revenueData[y]![m]![d]!['commission']! + commission;
      }

      _availableYears = yearsSet.toList()..sort((a,b)=>b.compareTo(a));
      if (_availableYears.isNotEmpty) {
        _selectedYear = _availableYears.first;
      } else {
        _selectedYear = DateTime.now().year;
        _availableYears = [_selectedYear!];
      }

    } catch (e) {
      debugPrint("Error fetching revenue: $e");
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("العمولة و الأرباح", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF43C59E),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF43C59E)))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSummaryCards(),
                const SizedBox(height: 24),
                _buildControls(),
                const SizedBox(height: 24),
                _buildChartContainer(),
                const SizedBox(height: 24),
                if (_unpaidCommission > 0)
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _showPaymentDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("ادفع العمولة", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: _buildInfoCard(
            title: "إجمالي أرباح السائق",
            value: "${_totalRevenue.toStringAsFixed(0)} دج",
            icon: Icons.account_balance_wallet,
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildInfoCard(
            title: "العمولة قيد الدفع",
            value: "${_unpaidCommission.toStringAsFixed(0)} دج",
            icon: Icons.money_off,
            color: Colors.redAccent,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({required String title, required String value, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: DropdownButtonHideUnderline(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: DropdownButton<int>(
                value: _selectedYear,
                hint: const Text("السنة"),
                isExpanded: true,
                items: _availableYears.map((y) {
                  return DropdownMenuItem(value: y, child: Text(y.toString()));
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedYear = val;
                    _selectedMonth = null;
                  });
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: DropdownButtonHideUnderline(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: DropdownButton<int?>(
                value: _selectedMonth,
                hint: const Text("كل الأشهر"),
                isExpanded: true,
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text("كل الأشهر")),
                  ...List.generate(12, (index) {
                    return DropdownMenuItem<int?>(
                      value: index + 1,
                      child: Text(_arabicMonths[index]),
                    );
                  })
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedMonth = val;
                  });
                },
              ),
            ),
          ),
        )
      ],
    );
  }

  Widget _buildChartContainer() {
    if (_selectedYear == null) return const SizedBox();

    final hasMonthSelected = _selectedMonth != null;

    return Container(
      height: 400,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                hasMonthSelected ? 'إيرادات شهر ${_arabicMonths[_selectedMonth! - 1]}' : "إيرادات السنة $_selectedYear",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (hasMonthSelected)
                TextButton.icon(
                  onPressed: () => setState(() => _selectedMonth = null),
                  icon: const Icon(Icons.arrow_back, size: 16, color: Color(0xFF43C59E)),
                  label: const Text("عودة", style: TextStyle(color: Color(0xFF43C59E))),
                )
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: hasMonthSelected ? _buildDailyLineChart() : _buildMonthlyBarChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyBarChart() {
    List<double> monthlyRevenue = List.filled(12, 0.0);
    double maxY = 0;

    for (int month = 1; month <= 12; month++) {
      if (_revenueData[_selectedYear] != null && _revenueData[_selectedYear]![month] != null) {
        final days = _revenueData[_selectedYear]![month]!;
        for (var dayData in days.values) {
          double rev = dayData['revenue'] ?? 0.0;
          double com = dayData['commission'] ?? 0.0;
          monthlyRevenue[month - 1] += (rev - com);
        }
      }
      if (monthlyRevenue[month - 1] > maxY) maxY = monthlyRevenue[month - 1];
    }
    
    // Set fallback if 0
    if (maxY == 0) maxY = 1000;

    List<BarChartGroupData> barGroups = [];
    for (int month = 1; month <= 12; month++) {
      double revenue = monthlyRevenue[month - 1];

      Color barColor = const Color(0xFF43C59E);
      if (revenue == 0) {
        barColor = Colors.grey.shade300;
      } else if (revenue < 2000) {
        barColor = Colors.lightGreen;
      } else if (revenue < 10000) {
        barColor = Colors.green;
      } else {
        barColor = Colors.green.shade800;
      }

      barGroups.add(
        BarChartGroupData(
          x: month,
          barRods: [
            BarChartRodData(
              toY: revenue,
              color: barColor,
              width: 16,
              borderRadius: BorderRadius.circular(4),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxY,
                color: Colors.grey.shade100,
              ),
            )
          ],
        )
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY * 1.2,
        barGroups: barGroups,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.black87,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                "${rod.toY.toStringAsFixed(0)} دج\n",
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                children: [
                  TextSpan(
                    text: _arabicMonths[group.x - 1],
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  )
                ]
              );
            },
          ),
          touchCallback: (FlTouchEvent event, barTouchResponse) {
             if (event.isInterestedForInteractions && barTouchResponse != null && barTouchResponse.spot != null) {
               final month = barTouchResponse.spot!.touchedBarGroup.x;
               if (event is FlTapUpEvent) {
                 setState(() {
                   _selectedMonth = month;
                 });
               }
             }
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value >= 1 && value <= 12) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      _arabicMonths[value.toInt() - 1].substring(0, value.toInt() == 5 ? 4 : 3),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  );
                }
                return const SizedBox();
              },
              reservedSize: 30,
            )
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _buildDailyLineChart() {
    int daysInMonth = DateUtils.getDaysInMonth(_selectedYear!, _selectedMonth!);
    List<FlSpot> spots = [];
    double maxY = 0;

    for (int day = 1; day <= daysInMonth; day++) {
      double revenue = 0;
      if (_revenueData[_selectedYear] != null && 
          _revenueData[_selectedYear]![_selectedMonth] != null && 
          _revenueData[_selectedYear]![_selectedMonth]![day] != null) {
        double rev = _revenueData[_selectedYear]![_selectedMonth]![day]!['revenue'] ?? 0.0;
        double com = _revenueData[_selectedYear]![_selectedMonth]![day]!['commission'] ?? 0.0;
        revenue = rev - com;
      }
      if (revenue > maxY) maxY = revenue;
      spots.add(FlSpot(day.toDouble(), revenue));
    }
    
    if (maxY == 0) maxY = 1000;

    return LineChart(
      LineChartData(
        minX: 1,
        maxX: daysInMonth.toDouble(),
        minY: 0,
        maxY: maxY * 1.2,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFF43C59E),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF43C59E).withValues(alpha: 0.2),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
             getTooltipColor: (_) => Colors.black87,
             getTooltipItems: (touchedSpots) {
               return touchedSpots.map((spot) => LineTooltipItem(
                 "${spot.y.toStringAsFixed(0)} دج\n",
                 const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                 children: [
                   TextSpan(
                     text: "يوم ${spot.x.toInt()}",
                     style: const TextStyle(color: Colors.grey, fontSize: 12),
                   )
                 ]
               )).toList();
             }
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 5,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(value.toInt().toString(), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                );
              },
            )
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  void _showPaymentDialog() {
     if (currentUser == null) return;
     showModalBottomSheet(
       context: context,
       isScrollControlled: true,
       backgroundColor: Colors.transparent,
       builder: (context) {
          return PaymentBottomSheet(
            uid: currentUser!.uid,
            amount: _unpaidCommission,
            onPaymentSuccess: _fetchRevenueData,
          );
       }
     );
  }
}

class PaymentBottomSheet extends StatefulWidget {
  final String uid;
  final double amount;
  final VoidCallback onPaymentSuccess;
  
  const PaymentBottomSheet({super.key, required this.uid, required this.amount, required this.onPaymentSuccess});

  @override
  State<PaymentBottomSheet> createState() => _PaymentBottomSheetState();
}

class _PaymentBottomSheetState extends State<PaymentBottomSheet> {
  File? _proofImage;
  bool _isUploading = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (pickedFile != null) {
      setState(() {
        _proofImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _confirmPayment() async {
    if (_proofImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء رفع وصل الدفع أو الإثبات')));
      return;
    }

    setState(() => _isUploading = true);
    try {
      final fileName = '${widget.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Supabase.instance.client.storage
          .from('commission_proofs')
          .upload(fileName, _proofImage!, fileOptions: const FileOptions(upsert: true));
      final downloadUrl = Supabase.instance.client.storage
          .from('commission_proofs')
          .getPublicUrl(fileName);

      final newPaymentRef = FirebaseDatabase.instance.ref().child('commission_payments').child(widget.uid).push();
      await newPaymentRef.set({
        'amount': widget.amount,
        'proofUrl': downloadUrl,
        'status': 'pending_verification',
        'timestamp': ServerValue.timestamp,
      });

      if (mounted) {
         Navigator.pop(context);
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفع الإثبات. يرجى الانتظار حتى تتم مراجعته وتأكيده.')));
         widget.onPaymentSuccess();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
     return Container(
       padding: EdgeInsets.only(
         top: 24, left: 24, right: 24,
         bottom: MediaQuery.of(context).viewInsets.bottom + 24,
       ),
       decoration: const BoxDecoration(
         color: Colors.white,
         borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
       ),
       child: Column(
         mainAxisSize: MainAxisSize.min,
         crossAxisAlignment: CrossAxisAlignment.stretch,
         children: [
           const Text("دفع العمولة المستحقة", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF43C59E)), textAlign: TextAlign.center),
           const SizedBox(height: 20),
           Container(
             padding: const EdgeInsets.all(16),
             decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
             child: Column(
               children: [
                 const Text("معلومات التحويل للحسابات البريدية", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                 const SizedBox(height: 12),
                 const Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [Text("رقم الحساب (CCP):"), Text("0000 123456789", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))],
                 ),
                 const SizedBox(height: 8),
                 const Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [Text("الاسم:"), Text("Rahti App S.A.R.L", style: TextStyle(fontWeight: FontWeight.bold))],
                 ),
                 const SizedBox(height: 8),
                 Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [const Text("المبلغ المستحق للدفع:"), Text("${widget.amount.toStringAsFixed(0)} دج", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16))],
                 ),
               ],
             ),
           ),
           const SizedBox(height: 24),
           OutlinedButton.icon(
             onPressed: _pickImage,
             icon: const Icon(Icons.upload_file, color: Color(0xFF43C59E)),
             label: Text(_proofImage == null ? "رفع الإثبات (وصل أو صورة)" : "تم إدراج الصورة، انقر للتغيير", style: const TextStyle(color: Color(0xFF43C59E), fontWeight: FontWeight.bold)),
             style: OutlinedButton.styleFrom(
               padding: const EdgeInsets.symmetric(vertical: 16),
               side: BorderSide(color: _proofImage == null ? Colors.grey.shade300 : Colors.green, width: 2),
               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
             ),
           ),
           const SizedBox(height: 24),
           SizedBox(
             height: 56,
             child: ElevatedButton(
               onPressed: _isUploading ? null : _confirmPayment,
               style: ElevatedButton.styleFrom(
                 backgroundColor: const Color(0xFF43C59E),
                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
               ),
               child: _isUploading 
                 ? const CircularProgressIndicator(color: Colors.white)
                 : const Text("تأكيد الدفع", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
             ),
           ),
         ],
       ),
     );
  }
}
