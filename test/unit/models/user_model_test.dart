import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:facebook_clone/models/user.dart';

void main() {
  group('User.fromJson', () {
    test('完整字段解析', () {
      const json = '''
      {
        "id": 1,
        "username": "testuser",
        "email": "test@example.com",
        "display_name": "Test User",
        "bio": "Hello world",
        "avatar_url": "https://example.com/avatar.jpg",
        "cover_photo_url": "https://example.com/cover.jpg",
        "created_at": "2024-01-15T10:30:00.000Z"
      }
      ''';
      final user = User.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(user.id, 1);
      expect(user.username, 'testuser');
      expect(user.email, 'test@example.com');
      expect(user.displayName, 'Test User');
      expect(user.bio, 'Hello world');
      expect(user.avatarUrl, 'https://example.com/avatar.jpg');
      expect(user.coverPhotoUrl, 'https://example.com/cover.jpg');
      expect(user.createdAt, DateTime.utc(2024, 1, 15, 10, 30));
    });

    test('缺失字段降级为空字符串或 null', () {
      const json = '{"id": 2, "username": "min", "email": "min@e.com"}';
      final user = User.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(user.id, 2);
      expect(user.username, 'min');
      expect(user.email, 'min@e.com');
      expect(user.displayName, isNull);
      expect(user.bio, isNull);
      expect(user.avatarUrl, isNull);
      expect(user.coverPhotoUrl, isNull);
      expect(user.createdAt, isNull);
    });

    test('id 为字符串时自动转换', () {
      const json = '{"id": "99", "username": "s", "email": "e@e.com"}';
      final user = User.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(user.id, 99);
    });

    test('username 为空时返回空字符串', () {
      const json = '{"id": 1, "email": "e@e.com"}';
      final user = User.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(user.username, '');
    });
  });

  group('User.toJson', () {
    test('toJson 输出字段名使用 snake_case', () {
      final user = User(
        id: 1,
        username: 'u',
        email: 'e@e.com',
        displayName: 'DN',
        bio: 'b',
        avatarUrl: 'a.jpg',
        coverPhotoUrl: 'c.jpg',
      );
      final json = user.toJson();
      expect(json['id'], 1);
      expect(json['username'], 'u');
      expect(json['email'], 'e@e.com');
      expect(json['display_name'], 'DN');
      expect(json['bio'], 'b');
      expect(json['avatar_url'], 'a.jpg');
      expect(json['cover_photo_url'], 'c.jpg');
    });
  });

  group('User.displayName', () {
    test('displayName 映射自 display_name', () {
      const json = '{"id": 1, "username": "u", "email": "e@e.com", "display_name": "My Name"}';
      final user = User.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(user.displayName, 'My Name');
    });
  });

  group('User.initials', () {
    test('返回用户名首字母大写', () {
      final user = User(id: 1, username: 'john', email: 'j@e.com');
      expect(user.initials, 'J');
    });

    test('用户名为空返回 ?', () {
      final user = User(id: 1, username: '', email: 'e@e.com');
      expect(user.initials, '?');
    });
  });

  group('User.copyWith', () {
    test('部分字段更新保留原有值', () {
      final original = User(
        id: 1, username: 'john', email: 'j@e.com',
        displayName: 'John', bio: 'old bio',
        avatarUrl: 'old.jpg', coverPhotoUrl: 'old_cover.jpg',
      );
      final updated = original.copyWith(displayName: 'Johnny');
      expect(updated.id, 1);
      expect(updated.username, 'john');
      expect(updated.email, 'j@e.com');
      expect(updated.displayName, 'Johnny');
      expect(updated.bio, 'old bio');
      expect(updated.avatarUrl, 'old.jpg');
      expect(updated.coverPhotoUrl, 'old_cover.jpg');
    });
  });
}
