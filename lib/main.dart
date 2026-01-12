import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  await FirebaseAuth.instance.signInAnonymously();
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Neon Chat',
      theme: ThemeData.dark(),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController controller = TextEditingController();
  final FocusNode inputFocusNode = FocusNode();
  final CollectionReference messagesRef =
      FirebaseFirestore.instance.collection('messages');

  void sendMessage() {
    final text = controller.text.trim();
    if (text.isEmpty) return;

    messagesRef.add({
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'uid': FirebaseAuth.instance.currentUser!.uid,
    });

    controller.clear();
    inputFocusNode.requestFocus();
  }

  @override
  void dispose() {
    controller.dispose();
    inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Neon Chat'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: messagesRef
                  .orderBy('createdAt')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index];
                    final isMe = data['uid'] == myUid;

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 14),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.greenAccent.withOpacity(0.2)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          data['text'],
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Input
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.black,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: inputFocusNode,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => sendMessage(),
                    decoration: const InputDecoration(
                      hintText: 'Type message...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
