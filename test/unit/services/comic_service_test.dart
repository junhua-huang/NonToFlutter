import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:facebook_clone/models/comic_event.dart';
import 'package:facebook_clone/services/comic_service.dart';
import '../../helpers/test_helpers.dart';

/// 列表型成功的便捷包装
void mockSuccessList(List<Map<String, dynamic>> data) {
  setupMockDio(statusCode: 200, body: jsonEncode(data));
}

void main() {
  late ComicService comicService;

  setUp(() {
    comicService = ComicService();
  });

  tearDown(() {
    tearDownMockDio();
  });

  group('comic_service - getCities', () {
    test('getCities 列表解析', () async {
      mockSuccessList([
        {'id': 1, 'name': '南宁', 'province': '广西'},
        {'id': 2, 'name': '柳州', 'province': '广西'},
      ]);
      final resp = await comicService.getCities();
      expectSuccess(resp);
      expect(resp.data, isA<List<ComicCity>>());
      final list = resp.data as List<ComicCity>;
      expect(list.length, 2);
      expect(list[0].name, '南宁');
    });
  });

  group('comic_service - getTags', () {
    test('getTags 列表解析', () async {
      mockSuccessList([
        {'id': 1, 'name': '同人志', 'tagType': 'type'},
      ]);
      final resp = await comicService.getTags();
      expectSuccess(resp);
      expect(resp.data, isA<List<ComicTag>>());
    });
  });

  group('comic_service - getEvents', () {
    test('getEvents 分页参数正确', () async {
      mockSuccess({
        'records': [], 'total': 0, 'page': 1, 'size': 10, 'pages': 0,
      });
      final resp = await comicService.getEvents(page: 1, size: 10);
      expectSuccess(resp);
    });

    test('getEvents 带 city 参数', () async {
      mockSuccess({
        'records': [], 'total': 0, 'page': 1, 'size': 10, 'pages': 0,
      });
      final resp = await comicService.getEvents(city: '南宁');
      expectSuccess(resp);
    });
  });

  group('comic_service - getEventDetail', () {
    test('getEventDetail 解析完整', () async {
      mockSuccess({
        'id': 1, 'name': 'CICF', 'cityName': '广州', 'cityId': 1,
        'venue': '琶洲', 'status': 1, 'statusText': '即将开始',
        'tags': ['动漫'], 'coverImage': 'https://img.jpg',
        'followCount': 10, 'isFollowed': false, 'isOwner': false,
        'images': [{'id': 1, 'imageUrl': 'https://img.jpg', 'isCover': true}],
      });
      final resp = await comicService.getEventDetail(1);
      expectSuccess(resp);
      expect(resp.data, isA<ComicEvent>());
      final event = resp.data as ComicEvent;
      expect(event.name, 'CICF');
      expect(event.images.length, 1);
    });

    test('getEventDetail 带 userId 参数', () async {
      mockSuccess({
        'id': 1, 'name': 'Test', 'cityName': '', 'cityId': 0,
        'status': 0, 'statusText': '', 'tags': [],
        'followCount': 0, 'isFollowed': false, 'isOwner': false,
        'images': [],
      });
      final resp = await comicService.getEventDetail(1, userId: 5);
      expectSuccess(resp);
    });
  });

  group('comic_service - toggleFollow', () {
    test('toggleFollow 调用正确', () async {
      mockSuccess({'is_followed': true, 'follow_count': 11});
      final resp = await comicService.toggleFollow(1);
      expectSuccess(resp);
      final data = resp.data as Map<String, dynamic>;
      expect(data['is_followed'], true);
    });
  });

  group('comic_service - getMyEvents', () {
    test('getMyEvents 分页', () async {
      mockSuccess({'records': [], 'total': 0, 'page': 1, 'size': 10, 'pages': 0});
      final resp = await comicService.getMyEvents(page: 1);
      expectSuccess(resp);
    });
  });

  group('comic_service - getMyFollowed', () {
    test('getMyFollowed 分页', () async {
      mockSuccess({'records': [], 'total': 0, 'page': 1, 'size': 10, 'pages': 0});
      final resp = await comicService.getMyFollowed(page: 2);
      expectSuccess(resp);
    });
  });

  group('comic_service - submitEvent', () {
    test('submitEvent 请求体正确', () async {
      mockSuccess({'id': 99, 'message': 'created'});
      final body = {
        'name': 'Test Event', 'cityId': 1, 'venue': 'Hall 1',
        'imageUrls': ['https://img.jpg'],
      };
      final resp = await comicService.submitEvent(body);
      expectSuccess(resp);
      final data = resp.data as Map<String, dynamic>;
      expect(data['id'], 99);
    });
  });

  group('comic_service - updateEventData', () {
    test('updateEventData 请求体正确', () async {
      mockSuccess({'message': 'updated'});
      final body = {'name': 'Updated', 'venue': 'New Hall'};
      final resp = await comicService.updateEventData(1, body);
      expectSuccess(resp);
    });
  });
}
