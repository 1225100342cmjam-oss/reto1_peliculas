import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// CONFIGURACIÓN
// Opción A (recomendada): ejecutar con --dart-define=TMDB_API_KEY=tu_key
// Opción B: reemplaza el defaultValue por tu key (no la subas a GitHub).
// ---------------------------------------------------------------------------
const String tmdbApiKey = String.fromEnvironment(
  'TMDB_API_KEY',
  defaultValue: 'PEGA_AQUI_TU_API_KEY',
);

void main() => runApp(const CineApp());

// ---------------------------------------------------------------------------
// MODELOS
// ---------------------------------------------------------------------------
class Mood {
  final String label;
  final String emoji;
  final int genreId; // ID de género en TMDB

  const Mood(this.label, this.emoji, this.genreId);
}

const List<Mood> moods = [
  Mood('Feliz', '😄', 35), // Comedia
  Mood('Triste', '😢', 18), // Drama
  Mood('Aventurero', '🧭', 12), // Aventura
  Mood('Romántico', '💘', 10749), // Romance
  Mood('Con miedo', '👻', 27), // Terror
  Mood('Curioso', '🛸', 878), // Ciencia ficción
];

class Movie {
  final int id;
  final String title;
  final String overview;
  final String? posterPath;
  final double rating;
  final String year;

  Movie({
    required this.id,
    required this.title,
    required this.overview,
    required this.posterPath,
    required this.rating,
    required this.year,
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    final date = (json['release_date'] as String?) ?? '';
    return Movie(
      id: json['id'] as int,
      title: (json['title'] as String?) ?? 'Sin título',
      overview: (json['overview'] as String?)?.trim().isNotEmpty == true
          ? json['overview'] as String
          : 'Esta película no tiene sinopsis en español.',
      posterPath: json['poster_path'] as String?,
      rating: ((json['vote_average'] as num?) ?? 0).toDouble(),
      year: date.length >= 4 ? date.substring(0, 4) : 's/f',
    );
  }

  String? get posterUrl =>
      posterPath == null ? null : 'https://image.tmdb.org/t/p/w500$posterPath';
}

// ---------------------------------------------------------------------------
// SERVICIO TMDB
// ---------------------------------------------------------------------------
class TmdbService {
  static const _base = 'https://api.themoviedb.org/3';
  final _random = Random();

  Future<List<Movie>> _get(String path, Map<String, String> params) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: {
      'api_key': tmdbApiKey,
      'language': 'es-MX',
      ...params,
    });

    final res = await http.get(uri).timeout(const Duration(seconds: 15));

    if (res.statusCode == 401) {
      throw Exception('API key inválida. Revisa tu TMDB_API_KEY.');
    }
    if (res.statusCode != 200) {
      throw Exception('TMDB respondió con error ${res.statusCode}.');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final results = (data['results'] as List).cast<Map<String, dynamic>>();
    return results.map(Movie.fromJson).toList();
  }

  /// Una película al azar del género asociado al estado de ánimo.
  Future<Movie> randomByMood(Mood mood) async {
    final page = _random.nextInt(5) + 1; // páginas 1..5 para variar
    final list = await _get('/discover/movie', {
      'with_genres': '${mood.genreId}',
      'sort_by': 'popularity.desc',
      'vote_count.gte': '200',
      'page': '$page',
    });
    if (list.isEmpty) throw Exception('No se encontraron películas.');
    return list[_random.nextInt(list.length)];
  }

  /// Tendencias de la semana.
  Future<List<Movie>> trending() => _get('/trending/movie/week', {});
}

// ---------------------------------------------------------------------------
// APP
// ---------------------------------------------------------------------------
class CineApp extends StatelessWidget {
  const CineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cine de fin de semana',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE9A23B),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF12181F),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _service = TmdbService();

  int _mode = 0; // 0 = al azar por ánimo, 1 = tendencias
  Mood? _mood;
  Future<Movie>? _movieFuture;
  Future<List<Movie>>? _trendingFuture;

  void _pickMood(Mood mood) {
    setState(() {
      _mood = mood;
      _movieFuture = _service.randomByMood(mood);
    });
  }

  void _changeMode(int mode) {
    setState(() {
      _mode = mode;
      if (mode == 1) _trendingFuture ??= _service.trending();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cine de fin de semana'),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('Según mi ánimo'),
                      icon: Icon(Icons.mood),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('Tendencias'),
                      icon: Icon(Icons.trending_up),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => _changeMode(s.first),
                ),
                const SizedBox(height: 16),
                Expanded(child: _mode == 0 ? _moodView() : _trendingView()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----- Vista 1: película al azar según el ánimo -----
  Widget _moodView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('¿Cómo te sientes hoy?',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in moods)
              ChoiceChip(
                label: Text('${m.emoji} ${m.label}'),
                selected: _mood == m,
                onSelected: (_) => _pickMood(m),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _movieFuture == null
              ? const _Message(
                  icon: Icons.movie_filter_outlined,
                  text: 'Elige tu estado de ánimo y te recomiendo una película.',
                )
              : FutureBuilder<Movie>(
                  future: _movieFuture,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return _Message(
                        icon: Icons.error_outline,
                        text: _cleanError(snap.error),
                      );
                    }
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          MovieCard(movie: snap.data!, expanded: true),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => _pickMood(_mood!),
                            icon: const Icon(Icons.casino_outlined),
                            label: const Text('Otra película'),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ----- Vista 2: lista de tendencias -----
  Widget _trendingView() {
    return FutureBuilder<List<Movie>>(
      future: _trendingFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _Message(
            icon: Icons.error_outline,
            text: _cleanError(snap.error),
          );
        }
        final movies = snap.data!;
        return ListView.separated(
          itemCount: movies.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => MovieCard(movie: movies[i]),
        );
      },
    );
  }

  String _cleanError(Object? e) =>
      e.toString().replaceFirst('Exception: ', '').replaceFirst(
            'ClientException: ',
            'Sin conexión: ',
          );
}

// ---------------------------------------------------------------------------
// WIDGETS
// ---------------------------------------------------------------------------
class MovieCard extends StatelessWidget {
  final Movie movie;
  final bool expanded; // true = sinopsis completa

  const MovieCard({super.key, required this.movie, this.expanded = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final posterWidth = expanded ? 140.0 : 100.0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: posterWidth,
              child: _Poster(url: movie.posterUrl),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 18, color: Color(0xFFE9A23B)),
                        const SizedBox(width: 4),
                        Text('${movie.rating.toStringAsFixed(1)}  ·  ${movie.year}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      movie.overview,
                      maxLines: expanded ? null : 4,
                      overflow: expanded ? null : TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  final String? url;
  const _Poster({this.url});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Colors.black26,
      alignment: Alignment.center,
      constraints: const BoxConstraints(minHeight: 150),
      child: const Icon(Icons.image_not_supported_outlined),
    );

    if (url == null) return placeholder;

    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.black26,
          constraints: const BoxConstraints(minHeight: 150),
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Message({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.white54),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}