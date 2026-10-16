import 'package:fluent_ui/fluent_ui.dart';

import '../app/theme.dart';
import '../data/curriculum.dart';
import '../data/event_store.dart';
import '../lessons/progress.dart';
import '../widgets/common.dart';
import 'lesson_page.dart';

class LessonsPage extends StatelessWidget {
  const LessonsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final progress = LessonProgress.fromEvents(StoreScope.of(context).events);
    return PageFrame(
      title: 'Lessons',
      subtitle: 'From beginner to 2000, one step at a time',
      trailing: Pill('${progress.lessonsDone} / ${allLessons.length} done', color: p.success),
      child: ResponsiveGrid(
        minItemWidth: 360,
        children: [for (final c in courses) _CourseCard(course: c, progress: progress)],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.progress});

  final Course course;
  final LessonProgress progress;

  IconData get _icon => switch (course.phase) {
        Phase.opening => FluentIcons.rocket,
        Phase.middlegame => FluentIcons.flow,
        Phase.endgame => FluentIcons.flag,
      };

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_icon, color: p.accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.title,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: p.text)),
                  Text(course.subtitle, style: TextStyle(color: p.muted, fontSize: 12)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Meter(progress.courseFraction(course))),
            const SizedBox(width: 10),
            Text('${(progress.courseFraction(course) * 100).round()}%',
                style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          for (final l in course.lessons) _LessonRow(lesson: l, progress: progress),
        ],
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson, required this.progress});

  final Lesson lesson;
  final LessonProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final status = progress.status(lesson);
    final (icon, color) = switch (status) {
      LessonStatus.done => (FluentIcons.completed_solid, p.success),
      LessonStatus.inProgress => (FluentIcons.circle_half_full, p.accent),
      LessonStatus.todo => (FluentIcons.circle_ring, p.muted),
    };
    final steps = lesson.steps.length;
    final done = (progress.fraction(lesson) * steps).round();
    return HoverButton(
      semanticLabel: '${lesson.title}, ${status == LessonStatus.done ? 'done' : '$done of $steps steps'}',
      onPressed: () => openLesson(context, lesson),
      builder: (context, states) => Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: states.isHovered ? p.surfaceAlt : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lesson.title,
                      style: TextStyle(
                          color: p.text,
                          fontWeight: status == LessonStatus.inProgress ? FontWeight.w600 : FontWeight.w400)),
                  Text(lesson.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(status == LessonStatus.inProgress ? '$done/$steps' : '${lesson.level}',
                style: TextStyle(color: status == LessonStatus.inProgress ? p.accent : p.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
