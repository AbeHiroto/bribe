import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class InviteScreen extends StatefulWidget {
  final String uniqueToken;

  const InviteScreen({Key? key, required this.uniqueToken}) : super(key: key);

  @override
  _InviteScreenState createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final TextEditingController _nicknameController = TextEditingController();
  bool _isLoading = false;
  String roomCreator = '';
  String roomTheme = '';

  @override
  void initState() {
    super.initState();
    fetchRoomInfo();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> fetchRoomInfo() async {
    setState(() {
      _isLoading = true;
    });

    final response = await http.get(
      Uri.parse('http://localhost:8080/play/${widget.uniqueToken}'),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        roomCreator = data['roomCreator'];
        roomTheme = data['roomTheme'];
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('ルーム情報の取得に失敗しました。'),
      ));
    }
  }

  void submitChallenge(BuildContext context) async {
    if (_nicknameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('ニックネームを入力してください'),
      ));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final jwtToken = prefs.getString('jwtToken') ?? '';

    final response = await http.post(
      Uri.parse('http://localhost:8080/challenger/create/${widget.uniqueToken}'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({
        'nickname': _nicknameController.text,
        'subscriptionStatus': 'basic', // 課金ステータスが必要であれば設定
      }),
    );

    if (response.statusCode == 201) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('対戦申請が正常に送信されました。'),
      ));
      Navigator.pop(context); // 対戦申請後に前の画面に戻る
    } else {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('対戦申請に失敗しました。'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('対戦申請')),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('ルーム作成者: $roomCreator'),
                  Text('ルームテーマ: $roomTheme'),
                  SizedBox(height: 20),
                  TextField(
                    controller: _nicknameController,
                    decoration: InputDecoration(
                      labelText: 'あなたのニックネーム',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => submitChallenge(context),
                    child: Text('対戦を申請する'),
                  ),
                ],
              ),
            ),
    );
  }
}