import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:background_sms/background_sms.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SmsSender(),
    );
  }
}

class SmsSender extends StatefulWidget {
  @override
  _SmsSenderState createState() => _SmsSenderState();
}

class _SmsSenderState extends State<SmsSender> {
  late List<Map<String, String>> _messages;
  late Timer _timer;
  int _counter = 0;
  int _remainingSeconds = 60;

  @override
  void initState() {
    super.initState();
    _messages = [];
    _fetchNumbers();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds -= 1;
        } else {
          _remainingSeconds = 60;
          _fetchNumbers();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _fetchNumbers() async {
    final response = await http
        .get(Uri.parse('${dotenv.env['API_BASE_URL']}/get_numbers.php'));
    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      final messages = jsonData['messages'] as List<dynamic>;
      setState(() {
        _messages = messages
            .map((message) => {
                  'id': message['id'].toString(),
                  'message_to': message['message_to'].toString(),
                  'message': message['message'].toString(),
                  'is_sent': message['is_sent'].toString(),
                })
            .toList();
      });
      _handleMessages(); // Trigger the sender after fetching numbers and messages
    } else {
      throw Exception('Failed to load phone numbers please check again');
    }
  }

  Future<void> _handleMessages() async {
    if (await _isPermissionGranted()) {
      int? simSlot = (await _supportCustomSim()) ? 2 : null;
      for (var message in _messages) {
        await _sendMessage(
          message['message_to']!,
          message['message']!,
          message['id']!,
          simSlot: simSlot,
        );
        setState(() {
          _counter++;
        });
      }
    } else {
      await _getPermission();
    }
  }

  Future<void> _sendMessage(
    String phoneNumber,
    String message,
    String messageID, {
    int? simSlot,
  }) async {
    var result = await BackgroundSms.sendMessage(
      phoneNumber: phoneNumber,
      message: message,
      simSlot: simSlot,
    );
    if (result == SmsStatus.sent) {
      print("Sent to $phoneNumber");
      await _markMessageAsSent(messageID);
    } else {
      print("Failed to send to $phoneNumber");
    }
  }

  Future<void> _markMessageAsSent(String id) async {
    final url =
        Uri.parse('${dotenv.env['API_BASE_URL']}/update_is_sent.php?id=$id');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        print('Message marked as sent for $id');
      } else {
        print(
            'Failed to mark message as sent for $id. Status code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error marking message as sent for $id: $e');
    }
  }

  Future<void> _getPermission() async => await [Permission.sms].request();

  Future<bool> _isPermissionGranted() async =>
      await Permission.sms.status.isGranted;

  Future<bool> _supportCustomSim() async {
    bool? isSupportCustomSim = await BackgroundSms.isSupportCustomSim;
    return isSupportCustomSim ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Sms'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Messages Sent: $_counter',
              style: TextStyle(fontSize: 24),
            ),
            SizedBox(height: 20),
            Text(
              'Next fetch in: $_remainingSeconds seconds',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 20),
            _messages.isEmpty
                ? CircularProgressIndicator()
                : Expanded(
                    child: ListView.builder(
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(_messages[index]['message_to']!),
                          subtitle: Text(_messages[index]['message']!),
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
