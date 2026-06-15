import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  final String query = '''
    [out:json];
    way["name"="MacArthur Highway"](14.6740, 120.9810, 14.6820, 120.9890);
    out geom;
  ''';
  
  final url = Uri.parse('https://overpass-api.de/api/interpreter');
  final response = await http.post(
    url, 
    headers: {
      'User-Agent': 'SafePathsApp/1.0 (contact: test@example.com)',
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: {
      'data': query
    }
  );
  
  print('Status code: ${response.statusCode}');
  if (response.statusCode != 200) {
    print('Body: ${response.body}');
  } else {
    print('Success: ${response.body.substring(0, 100)}');
  }
}
