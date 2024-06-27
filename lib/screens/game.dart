import 'package:flutter/material.dart';
//import 'package:flutter/services.dart'; // RawKeyboardListenerを使用する場合
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/html.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
//import 'package:flutter_svg/flutter_svg.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late WebSocketChannel channel;
  String message = "";
  List<List<String>> board = List.generate(3, (_) => List.generate(3, (_) => ''));
  String currentTurn = "";
  String refereeStatus = "normal";
  int biasDegree = 0;
  List<int> bribeCounts = [0, 0];
  List<Map<String, dynamic>> chatMessages = []; // メッセージと送信者IDを格納するリスト
  String opponentStatus = "offline"; // 対戦相手のオンライン状況
  TextEditingController _textController = TextEditingController();
  FocusNode _focusNode = FocusNode();
  int userId = 0; // ログイン中のユーザーIDを保持
  // final ScrollController _scrollController = ScrollController();
  String winnerNickName = ""; // 勝者のニックネームを保持
  int userWins = 0; // ユーザーの勝利数
  int opponentWins = 0; // 対戦相手の勝利数
  String roundStatus = ""; // ラウンド情報を保持

  @override
  void initState() {
    super.initState();
    _initializeSession();
  }

  Future<void> _initializeSession() async {
    final prefs = await SharedPreferences.getInstance();
    final jwtToken = prefs.getString('jwtToken') ?? '';
    userId = prefs.getInt('userId') ?? 0;
    String sessionId = prefs.getString('sessionId') ?? '';

    if (jwtToken.isNotEmpty) {
      _connectWebSocket(jwtToken, sessionId);
    } else {
      print("JWT token is missing");
    }
  }

  Future<void> _connectWebSocket(String jwtToken, String sessionId) async {
    try {
      final url = 'ws://localhost:8080/ws?token=$jwtToken&sessionID=$sessionId';
      if (kIsWeb) {
        channel = HtmlWebSocketChannel.connect(url);
      } else {
        channel = IOWebSocketChannel.connect(Uri.parse(url));
      }
  
      channel.stream.listen((data) {
        handleMessage(data);
      }, onError: (error) async {
        print("WebSocket connection error: $error");
      });
    } catch (e) {
      print("Failed to connect to WebSocket: $e");
    }
  }
  
  Future<void> saveSessionIdAndUserId(String sessionId, int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sessionId', sessionId);
    await prefs.setInt('userId', userId);
    setState(() {
      this.userId = userId; // 受信後すぐにuserIdを設定
    });
  }

  @override
  void dispose() {
    channel.sink.close();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void handleMessage(dynamic data) {
    try {
      // final decodedData = jsonDecode(utf8.decode(data as List<int>));
      final decodedData = jsonDecode(data);
      if (decodedData.containsKey('sessionID') && decodedData.containsKey('userID')) {
        saveSessionIdAndUserId(decodedData['sessionID'], decodedData['userID']);
        print('New session ID and User ID saved: ${decodedData['sessionID']}, ${decodedData['userID']}');
      } else {
        List<Map<String, dynamic>> players = [];  // プレーヤーリストを定義
        switch (decodedData['type']) {
          case 'gameState':
            setState(() {
              board = (decodedData['board'] as List<dynamic>)
                .map((row) => (row as List<dynamic>).map((cell) => cell as String).toList())
                .toList();
              //board = List<List<String>>.from(decodedData['board']);
              currentTurn = decodedData['currentPlayer'] ?? "Unknown";
              refereeStatus = decodedData['refereeStatus'];
              roundStatus = decodedData['status'];
              biasDegree = decodedData['biasDegree'] ?? 0;
              bribeCounts = (decodedData['bribeCounts'] as List<dynamic>)
                .map((count) => count ?? 0) // null を 0 に置き換える
                .cast<int>()
                .toList();
              
              if (roundStatus == "finished") {
                clearSessionId();
                showGameFinishedDialog();
              }
            });
            break;
          case 'chatMessage':
            setState(() {
              chatMessages.insert(0, {
                "message": decodedData['message'],
                "from": decodedData['from']
              });
              if (chatMessages.length > 50) {
                chatMessages.removeLast(); // 最新の50件のみ表示
              }
            });
            break;
          case 'onlineStatus':
            setState(() {
              opponentStatus = decodedData['isOnline'] ? "online" : "offline";
            });
            break;
          case 'gameResults':
            setState(() {
              board = (decodedData['board'] as List<dynamic>)
                .map((row) => (row as List<dynamic>).map((cell) => cell as String).toList())
                .toList();
              currentTurn = decodedData['currentPlayer'] ?? "Unknown";
              refereeStatus = decodedData['refereeStatus'];
              biasDegree = decodedData['biasDegree'] ?? 0;
              roundStatus = decodedData['status'];
              bribeCounts = (decodedData['bribeCounts'] as List<dynamic>)
                .map((count) => count ?? 0)
                .cast<int>()
                .toList();
              players = (decodedData['playersInfo'] as List<dynamic>)
                .map((player) => {
                  'id': player['id'],
                  'nickName': player['nickName']
                })
                .toList();
              // 勝利数を計算
              userWins = 0;
              opponentWins = 0;

              final winners = decodedData['winners'] as List<dynamic>;
              for (var winnerId in winners) {
                if (winnerId == userId) {
                  userWins++;
                } else if (winnerId != 0) {
                  opponentWins++;
                }
              }

              // 勝者のニックネームを取得
              if (winners.isNotEmpty && winners.last != 0) {
                final winnerId = winners.last;
                final winnerInfo = (decodedData['playersInfo'] as List<dynamic>)
                  .firstWhere((player) => player['id'] == winnerId);
                winnerNickName = winnerInfo['nickName'] ?? "Unknown";
              } else {
                winnerNickName = "Draw";
              }
            });

            if (roundStatus == "finished") {
              clearSessionId();
              showGameFinishedDialog();
            }

            showGameResultDialog(roundStatus, players);
            break;
          default:
            print("Unknown message type: ${decodedData['type']}");
        }
      }
    } catch (e, stackTrace) {
      print('Error handling message: $e');
      print('Stack trace: $stackTrace');
    }
  }

  void sendMessage(String message) {
    try {
      // final encodedMessage = utf8.encode(jsonEncode({"type": "chatMessage", "message": message}));
      print('Sending message: $message');
      channel.sink.add(message);
      _textController.clear();
    } catch (e, stackTrace) {
      print('Error sending message: $e');
      print('Stack trace: $stackTrace');
    }
  }

  void markCell(int x, int y) {
    final msg = jsonEncode({
      "type": "action",
      "actionType": "markCell",
      "x": x,
      "y": y,
    });
    sendMessage(msg);
  }

  void bribeReferee() {
    final msg = jsonEncode({
      "type": "action",
      "actionType": "bribe",
    });
    sendMessage(msg);
  }

  void accuseReferee() {
    final msg = jsonEncode({
      "type": "action",
      "actionType": "accuse",
    });
    sendMessage(msg);
  }

  void handleRetry(bool wantRetry) {
    final msg = jsonEncode({
      "type": "action",
      "actionType": "retry",
      "wantRetry": wantRetry,
    });
    sendMessage(msg);
  }

  void showGameResultDialog(String status, List<Map<String, dynamic>> players) {
    // ユーザーIDに基づいて賄賂回数を設定
  int userBribeCount = 0;
  int opponentBribeCount = 0;
  if (players[0]['id'] == userId) {
    userBribeCount = bribeCounts[0];
    opponentBribeCount = bribeCounts[1];
  } else if (players[1]['id'] == userId) {
    userBribeCount = bribeCounts[1];
    opponentBribeCount = bribeCounts[0];
  }
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Column(
            children: [
              Text(
                roundStatus == "round1_finished"
                    ? "Round 1 Finished!"
                    : roundStatus == "round2_finished"
                        ? "Round 2 Finished!"
                        : "Thank You for Playing!",
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: "You ",
                      style: TextStyle(fontSize: 16), // Smaller text for "You"
                    ),
                    TextSpan(
                      text: "$userWins - $opponentWins",
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), // Larger, bold text for the score
                    ),
                    TextSpan(
                      text: " Rival",
                      style: TextStyle(fontSize: 16), // Smaller text for "Rival"
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                winnerNickName == "Draw"
                    ? "It's a draw!"
                    : "$winnerNickName wins!",
                style: TextStyle(fontSize: 24),
              ),
              SizedBox(height: 16),
              Text("Bribe Counts:"),
              Text("You: $userBribeCount"),
              Text("Rival: $opponentBribeCount"),
              // Text("You: ${bribeCounts[0]}"),
              // Text("Rival: ${bribeCounts[1]}"),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: Text("Close"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );

    // Add the retry message to chat
    setState(() {
      if (status == "round1_finished" || status == "round2_finished") {
        chatMessages.insert(0, {
          "message": "Play Next Round?",
          "from": 0, // 0 indicates system message
          "type": "system"
        });
      } else if (status == "finished") {
        chatMessages.insert(0, {
          "message": "This is the End of the Match!",
          "from": 0,
          "type": "system"
        });
      }
    });
  }

  Future<void> clearSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sessionId');
  }


  void showGameFinishedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Game Finished!"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Thank You for Playing!"),
              SizedBox(height: 8),
              Text("(Reload to Back Home)"),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: Text("Close"),
              onPressed: () {
                Navigator.of(context).pop();
                // Navigator.pushAndRemoveUntil(
                // context,
                // MaterialPageRoute(builder: (context) => HomeScreen()),
                // (Route<dynamic> route) => false,
                // );
              },
            ),
          ],
        );
      },
    );
  }

  void _clearJwtAndSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwtToken');
    await prefs.remove('sessionId');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('JWT and Session ID cleared'),
    ));
    Navigator.pushReplacementNamed(context, '/');
  }

  void _showResetConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Reset App?'),
          content: Text('If you reset this App, your invitation URL and accepted request will be disposed. Are you sure?'),
          actions: [
            TextButton(
              child: Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Reset'),
              onPressed: () {
                Navigator.of(context).pop();
                _clearJwtAndSessionId();
              },
            ),
          ],
        );
      },
    );
  }

  String _getRefereeImage(String status) {
    switch (status) {
      case "normal":
        return "referee_normal.png";
      case "angry":
        return "referee_angry.png";
      case "sad":
        return "referee_sad.png";
      default:
        return "referee_normal.png";
    }
  }

  @override
  Widget build(BuildContext context) {
  return Scaffold(
    extendBodyBehindAppBar: true, // AppBarの背後に背景を拡張
    appBar: AppBar(
      title: Text("Game Screen"),
      backgroundColor: Colors.transparent, // AppBarを透明に設定
      elevation: 0, // AppBarの影を削除
      actions: [
        IconButton(
          icon: Icon(Icons.warning),
          onPressed: _showResetConfirmationDialog,
        ),
      ],
    ),
    backgroundColor: Colors.transparent, // Scaffoldの背景色を透明に設定
    body: Stack(
      children: [
        // 背景画像を追加
        Positioned.fill(
          child: Image.asset(
            _getRefereeImage(refereeStatus),
            fit: BoxFit.cover,
          ),
        ),
        SafeArea( // SafeAreaで上部のマージンを避ける
          child: Column(
            children: <Widget>[
              Container(
                height: 80, // 最上段の高さを固定
                padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    ElevatedButton(
                      onPressed: bribeReferee,
                      child: Text("Bribe"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: Size(270, 70), // 吹き出しのサイズを設定
                              painter: SpeechBubblePainter(color: Colors.white.withOpacity(1.0)),
                            ),
                            Container(
                              width: 200.0, // 固定幅を設定
                              padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0), // パディングを追加
                              child: Column(
                                children: [
                                  Text(
                                    "Current Turn is...",
                                    style: TextStyle(
                                      fontSize: 12.0, // やや小さいフォントサイズ
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    currentTurn,
                                    style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: 30.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: accuseReferee,
                      child: Text("Accuse"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8), //デフォルトは20
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1, // 正方形のマス目を維持
                    child: Container(
                      constraints: BoxConstraints(maxWidth: 200, maxHeight: 200), // マス目の最大サイズを設定
                      child: GridView.builder(
                        padding: EdgeInsets.fromLTRB(4.0, 0, 4.0, 0.0),
                        //padding: EdgeInsets.all(0.0),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5, // 列数の固定
                        ),
                        itemBuilder: (context, index) {
                          final x = index ~/ 5; //ここも3か5
                          final y = index % 5;
                          return GestureDetector(
                            onTap: () {
                              markCell(x, y);
                            },
                            child: Container(
                              margin: EdgeInsets.all(2.0), // パネル間のスペースを設定
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.4), // 半透明の白色背景
                                borderRadius: BorderRadius.circular(4.0), // 角を丸くする
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2), // 影の色
                                    spreadRadius: 1, // 影の広がり
                                    blurRadius: 5, // 影のぼかし
                                    offset: Offset(2, 2), // 影の位置
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Container(
                                  padding: EdgeInsets.all(12.0), // 必要に応じて内部のスペースを設定
                                  //margin: EdgeInsets.all(8.0), // 必要に応じて外部のスペースを設定
                                  child: board[x][y] == 'O'
                                      ? Image.asset(
                                          'assets/circle.png',
                                          fit: BoxFit.fill, // フィット方法を設定
                                        )
                                      : board[x][y] == 'X'
                                          ? Image.asset(
                                              'assets/cross.png',
                                              fit: BoxFit.fill, // フィット方法を設定
                                            )
                                          : Container(),
                                ),
                              ),
                              // child: Center(
                              //   child: board[x][y] == 'O'
                              //       ? SvgPicture.asset('assets/circle.svg')
                              //       : board[x][y] == 'X'
                              //           ? SvgPicture.asset('assets/cross.svg')
                              //           : Container(),
                              // ),
                            ),
                          );
                        },
                        itemCount: 25, // Themeによるマス目の総合数をここで指定（9か25）
                        shrinkWrap: true,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Container(
                height: 180, // チャットメッセージリストの高さを制限
                margin: const EdgeInsets.fromLTRB(4.0, 0, 4.0, 4.0),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.4), // 半透明の白背景
                  borderRadius: BorderRadius.circular(12.0), // 角を丸くする
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2), // 影の色
                      spreadRadius: 1, // 影の広がり
                      blurRadius: 5, // 影のぼかし
                      offset: Offset(2, 2), // 影の位置
                    ),
                  ],
                ),
                child: Stack(
                  children: <Widget>[
                    ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment(0.0, -0.6),
                          colors: [Colors.transparent, Colors.white.withOpacity(0.2), Colors.white.withOpacity(1.0)],
                          stops: [0.0, 0.2, 1.0],
                          // colors: [Colors.transparent, Colors.white.withOpacity(0.2)],
                          // stops: [0.0, 0.3],
                        ).createShader(bounds);
                      },
                      blendMode: BlendMode.dstIn,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 0),
                        child: Column(
                          children: <Widget>[
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.only(top: 40.0),
                                reverse: true,
                                itemCount: chatMessages.length,
                                itemBuilder: (context, index) {
                                  final messageData = chatMessages[index];
                                  final isMe = messageData["from"] == userId;
                                  final isSystem = messageData["type"] == "system";
                                  final isSystemChat = messageData["from"] == 0;
                                  return Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: isSystem 
                                          ? MainAxisAlignment.center 
                                          : isMe 
                                            ? MainAxisAlignment.end 
                                            : MainAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.max,
                                        children: [
                                          Flexible(
                                            child: Container(
                                              padding: EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
                                              margin: EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
                                              decoration: BoxDecoration(
                                                color: isSystem
                                                  ? Colors.yellow[100]
                                                  : isSystemChat
                                                    ? Colors.yellow[100]
                                                    : isMe
                                                      ? Colors.blue[100]
                                                      : Colors.grey[300],
                                                borderRadius: BorderRadius.circular(12.0),
                                              ),
                                              child: Text(
                                                messageData["message"],
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 16.0,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (isSystem && messageData["message"] == "Play Next Round?")
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            ElevatedButton(
                                              onPressed: () {
                                                handleRetry(true);
                                                showDialog(
                                                  context: context,
                                                  builder: (BuildContext context) {
                                                    return AlertDialog(
                                                      title: Text("Retry Request Sent!"),
                                                      content: Text("Waiting for your opponent's response."),
                                                      actions: <Widget>[
                                                        TextButton(
                                                          child: Text("OK"),
                                                          onPressed: () {
                                                            Navigator.of(context).pop();
                                                          },
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                );
                                              },
                                              child: Text("Play"),
                                            ),
                                            SizedBox(width: 8),
                                            ElevatedButton(
                                              onPressed: () {
                                                handleRetry(false);
                                              },
                                              child: Text("Quit"),
                                            ),
                                          ],
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.all(8.0), // 上下左右のマージンを設定
                                    decoration: BoxDecoration(
                                      color: Colors.white, // 背景色を白に設定
                                      borderRadius: BorderRadius.circular(24.0), // 角を丸くする
                                    ),
                                    child: Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: TextField(
                                            controller: _textController,
                                            decoration: InputDecoration(
                                              hintText: "Send a message",
                                              border: InputBorder.none, // デフォルトのボーダーを削除
                                              contentPadding: EdgeInsets.symmetric(horizontal: 16.0), // パディングを追加
                                            ),
                                            onSubmitted: (String input) {
                                              try {
                                                sendMessage(jsonEncode({"type": "chatMessage", "message": input}));
                                              } catch (e) {
                                                print('Error on message submit: $e');
                                              }
                                            },
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.send),
                                          onPressed: () {
                                            sendMessage(jsonEncode({"type": "chatMessage", "message": _textController.text}));
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2.0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: Colors.transparent, // 背景を透明に設定
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // "Opponent: "テキスト
                            Text(
                              "Opponent: ",
                              style: TextStyle(color: Colors.black),
                            ),
                            // opponentStatusテキストと背景
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                              margin: EdgeInsets.symmetric(vertical: 2.0),
                              decoration: BoxDecoration(
                                color: Colors.white, // 白の不透明背景
                                borderRadius: BorderRadius.circular(12.0), // 角を丸くする
                              ),
                              child: Text(
                                opponentStatus,
                                style: TextStyle(
                                  color: opponentStatus == "online" ? Colors.green : Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
}

class SpeechBubblePainter extends CustomPainter {
  final Color color;

  SpeechBubblePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    var path = Path()
      ..moveTo(0, size.height * 0.1)
      ..lineTo(0, size.height * 0.9)
      ..quadraticBezierTo(0, size.height, size.width * 0.1, size.height)
      ..lineTo(size.width * 0.9, size.height)
      ..quadraticBezierTo(size.width, size.height, size.width, size.height * 0.9)
      ..lineTo(size.width, size.height * 0.1)
      ..quadraticBezierTo(size.width, 0, size.width * 0.9, 0)
      ..lineTo(size.width * 0.1, 0)
      ..quadraticBezierTo(0, 0, 0, size.height * 0.1)
      ..close();

    // 吹き出しの尻尾を追加
    path.moveTo(size.width * 0.7, size.height);
    path.lineTo(size.width * 0.45, size.height + 10);
    path.lineTo(size.width * 0.55, size.height);

    // 影を描画
    canvas.drawShadow(path, Colors.black.withOpacity(0.5), 4.0, true);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}
