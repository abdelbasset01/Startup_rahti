import 'package:flutter/material.dart';

class Seat {
  bool isTaken;
  String gender;

  Seat({required this.isTaken, this.gender = ''});
}

class SeatSelectionPage extends StatefulWidget {
  const SeatSelectionPage({super.key});

  @override
  State<SeatSelectionPage> createState() => _SeatSelectionPageState();
}

class _SeatSelectionPageState extends State<SeatSelectionPage> {
  String selectedGender = 'male';

  // Create 20 seats
  List<Seat> seats = List.generate(
    20,
    (index) => Seat(isTaken: index == 3 || index == 7), // example taken seats
  );

  int? selectedSeatIndex;

  Color getSeatColor(Seat seat, bool isSelected) {
    if (seat.isTaken) return Colors.grey.shade400;

    if (isSelected) {
      if (seat.gender == 'male') return Colors.blue;
      if (seat.gender == 'female') return Colors.pink;
      if (seat.gender == 'kids') return Colors.orange;
    }

    return Colors.grey.shade200;
  }

  IconData? getSeatIcon(Seat seat) {
    if (seat.gender == 'male') return Icons.male;
    if (seat.gender == 'female') return Icons.female;
    if (seat.gender == 'kids') return Icons.child_care;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Select Your Seat")),
      body: Column(
        children: [
          const SizedBox(height: 10),

          /// GENDER SELECTION
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              genderButton('kids', Colors.orange),
              genderButton('male', Colors.blue),
              genderButton('female', Colors.pink),
            ],
          ),

          const SizedBox(height: 20),

          /// SEAT GRID
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: seats.length,
              itemBuilder: (context, index) {
                final seat = seats[index];
                final isSelected = selectedSeatIndex == index;

                return GestureDetector(
                  onTap: seat.isTaken
                      ? null
                      : () {
                          setState(() {
                            selectedSeatIndex = index;
                            seat.gender = selectedGender;
                          });
                        },
                  child: Container(
                    decoration: BoxDecoration(
                      color: getSeatColor(seat, isSelected),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Center(
                      child: seat.isTaken
                          ? const Icon(Icons.block, color: Colors.black54)
                          : Icon(
                              getSeatIcon(seat),
                              color: Colors.white,
                            ),
                    ),
                  ),
                );
              },
            ),
          ),

          /// CONFIRM BUTTON
          Padding(
            padding: const EdgeInsets.all(20),
            child: ElevatedButton(
              onPressed: selectedSeatIndex == null
                  ? null
                  : () {
                      setState(() {
                        seats[selectedSeatIndex!].isTaken = true;
                      });

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Seat confirmed successfully!"),
                        ),
                      );
                    },
              child: const Text("Confirm Seat"),
            ),
          ),
        ],
      ),
    );
  }

  Widget genderButton(String gender, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              selectedGender == gender ? color : Colors.grey,
        ),
        onPressed: () {
          setState(() {
            selectedGender = gender;
          });
        },
        child: Text(gender.toUpperCase()),
      ),
    );
  }
}
