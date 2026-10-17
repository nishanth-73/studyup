import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/subjects/data/subjects_models.dart';
import 'package:studyup/features/subjects/presentation/subjects_controller.dart';

void main() {
  group('Chapter sources', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<SubjectsController> ready() async {
      final controller = SubjectsController();
      controller.addSubject(name: 'Physics', meta: 'Mechanics');
      return controller;
    }

    /// The subject created by [ready], found by its unique meta so the
    /// first-run starter library (which also ships a Physics example)
    /// never confuses the lookup, whenever seeding lands.
    Subject userSubject(SubjectsController controller) =>
        controller.state.firstWhere((s) => s.meta == 'Mechanics');

    test('add + delete sources on a chapter', () async {
      final controller = await ready();
      final subjectId = userSubject(controller).id;
      final chapterId = userSubject(controller).chapters.single.id;

      controller.addSource(
        subjectId: subjectId,
        chapterId: chapterId,
        name: '  Chapter notes PDF  ',
        kind: StudySourceKind.pdf,
        url: 'https://example.com/notes.pdf',
      );
      var chapter = userSubject(controller).chapters.single;
      expect(chapter.sources, hasLength(1));
      expect(chapter.sources.single.name, 'Chapter notes PDF');
      expect(chapter.sources.single.kind, StudySourceKind.pdf);
      expect(chapter.sources.single.url, 'https://example.com/notes.pdf');

      // Blank URLs are ignored; other chapter edits keep sources.
      controller.addSource(
        subjectId: subjectId,
        chapterId: chapterId,
        name: 'Empty',
        kind: StudySourceKind.link,
        url: '   ',
      );
      expect(userSubject(controller).chapters.single.sources, hasLength(1));
      controller.renameChapter(
        subjectId: subjectId,
        chapterId: chapterId,
        title: 'Renamed',
      );
      expect(userSubject(controller).chapters.single.sources, hasLength(1));

      final sourceId = chapter.sources.single.id;
      controller.deleteSource(
        subjectId: subjectId,
        chapterId: chapterId,
        sourceId: sourceId,
      );
      expect(userSubject(controller).chapters.single.sources, isEmpty);
      controller.dispose();
    });

    test('sources persist across reloads; legacy rows load empty', () async {
      final first = await ready();
      final subjectId = userSubject(first).id;
      final chapterId = userSubject(first).chapters.single.id;
      first.addSource(
        subjectId: subjectId,
        chapterId: chapterId,
        name: 'Ref',
        kind: StudySourceKind.image,
        url: 'https://example.com/img.png',
      );
      // Let the write queue flush.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      first.dispose();

      final restored = SubjectsController();
      for (var i = 0; i < 50; i++) {
        final match = restored.state.where((s) => s.id == subjectId);
        if (match.isNotEmpty &&
            match.single.chapters.single.sources.isNotEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final chapter = restored.state
          .singleWhere((s) => s.id == subjectId)
          .chapters
          .single;
      expect(chapter.sources.single.name, 'Ref');
      expect(chapter.sources.single.kind, StudySourceKind.image);
      restored.dispose();
    });
  });
}
