import 'package:flutter/material.dart';
import 'package:running_historian/ui/screens/run_screen.dart';

class RunningHistorianApp extends StatelessWidget {
  const RunningHistorianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Running Historian',
      theme: ThemeData(useMaterial3: true),
      home:
          const RunScreen(), // 👈 const, потому что RunScreen — StatefulWidget
    );
  }
}
