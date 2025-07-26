import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ExternalTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> params) execute;

  ExternalTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });
}

class ExternalToolsService extends ChangeNotifier {
  static final ExternalToolsService _instance = ExternalToolsService._internal();
  factory ExternalToolsService() => _instance;
  ExternalToolsService._internal() {
    _initializeTools();
  }

  final Map<String, ExternalTool> _tools = {};
  bool _isExecuting = false;
  List<String> _currentlyExecutingTools = [];
  String _lastToolUsed = '';
  Map<String, dynamic> _lastResult = {};
  
  // Callback for model switching
  void Function(String modelName)? _modelSwitchCallback;

  bool get isExecuting => _isExecuting;
  List<String> get currentlyExecutingTools => List.unmodifiable(_currentlyExecutingTools);
  String get lastToolUsed => _lastToolUsed;
  Map<String, dynamic> get lastResult => Map.unmodifiable(_lastResult);

  void _initializeTools() {
    // Screenshot tool - takes screenshots of webpages using WordPress preview
    _tools['screenshot'] = ExternalTool(
      name: 'screenshot',
      description: 'Takes a screenshot of any webpage using WordPress preview service. Can capture single or multiple URLs. The AI can use this tool to visually understand websites, capture content, or help users with visual tasks.',
      parameters: {
        'url': {'type': 'string', 'description': 'The URL to take screenshot of', 'required': false},
        'urls': {'type': 'array', 'description': 'Multiple URLs to take screenshots of', 'required': false},
        'width': {'type': 'integer', 'description': 'Screenshot width in pixels (default: 1200)', 'default': 1200},
        'height': {'type': 'integer', 'description': 'Screenshot height in pixels (default: 800)', 'default': 800},
      },
      execute: _executeScreenshot,
    );

    // AI Models fetcher - dynamically fetches available AI models
    _tools['fetch_ai_models'] = ExternalTool(
      name: 'fetch_ai_models',
      description: 'Fetches available AI models from the API. The AI can use this to switch models if one is not responding or if the user is not satisfied with the current model.',
      parameters: {
        'refresh': {'type': 'boolean', 'description': 'Force refresh the models list (default: false)', 'default': false},
        'filter': {'type': 'string', 'description': 'Filter models by name pattern (optional)', 'default': ''},
      },
      execute: _fetchAIModels,
    );

    // Model switcher - switches the current AI model
    _tools['switch_ai_model'] = ExternalTool(
      name: 'switch_ai_model',
      description: 'Switches to a different AI model. The AI can use this when a model is not responding well or when the user requests a different model.',
      parameters: {
        'model_name': {'type': 'string', 'description': 'Name of the model to switch to', 'required': true},
        'reason': {'type': 'string', 'description': 'Reason for switching models (optional)', 'default': 'User request'},
      },
      execute: _switchAIModel,
    );

    // Image generation tool - generates images using AI models
    _tools['generate_image'] = ExternalTool(
      name: 'generate_image',
      description: 'Generates images using AI models like Flux and Turbo. The AI can use this tool when users request image creation, art generation, or visual content.',
      parameters: {
        'prompt': {'type': 'string', 'description': 'The prompt for image generation', 'required': true},
        'model': {'type': 'string', 'description': 'Image model to use (flux, turbo)', 'default': 'flux'},
        'width': {'type': 'integer', 'description': 'Image width in pixels (default: 1024)', 'default': 1024},
        'height': {'type': 'integer', 'description': 'Image height in pixels (default: 1024)', 'default': 1024},
        'enhance': {'type': 'boolean', 'description': 'Enhance the prompt (default: false)', 'default': false},
      },
      execute: _generateImage,
    );

    // Fetch image models - gets available image generation models
    _tools['fetch_image_models'] = ExternalTool(
      name: 'fetch_image_models',
      description: 'Fetches available image generation models from the API. The AI can use this to show users what image models are available.',
      parameters: {
        'refresh': {'type': 'boolean', 'description': 'Force refresh the models list (default: false)', 'default': false},
      },
      execute: _fetchImageModels,
    );

    // Web search tool - searches the web using DuckDuckGo and Wikipedia
    _tools['web_search'] = ExternalTool(
      name: 'web_search',
      description: 'Performs real-time web search using DuckDuckGo and Wikipedia. The AI can use this tool to find current information, news, or any web content.',
      parameters: {
        'query': {'type': 'string', 'description': 'The search query', 'required': true},
        'source': {'type': 'string', 'description': 'Search source (duckduckgo, wikipedia, both)', 'default': 'both'},
        'limit': {'type': 'integer', 'description': 'Maximum number of results (default: 5)', 'default': 5},
      },
      execute: _webSearch,
    );

    // Screenshot vision tool - analyzes screenshots using vision AI
    _tools['screenshot_vision'] = ExternalTool(
      name: 'screenshot_vision',
      description: 'Analyzes screenshots using vision AI models. The AI can use this tool to understand what is visible in screenshots it has generated.',
      parameters: {
        'image_url': {'type': 'string', 'description': 'URL of the screenshot to analyze', 'required': true},
        'question': {'type': 'string', 'description': 'Optional question about the image', 'default': 'What do you see in this image?'},
        'model': {'type': 'string', 'description': 'Vision model to use', 'default': 'claude-4-sonnet'},
      },
      execute: _screenshotVision,
    );
  }

  /// Execute a single tool by name with given parameters
  Future<Map<String, dynamic>> executeTool(String toolName, Map<String, dynamic> params) async {
    if (!_tools.containsKey(toolName)) {
      return {
        'success': false,
        'error': 'Tool "$toolName" not found',
        'available_tools': _tools.keys.toList(),
      };
    }

    _isExecuting = true;
    _currentlyExecutingTools.add(toolName);
    _lastToolUsed = toolName;
    notifyListeners();

    try {
      final result = await _tools[toolName]!.execute(params);
      _lastResult = result;
      _currentlyExecutingTools.remove(toolName);
      if (_currentlyExecutingTools.isEmpty) {
        _isExecuting = false;
      }
      notifyListeners();
      return result;
    } catch (e) {
      _currentlyExecutingTools.remove(toolName);
      if (_currentlyExecutingTools.isEmpty) {
        _isExecuting = false;
      }
      _lastResult = {
        'success': false,
        'error': e.toString(),
        'tool': toolName,
      };
      notifyListeners();
      return _lastResult;
    }
  }

  /// Execute multiple tools in parallel
  Future<Map<String, Map<String, dynamic>>> executeToolsParallel(List<Map<String, dynamic>> toolCalls) async {
    final results = <String, Map<String, dynamic>>{};
    
    _isExecuting = true;
    _currentlyExecutingTools.clear();
    for (final call in toolCalls) {
      _currentlyExecutingTools.add(call['tool_name'] as String);
    }
    notifyListeners();

    try {
      final futures = toolCalls.map((call) async {
        final toolName = call['tool_name'] as String;
        final params = call['parameters'] as Map<String, dynamic>? ?? {};
        
        if (!_tools.containsKey(toolName)) {
          return MapEntry(toolName, {
            'success': false,
            'error': 'Tool "$toolName" not found',
            'available_tools': _tools.keys.toList(),
          });
        }

        try {
          final result = await _tools[toolName]!.execute(params);
          return MapEntry(toolName, result);
        } catch (e) {
          return MapEntry(toolName, {
            'success': false,
            'error': e.toString(),
            'tool': toolName,
          });
        }
      });

      final parallelResults = await Future.wait(futures);
      for (final entry in parallelResults) {
        results[entry.key] = entry.value;
      }

      _isExecuting = false;
      _currentlyExecutingTools.clear();
      notifyListeners();
      
      return results;
    } catch (e) {
      _isExecuting = false;
      _currentlyExecutingTools.clear();
      _lastResult = {
        'success': false,
        'error': 'Parallel execution failed: $e',
        'tools': toolCalls.map((c) => c['tool_name']).toList(),
      };
      notifyListeners();
      return {'error': _lastResult};
    }
  }

  /// Get list of available tools
  List<ExternalTool> getAvailableTools() {
    return _tools.values.toList();
  }

  /// Get specific tool information
  ExternalTool? getTool(String name) {
    return _tools[name];
  }

  /// Check if AI can access screenshot functionality
  bool get hasScreenshotCapability => _tools.containsKey('screenshot');

  /// Check if AI can access model switching
  bool get hasModelSwitchingCapability => _tools.containsKey('fetch_ai_models') && _tools.containsKey('switch_ai_model');

  /// Check if AI can access image generation
  bool get hasImageGenerationCapability => _tools.containsKey('generate_image');

  /// Check if AI can access web search
  bool get hasWebSearchCapability => _tools.containsKey('web_search');

  /// Check if AI can access screenshot vision
  bool get hasScreenshotVisionCapability => _tools.containsKey('screenshot_vision');

  /// Set the model switch callback (called by main shell)
  void setModelSwitchCallback(void Function(String modelName) callback) {
    _modelSwitchCallback = callback;
  }

  // Tool implementations

  Future<Map<String, dynamic>> _executeScreenshot(Map<String, dynamic> params) async {
    final url = params['url'] as String? ?? '';
    final urls = params['urls'] as List<dynamic>? ?? [];
    final width = params['width'] as int? ?? 1200;
    final height = params['height'] as int? ?? 800;

    // Determine which URLs to process
    List<String> targetUrls = [];
    if (url.isNotEmpty) {
      targetUrls.add(url);
    }
    if (urls.isNotEmpty) {
      targetUrls.addAll(urls.map((u) => u.toString()));
    }

    if (targetUrls.isEmpty) {
      return {
        'success': false,
        'error': 'Either url or urls parameter is required',
      };
    }

    // Handle multiple URLs
    if (targetUrls.length > 1) {
      return await _executeMultipleScreenshots(targetUrls, width, height);
    }

    try {
      // Validate URL format
      Uri parsedUrl;
      final singleUrl = targetUrls.first;
      try {
        if (!singleUrl.startsWith('http://') && !singleUrl.startsWith('https://')) {
          parsedUrl = Uri.parse('https://$singleUrl');
        } else {
          parsedUrl = Uri.parse(singleUrl);
        }
      } catch (e) {
        return {
          'success': false,
          'error': 'Invalid URL format: $singleUrl',
        };
      }

      // Use WordPress.com mshots API for screenshots
      final screenshotUrl = 'https://s0.wp.com/mshots/v1/${Uri.encodeComponent(parsedUrl.toString())}?w=$width&h=$height';
      
      // Verify the screenshot service is accessible with a longer timeout
      try {
        final response = await http.head(Uri.parse(screenshotUrl)).timeout(Duration(seconds: 15));
        
        return {
          'success': true,
          'url': parsedUrl.toString(),
          'screenshot_url': screenshotUrl,
          'preview_url': screenshotUrl, // Direct WordPress preview
          'width': width,
          'height': height,
          'description': 'Screenshot captured successfully for ${parsedUrl.toString()}',
          'service': 'WordPress mshots API (direct preview)',
          'accessible': response.statusCode == 200,
          'tool_executed': true,
          'execution_time': DateTime.now().toIso8601String(),
        };
      } catch (e) {
        // Even if head request fails, the screenshot service might still work
        return {
          'success': true,
          'url': parsedUrl.toString(),
          'screenshot_url': screenshotUrl,
          'preview_url': screenshotUrl,
          'width': width,
          'height': height,
          'description': 'Screenshot service initiated for ${parsedUrl.toString()}',
          'service': 'WordPress mshots API (direct preview)',
          'note': 'Service response pending - image may take a moment to generate',
          'tool_executed': true,
          'execution_time': DateTime.now().toIso8601String(),
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to capture screenshot: $e',
        'url': targetUrls.first,
        'tool_executed': false,
      };
    }
  }

  Future<Map<String, dynamic>> _executeMultipleScreenshots(List<String> urls, int width, int height) async {
    List<Map<String, dynamic>> screenshots = [];
    List<String> errors = [];

    for (int i = 0; i < urls.length; i++) {
      final url = urls[i];
      try {
        // Validate URL format
        Uri parsedUrl;
        if (!url.startsWith('http://') && !url.startsWith('https://')) {
          parsedUrl = Uri.parse('https://$url');
        } else {
          parsedUrl = Uri.parse(url);
        }

        // Use WordPress.com mshots API for screenshots
        final screenshotUrl = 'https://s0.wp.com/mshots/v1/${Uri.encodeComponent(parsedUrl.toString())}?w=$width&h=$height';
        
        screenshots.add({
          'index': i + 1,
          'url': parsedUrl.toString(),
          'screenshot_url': screenshotUrl,
          'preview_url': screenshotUrl,
          'width': width,
          'height': height,
        });
      } catch (e) {
        errors.add('URL ${i + 1} ($url): $e');
      }
    }

    return {
      'success': screenshots.isNotEmpty,
      'screenshots': screenshots,
      'total_screenshots': screenshots.length,
      'errors': errors,
      'service': 'WordPress mshots API (direct preview)',
      'tool_executed': true,
      'execution_time': DateTime.now().toIso8601String(),
      'description': 'Multiple screenshots captured: ${screenshots.length} successful, ${errors.length} failed',
    };
  }

  Future<Map<String, dynamic>> _fetchAIModels(Map<String, dynamic> params) async {
    final refresh = params['refresh'] as bool? ?? false;
    final filter = params['filter'] as String? ?? '';

    try {
      final response = await http.get(
        Uri.parse('https://ahamai-api.officialprakashkrsingh.workers.dev/v1/models'),
        headers: {'Authorization': 'Bearer ahamaibyprakash25'},
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<String> models = (data['data'] as List).map<String>((item) => item['id']).toList();
        
        // Apply filter if provided
        if (filter.isNotEmpty) {
          models = models.where((model) => model.toLowerCase().contains(filter.toLowerCase())).toList();
        }

        return {
          'success': true,
          'models': models,
          'total_count': models.length,
          'filter_applied': filter,
          'refreshed': refresh,
          'tool_executed': true,
          'execution_time': DateTime.now().toIso8601String(),
          'api_status': 'Connected successfully',
        };
      } else {
        return {
          'success': false,
          'error': 'API returned status ${response.statusCode}: ${response.reasonPhrase}',
          'tool_executed': true,
          'api_status': 'Failed to connect',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to fetch AI models: $e',
        'tool_executed': true,
        'api_status': 'Connection error',
      };
    }
  }

  Future<Map<String, dynamic>> _switchAIModel(Map<String, dynamic> params) async {
    final modelName = params['model_name'] as String? ?? '';
    final reason = params['reason'] as String? ?? 'User request';

    if (modelName.isEmpty) {
      return {
        'success': false,
        'error': 'model_name parameter is required',
        'tool_executed': false,
      };
    }

    try {
      // First, verify the model exists by fetching the models list
      final modelsResult = await _fetchAIModels({'refresh': true});
      
      if (modelsResult['success'] == true) {
        final models = modelsResult['models'] as List<String>;
        
        if (models.contains(modelName)) {
          // Actually switch the model if callback is available
          if (_modelSwitchCallback != null) {
            _modelSwitchCallback!(modelName);
          }
          
          return {
            'success': true,
            'new_model': modelName,
            'reason': reason,
            'available_models': models,
            'tool_executed': true,
            'execution_time': DateTime.now().toIso8601String(),
            'action_completed': _modelSwitchCallback != null ? 'Model switched successfully' : 'UI should update the selected model to $modelName',
            'validation': 'Model exists and is available',
          };
        } else {
          return {
            'success': false,
            'error': 'Model "$modelName" not found in available models',
            'available_models': models,
            'suggestion': 'Try one of the available models listed above',
            'tool_executed': true,
          };
        }
      } else {
        return {
          'success': false,
          'error': 'Could not fetch models list to verify model exists',
          'reason': modelsResult['error'],
          'tool_executed': true,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to switch AI model: $e',
        'tool_executed': true,
      };
    }
  }

  Future<Map<String, dynamic>> _generateImage(Map<String, dynamic> params) async {
    final prompt = params['prompt'] as String? ?? '';
    final model = params['model'] as String? ?? 'flux';
    final width = params['width'] as int? ?? 1024;
    final height = params['height'] as int? ?? 1024;
    final enhance = params['enhance'] as bool? ?? false;

    if (prompt.isEmpty) {
      return {
        'success': false,
        'error': 'Prompt parameter is required',
      };
    }

    try {
      final response = await http.post(
        Uri.parse('https://ahamai-api.officialprakashkrsingh.workers.dev/v1/images/generations'),
        headers: {
          'Authorization': 'Bearer ahamaibyprakash25',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'prompt': prompt,
          'width': width,
          'height': height,
          'enhance': enhance,
        }),
      ).timeout(Duration(seconds: 60));

      if (response.statusCode == 200) {
        // The image is returned as binary data
        final imageBytes = response.bodyBytes;
        
        // Create a data URL for the image
        final base64Image = base64Encode(imageBytes);
        final dataUrl = 'data:image/jpeg;base64,$base64Image';

        return {
          'success': true,
          'prompt': prompt,
          'model': model,
          'width': width,
          'height': height,
          'enhance': enhance,
          'image_url': dataUrl,
          'image_size': imageBytes.length,
          'tool_executed': true,
          'execution_time': DateTime.now().toIso8601String(),
          'description': 'Image generated successfully using $model model',
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to generate image: HTTP ${response.statusCode}',
          'prompt': prompt,
          'model': model,
          'width': width,
          'height': height,
          'enhance': enhance,
          'tool_executed': true,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to generate image: $e',
        'prompt': prompt,
        'model': model,
        'width': width,
        'height': height,
        'enhance': enhance,
        'tool_executed': true,
      };
    }
  }

  Future<Map<String, dynamic>> _fetchImageModels(Map<String, dynamic> params) async {
    final refresh = params['refresh'] as bool? ?? false;

    try {
      final response = await http.get(
        Uri.parse('https://ahamai-api.officialprakashkrsingh.workers.dev/v1/images/models'),
        headers: {
          'Authorization': 'Bearer ahamaibyprakash25',
        },
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final modelsData = data['data'] as List;
        
        List<Map<String, dynamic>> models = modelsData.map<Map<String, dynamic>>((item) => {
          'id': item['id'],
          'name': item['name'] ?? item['id'],
          'provider': item['provider'] ?? 'unknown',
          'width': item['width'] ?? 1024,
          'height': item['height'] ?? 1024,
        }).toList();
        
        return {
          'success': true,
          'models': models,
          'model_names': models.map((m) => m['id']).toList(),
          'total_count': models.length,
          'refreshed': refresh,
          'tool_executed': true,
          'execution_time': DateTime.now().toIso8601String(),
          'api_status': 'Connected successfully',
        };
      } else {
        return {
          'success': false,
          'error': 'API returned status ${response.statusCode}: ${response.reasonPhrase}',
          'tool_executed': true,
          'api_status': 'Failed to connect',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to fetch image models: $e',
        'tool_executed': true,
        'api_status': 'Connection error',
      };
    }
  }

  Future<Map<String, dynamic>> _webSearch(Map<String, dynamic> params) async {
    final query = params['query'] as String? ?? '';
    final source = params['source'] as String? ?? 'both';
    final limit = params['limit'] as int? ?? 5;

    if (query.isEmpty) {
      return {
        'success': false,
        'error': 'Query parameter is required',
      };
    }

    try {
      List<Map<String, dynamic>> allResults = [];
      
      // Wikipedia search
      if (source == 'wikipedia' || source == 'both') {
        try {
          final wikipediaUrl = 'https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=${Uri.encodeComponent(query)}&srlimit=$limit&format=json&origin=*';
          final wikipediaResponse = await http.get(Uri.parse(wikipediaUrl)).timeout(Duration(seconds: 15));
          
          if (wikipediaResponse.statusCode == 200) {
            final wikipediaData = json.decode(wikipediaResponse.body);
            final searchResults = wikipediaData['query']['search'] as List? ?? [];
            
            for (final result in searchResults) {
              allResults.add({
                'title': result['title'],
                'snippet': result['snippet']?.replaceAll(RegExp(r'<[^>]*>'), ''),
                'url': 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(result['title'])}',
                'source': 'Wikipedia',
              });
            }
          }
        } catch (e) {
          debugPrint('Wikipedia search error: $e');
        }
      }

      // DuckDuckGo Instant Answer API
      if (source == 'duckduckgo' || source == 'both') {
        try {
          final duckduckgoUrl = 'https://api.duckduckgo.com/?q=${Uri.encodeComponent(query)}&format=json&no_html=1&skip_disambig=1';
          final duckduckgoResponse = await http.get(Uri.parse(duckduckgoUrl)).timeout(Duration(seconds: 15));
          
          if (duckduckgoResponse.statusCode == 200) {
            final duckduckgoData = json.decode(duckduckgoResponse.body);
            
            // Add abstract if available
            if (duckduckgoData['Abstract'] != null && duckduckgoData['Abstract'].toString().isNotEmpty) {
              allResults.add({
                'title': duckduckgoData['Heading'] ?? query,
                'snippet': duckduckgoData['Abstract'],
                'url': duckduckgoData['AbstractURL'] ?? '',
                'source': 'DuckDuckGo Abstract',
              });
            }
            
            // Add related topics
            final relatedTopics = duckduckgoData['RelatedTopics'] as List? ?? [];
            for (final topic in relatedTopics.take(3)) {
              if (topic is Map && topic['Text'] != null && topic['Text'].toString().isNotEmpty) {
                allResults.add({
                  'title': topic['Text']?.split(' - ').first ?? '',
                  'snippet': topic['Text'],
                  'url': topic['FirstURL'] ?? '',
                  'source': 'DuckDuckGo',
                });
              }
            }
          }
        } catch (e) {
          debugPrint('DuckDuckGo search error: $e');
        }
      }

      // Limit results and remove duplicates
      final uniqueResults = <Map<String, dynamic>>[];
      final seenTitles = <String>{};
      
      for (final result in allResults) {
        final title = result['title']?.toString().toLowerCase() ?? '';
        if (title.isNotEmpty && !seenTitles.contains(title) && uniqueResults.length < limit) {
          seenTitles.add(title);
          uniqueResults.add(result);
        }
      }

      return {
        'success': true,
        'query': query,
        'source': source,
        'limit': limit,
        'results': uniqueResults,
        'total_found': uniqueResults.length,
        'tool_executed': true,
        'execution_time': DateTime.now().toIso8601String(),
        'description': 'Web search completed successfully with ${uniqueResults.length} results',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to perform web search: $e',
        'query': query,
        'source': source,
        'limit': limit,
        'tool_executed': true,
      };
    }
  }

  Future<Map<String, dynamic>> _screenshotVision(Map<String, dynamic> params) async {
    final imageUrl = params['image_url'] as String? ?? '';
    final question = params['question'] as String? ?? 'What do you see in this image?';
    final model = params['model'] as String? ?? 'claude-4-sonnet';

    if (imageUrl.isEmpty) {
      return {
        'success': false,
        'error': 'image_url parameter is required',
      };
    }

    try {
      final response = await http.post(
        Uri.parse('https://ahamai-api.officialprakashkrsingh.workers.dev/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer ahamaibyprakash25',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'user', 
              'content': [
                {'type': 'text', 'text': question},
                {'type': 'image_url', 'image_url': {'url': imageUrl}},
              ]
            },
          ],
          'max_tokens': 300,
          'temperature': 0.7,
        }),
      ).timeout(Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final answer = data['choices'][0]['message']['content'] as String? ?? '';

        return {
          'success': true,
          'question': question,
          'model': model,
          'image_url': imageUrl,
          'answer': answer,
          'tool_executed': true,
          'execution_time': DateTime.now().toIso8601String(),
          'description': 'Screenshot analyzed successfully using vision AI',
        };
      } else {
        return {
          'success': false,
          'error': 'API returned status ${response.statusCode}: ${response.reasonPhrase}',
          'question': question,
          'model': model,
          'image_url': imageUrl,
          'tool_executed': true,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to analyze screenshot: $e',
        'question': question,
        'model': model,
        'image_url': imageUrl,
        'tool_executed': true,
      };
    }
  }
}