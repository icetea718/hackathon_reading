import 'package:flutter/material.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: const [
          IconButton(
            onPressed: null,
            icon: Icon(Icons.add),
            tooltip: '导入',
          ),
        ],
      ),
      body: const Center(
        child: Text('还没有书，点右上角导入'),
      ),
    );
  }
}
