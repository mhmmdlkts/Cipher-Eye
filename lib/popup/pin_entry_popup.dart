import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:flutter/material.dart';

class PinEntryPopup extends StatefulWidget {
  PinEntryPopup({Key? key}) : super(key: key);
  @override
  _PinEntryPopupState createState() => _PinEntryPopupState();
}

class _PinEntryPopupState extends State<PinEntryPopup> {
  String enteredPin = '';
  final int pinLength = 6;
  int tryRemains = 3;

  @override
  Widget build(BuildContext context) {
    double width = 400;
    return AlertDialog(
      content: Padding(
        padding: EdgeInsets.symmetric(vertical: 25, horizontal: 5),
        child: SizedBox(
          height: 300,
          width: width,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _buildCircles(),
              ),
              NumericKeyboard(width: width, onNumberSelected: (value) {
                if (value == -1) {
                  if (enteredPin.length > 0) {
                    setState(() {
                      enteredPin = enteredPin.substring(0, enteredPin.length - 1);
                    });
                  }
                } else {
                  if (enteredPin.length < pinLength) {
                    setState(() {
                      enteredPin = enteredPin + value.toString();
                    });
                  }
                }
                if (enteredPin.length == pinLength) {
                  checkPin();
                }
              }),
            ],
          ),
        ),
      ),
    );
  }

  checkPin() {
    SecureStorageService.checkPin(enteredPin).then((value) {
      if (value) {
        Navigator.of(context).pop(true);
      } else {
        clear();
        tryRemains--;
        if (tryRemains <= 0) {
          Navigator.of(context).pop(false);
        }
      }
    });
  }

  void clear() {
    setState(() {
      enteredPin = '';
    });
  }

  List<Widget> _buildCircles() {
    List<Widget> circles = [];
    for (int i = 0; i < pinLength; i++) {
      circles.add(
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: i < enteredPin.length ? Color(0xff3f826a) : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: Color(0xff3f826a)),
          ),
        ),
      );
    }
    return circles;
  }
}

class NumericKeyboard extends StatelessWidget {
  final double width;
  final Function(int) onNumberSelected;

  NumericKeyboard({required this.onNumberSelected, required this.width});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 10,
      runSpacing: 10,
      children: List.generate(12, (index) {
        if (index == 9) {
          return SizedBox(width: width / 4);
        } else if (index == 10) {
          return _buildNumberButton(0);
        } else if (index == 11) {
          return _buildNumberButton(-1);
        } else {
          return _buildNumberButton(index+1);
        }
      }),
    );
  }

  Widget _buildNumberButton(int number) {
    return SizedBox(
      width: width / 4,
      height: 50,
      child: OutlinedButton(
        onPressed: () => onNumberSelected(number.isNegative?-1:number),
        child: number.isNegative?Icon(Icons.backspace):Text(number.toString()),
      ),
    );
  }
}

