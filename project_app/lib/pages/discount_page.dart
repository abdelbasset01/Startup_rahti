import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/message_badge.dart';
import '../widgets/logout_confirmation_dialog.dart';
import '../widgets/global_app_bar_actions.dart';
import '../widgets/history_badge.dart';

class DiscountPage extends StatefulWidget {
  const DiscountPage({super.key});

  @override
  State<DiscountPage> createState() => _DiscountPageState();
}

class _DiscountPageState extends State<DiscountPage> {
  int _currentIndex = 4;

  final List<Map<String, dynamic>> _discounts = [
    {
      'code': 'WELCOME50',
      'title': 'عرض الرحلة الأولى',
      'desc': 'احصل على خصم 50% على رحلتك الأولى المؤكدة في جميع أنحاء الجزائر.',
      'discount': '50%',
      'color': Colors.blue,
      'expiry': 'لا تنتهي الصلاحية'
    },
    {
      'code': 'SUMMER24',
      'title': 'أجواء الصيف',
      'desc': 'استمتع بخصم 20% على جميع وجهات الساحل.',
      'discount': '20%',
      'color': Colors.orange,
      'expiry': 'صالح حتى 31 أغسطس'
    },
    {
      'code': 'STUDENT',
      'title': 'توفير الطلاب',
      'desc': 'خصم 15% للطلاب المعتمدين على الرحلات بين الولايات.',
      'discount': '15%',
      'color': Colors.green,
      'expiry': 'صالح طوال العام'
    },
     {
      'code': 'FREESHIP',
      'title': 'توصيل مجاني',
      'desc': 'أول توصيل طرد مجاني علينا!',
      'discount': '100%',
      'color': Colors.purple,
      'expiry': 'للاستخدام مرة واحدة فقط'
    },
  ];

  void _onBottomNavTapped(int index) {
    if (index == _currentIndex) return;
    
    setState(() {
      _currentIndex = index;
    });

    if (index == 0) {
      Navigator.pushReplacementNamed(context, '/home');
    } else if (index == 1) {
      Navigator.pushReplacementNamed(context, '/history');
    } else if (index == 2) {
      Navigator.pushReplacementNamed(context, '/messages');
    } else if (index == 3) {
      Navigator.pushReplacementNamed(context, '/delivery');
    } else if (index == 4) {
      // Already on Discount
    } else if (index == 5) {
      Navigator.pushNamed(context, '/quran');
    }
  }

  Future<void> _logout() async {
    final shouldLogout = await showLogoutConfirmationDialog(context);
    if (shouldLogout != true) return;

    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacementNamed(context, '/home');
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: const Color(0xFF43C59E),
        title: const Text('الخصومات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: const [
          GlobalAppBarActions()
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _discounts.length,
        itemBuilder: (context, index) {
          final offer = _discounts[index];
          return Container(
             margin: const EdgeInsets.only(bottom: 20),
             decoration: BoxDecoration(
               color: Colors.white,
               borderRadius: BorderRadius.circular(20),
               boxShadow: [
                 BoxShadow(
                   color: Colors.black.withValues(alpha: 0.05),
                   blurRadius: 15,
                   offset: const Offset(0, 5),
                 ),
               ],
             ),
             child: Column(
               children: [
                 // Header with Color
                 Container(
                   decoration: BoxDecoration(
                     color: (offer['color'] as Color).withValues(alpha: 0.1),
                     borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                   ),
                   padding: const EdgeInsets.all(16),
                   child: Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                       Row(
                         children: [
                           Icon(Icons.local_offer, color: offer['color'] as Color),
                           const SizedBox(width: 8),
                           Text(offer['code'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: offer['color'] as Color, letterSpacing: 1.2)),
                         ],
                       ),
                       Container(
                         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                         decoration: BoxDecoration(
                           color: Colors.white,
                           borderRadius: BorderRadius.circular(20),
                           border: Border.all(color: offer['color'] as Color),
                         ),
                         child: Text(offer['expiry'], style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: offer['color'] as Color)),
                       )
                     ],
                   ),
                 ),
                 // Content
                 Padding(
                   padding: const EdgeInsets.all(20),
                   child: Row(
                     children: [
                       Expanded(
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Text(offer['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                             const SizedBox(height: 8),
                             Text(offer['desc'], style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                           ],
                         ),
                       ),
                       const SizedBox(width: 16),
                       Container(
                         padding: const EdgeInsets.all(12),
                         decoration: BoxDecoration(
                           color: const Color(0xFF43C59E),
                           borderRadius: BorderRadius.circular(12),
                         ),
                         child: Column(
                           children: [
                             Text(offer['discount'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                             const Text("خصم", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                           ],
                         ),
                       ),
                     ],
                   ),
                 ),
                 const Divider(height: 1),
                 // Footer button
                 Padding(
                   padding: const EdgeInsets.all(12),
                   child: SizedBox(
                     width: double.infinity,
                     child: TextButton.icon(
                       onPressed: () {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم نسخ الرمز ${offer['code']} إلى الحافظة!"), backgroundColor: const Color(0xFF43C59E)));
                       },
                       icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
                       label: const Text("نسخ الرمز", style: TextStyle(color: Colors.grey)),
                     ),
                   ),
                 )
               ],
             ),
          );
        },
      ),
      bottomNavigationBar: Directionality(
        textDirection: TextDirection.ltr,
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF43C59E),
          unselectedItemColor: Colors.grey,
          onTap: _onBottomNavTapped,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
            BottomNavigationBarItem(icon: HistoryBadge(child: Icon(Icons.history)), label: 'السجل'),
            BottomNavigationBarItem(icon: MessageBadge(child: Icon(Icons.message)), label: 'الرسائل'),
            BottomNavigationBarItem(icon: Icon(Icons.local_shipping), label: 'توصيل'),
            BottomNavigationBarItem(icon: Icon(Icons.discount), label: 'خصومات'),
            BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'اقرأ'),
          ],
        ),
      ),
      ),
    );
  }
}
