import 'dart:async';
import 'dart:convert';
import 'package:angel_framework/src/http/angel_http_exception.dart';
import 'package:collection/collection.dart';
import 'package:http/src/base_client.dart' as http;
import 'package:http/src/base_request.dart' as http;
import 'package:http/src/request.dart' as http;
import 'package:http/src/response.dart' as http;
import 'package:http/src/streamed_response.dart' as http;
import 'package:merge_map/merge_map.dart';
import 'angel_client.dart';
import 'auth_types.dart' as auth_types;

const Map<String, String> _readHeaders = const {'Accept': 'application/json'};
final Map<String, String> _writeHeaders = mergeMap([
  _readHeaders,
  const {'Content-Type': 'application/json'}
]);

_buildQuery(Map params) {
  if (params == null || params.isEmpty) return "";

  List<String> query = [];

  params.forEach((k, v) {
    query.add('$k=$v');
  });

  return '?' + query.join('&');
}

AngelHttpException failure(http.Response response, {error, StackTrace stack}) {
  try {
    final json = JSON.decode(response.body);

    if (json is Map && json['isError'] == true) {
      return new AngelHttpException.fromMap(json);
    } else {
      return new AngelHttpException(error,
          message: 'Unhandled exception while connecting to Angel backend.',
          statusCode: response.statusCode,
          stackTrace: stack);
    }
  } catch (e, st) {
    return new AngelHttpException(error ?? e,
        message: 'Unhandled exception while connecting to Angel backend.',
        statusCode: response.statusCode,
        stackTrace: stack ?? st);
  }
}

abstract class BaseAngelClient extends Angel {
  @override
  String authToken;

  final http.BaseClient client;

  BaseAngelClient(this.client, String basePath) : super(basePath);

  @override
  Future<AngelAuthResult> authenticate(
      {String type: auth_types.LOCAL,
      credentials,
      String authEndpoint: '/auth',
      String reviveEndpoint: '/auth/token'}) async {
    if (type == null) {
      final url = '$basePath$reviveEndpoint';
      final response = await client.post(url,
          headers: mergeMap([
            _writeHeaders,
            {'Authorization': 'Bearer ${credentials['token']}'}
          ]));

      try {
        if (response.statusCode != 200) {
          throw failure(response);
        }

        final json = JSON.decode(response.body);

        if (json is! Map ||
            !json.containsKey('data') ||
            !json.containsKey('token')) {
          throw new AngelHttpException.NotAuthenticated(
              message:
                  "Auth endpoint '$url' did not return a proper response.");
        }

        return new AngelAuthResult.fromMap(json);
      } catch (e, st) {
        throw failure(response, error: e, stack: st);
      }
    } else {
      final url = '$basePath$authEndpoint/$type';
      http.Response response;

      if (credentials != null) {
        response = await client.post(url,
            body: JSON.encode(credentials), headers: _writeHeaders);
      } else {
        response = await client.post(url, headers: _writeHeaders);
      }

      try {
        if (response.statusCode != 200) {
          throw failure(response);
        }

        final json = JSON.decode(response.body);

        if (json is! Map ||
            !json.containsKey('data') ||
            !json.containsKey('token')) {
          throw new AngelHttpException.NotAuthenticated(
              message:
                  "Auth endpoint '$url' did not return a proper response.");
        }

        return new AngelAuthResult.fromMap(json);
      } catch (e, st) {
        throw failure(response, error: e, stack: st);
      }
    }
  }

  @override
  Service service(String path, {Type type}) {
    String uri = path.replaceAll(new RegExp(r"(^/)|(/+$)"), "");
    return new BaseAngelService(client, this, '$basePath/$uri');
  }
}

class BaseAngelService extends Service {
  @override
  final Angel app;
  final String basePath;
  final http.BaseClient client;

  BaseAngelService(this.client, this.app, this.basePath);

  makeBody(x) {
    return JSON.encode(x);
  }

  /// Sends a non-streaming [Request] and returns a non-streaming [Response].
  Future<http.Response> sendUnstreamed(
      String method, url, Map<String, String> headers,
      [body, Encoding encoding]) async {
    if (url is String) url = Uri.parse(url);
    var request = new http.Request(method, url);

    if (headers != null) request.headers.addAll(headers);
    if (encoding != null) request.encoding = encoding;
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List) {
        request.bodyBytes = DelegatingList.typed(body);
      } else if (body is Map) {
        request.bodyFields = DelegatingMap.typed(body);
      } else {
        throw new ArgumentError('Invalid request body "$body".');
      }
    }

    return http.Response.fromStream(await client.send(request));
  }

  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (app.authToken != null && app.authToken.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer ${app.authToken}';
    }

    return client.send(request);
  }

  @override
  Future<List> index([Map params]) async {
    final response = await sendUnstreamed(
        'GET', '$basePath/${_buildQuery(params)}', _readHeaders);

    try {
      if (response.statusCode != 200) {
        throw failure(response);
      }

      final json = JSON.decode(response.body);

      if (json is! List) {
        throw failure(response);
      }

      return json;
    } catch (e, st) {
      throw failure(response, error: e, stack: st);
    }
  }

  @override
  Future read(id, [Map params]) async {
    final response = await sendUnstreamed(
        'GET', '$basePath/$id${_buildQuery(params)}', _readHeaders);

    try {
      if (response.statusCode != 200) {
        throw failure(response);
      }

      return JSON.decode(response.body);
    } catch (e, st) {
      throw failure(response, error: e, stack: st);
    }
  }

  @override
  Future create(data, [Map params]) async {
    final response = await sendUnstreamed(
        'POST', '$basePath/${_buildQuery(params)}', _writeHeaders, makeBody(data));

    try {
      if (response.statusCode != 200) {
        throw failure(response);
      }

      return JSON.decode(response.body);
    } catch (e, st) {
      throw failure(response, error: e, stack: st);
    }
  }

  @override
  Future modify(id, data, [Map params]) async {
    final response = await sendUnstreamed(
        'PATCH', '$basePath/$id${_buildQuery(params)}', _writeHeaders, makeBody(data));

    try {
      if (response.statusCode != 200) {
        throw failure(response);
      }

      return JSON.decode(response.body);
    } catch (e, st) {
      throw failure(response, error: e, stack: st);
    }
  }

  @override
  Future update(id, data, [Map params]) async {
    final response = await sendUnstreamed(
        'POST', '$basePath/$id${_buildQuery(params)}', _writeHeaders, makeBody(data));

    try {
      if (response.statusCode != 200) {
        throw failure(response);
      }

      return JSON.decode(response.body);
    } catch (e, st) {
      throw failure(response, error: e, stack: st);
    }
  }

  @override
  Future remove(id, [Map params]) async {
    final response = await sendUnstreamed(
        'DELETE', '$basePath/$id${_buildQuery(params)}', _readHeaders);

    try {
      if (response.statusCode != 200) {
        throw failure(response);
      }

      return JSON.decode(response.body);
    } catch (e, st) {
      throw failure(response, error: e, stack: st);
    }
  }
}