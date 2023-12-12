import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

const basePath =
    '/Users/adrian/Library/Mobile Documents/iCloud~com~abbyy~finereader/Documents';
const fileList = [
  'a-azzurro',
  'babau-buzzurro',
  'cabina-carrozzina',
  'da-dileguarsi',
  'diletto-duttile'
];

void main(List<String> arguments) {
  exitCode = 0; // Presume success
  final parser = ArgParser()
    ..addFlag('all', negatable: false, abbr: 'a')
    ..addFlag('combine', negatable: false, abbr: 'c');

  ArgResults argResults = parser.parse(arguments);
  final paths = argResults.rest;

  ocr(
    paths,
    processAll: argResults['all'] as bool,
    combine: argResults['combine'] as bool,
  );
}
//TODO fix very last line to remove leading space

Future<void> ocr(List<String> paths,
    {bool processAll = false, bool combine = false}) async {
  String combinedFile = '';
  if (paths.isEmpty && !processAll) {
    // No files provided as arguments. Read from stdin and print each line.
    await stdin.pipe(stdout);
  } else {
    paths = processAll ? fileList : paths;
    print(paths);
    for (final path in paths) {
      String baseName = '$basePath/$path';

      String markdown = await docxToMarkdown(baseName);
      List<String> lines = await utf8.decoder
          .bind(File(markdown).openRead())
          .transform(const LineSplitter())
          .toList();
      List<String> parsed = parseMarkdown(lines);

      final filename = '$baseName.new.md';
      String parsedFile = parsed.reduce((value, element) => '$value\n$element');
      var file = await File(filename).writeAsString(parsedFile);

      if (combine) {
        combinedFile += parsedFile;
      }
    }
    if (combine) {
      final filename = '$basePath/dictionary.md';
      var file = await File(filename).writeAsString(combinedFile);
    }
  }
}

List<String> parseMarkdown(List<String> markdown) {
  List<String> parsedMarkdown;
  parsedMarkdown = removeBlankLines(markdown);
  parsedMarkdown = makeHeader(parsedMarkdown);
  parsedMarkdown = joinLines(parsedMarkdown);
  for (var i = 0; i < 40; i++) {
    // print('${parsedMarkdown[i]}');
  }

  return parsedMarkdown;
}

List<String> removeBlankLines(List<String> markdown) {
  List<String> parsedMarkdown = [];
  // match "> \|"
  RegExp exp1 = RegExp(r'^\> \\\|$');
  // match "> *\|*"
  RegExp exp2 = RegExp(r'^\> \*\\\|\*$');
  // match "> **\|**"
  RegExp exp3 = RegExp(r'^\> \*\*\\\|\*\*$');
  // match "> "
  RegExp exp4 = RegExp(r'^> *$');
  for (final line in markdown) {
    bool match1 = exp1.hasMatch(line);
    bool match2 = exp2.hasMatch(line);
    bool match3 = exp3.hasMatch(line);
    bool match4 = exp4.hasMatch(line);
    if (match1 || match2 || match3 || match4) {
    } else {
      parsedMarkdown.add(line);
    }
  }
  return parsedMarkdown;
}

List<String> joinLines(List<String> markdown) {
  List<String> parsedMarkdown = [];
  String currentLine = '';
  // match any line starting with "> "
  RegExp exp1 = RegExp(r'^> ');
  for (var i = 0; i < markdown.length; i++) {
    String line = markdown[i];
    bool match1 = exp1.hasMatch(line);
    if (match1) {
      if (i == 0) {
        if (exp1.hasMatch(markdown[1])) {
          parsedMarkdown.add(cleanOCRErrors(line));
        }
      } else if (i == markdown.length - 1) {
        parsedMarkdown.add(cleanOCRErrors(line.substring(2)));
      } else {
        currentLine = '$currentLine ${line.substring(2)}';
      }
    } else {
      currentLine = removeTabs(currentLine);
      // print(currentLine);
      currentLine = collapseWhiteSpace(currentLine);
      currentLine = convertBoldItalics(currentLine);
      currentLine = tidyItalics(currentLine);
      currentLine = tidyHyphens(currentLine);
      currentLine = tidyCommasAndDots(currentLine);
      currentLine = cleanOCRErrors(currentLine);
      // print(currentLine);
      currentLine = splitLines(currentLine);
      currentLine = removeBlanks(currentLine);
      parsedMarkdown.add(currentLine);
      // Header Line
      parsedMarkdown.add(line);
      currentLine = '';
    }
  }
  return parsedMarkdown;
}

List<String> makeHeader(List<String> markdown) {
  List<String> parsedHeader = [];
  // Header of form **HEADER\|**Definition\n
  RegExp headerExp1 = RegExp(r'^> \*\*(\w.*?)\\\|\*\*');
  // Header of form **HEADER\|Definition**\n
  RegExp headerExp2 = RegExp(r'^> \*\*(\w.*?)\\\|(.*)\*\*');
  // Header of form HEADER\|Definition\n
  RegExp headerExp3 = RegExp(r'^> ([A-Z]+)\\\|(.*)');

  for (var i = 0; i < markdown.length; i++) {
    String line = markdown[i];
    Iterable<RegExpMatch> headerMatches1 = headerExp1.allMatches(line);
    Iterable<RegExpMatch> headerMatches2 = headerExp2.allMatches(line);
    Iterable<RegExpMatch> headerMatches3 = headerExp3.allMatches(line);
    if (headerMatches1.isNotEmpty) {
      var headerMatch = headerMatches1.elementAt(0);
      if (headerMatch.group(1) != null) {
        String headerStr = '# ${headerMatch.group(1)}';
        parsedHeader.add(headerStr);
        String definition = '> ${line.substring(headerMatch.end)}';

        // parsedHeader.add(tidyDefinition(definition));
        parsedHeader.add(definition);
        // print('$headerStr: $definition');
      }
    } else if (headerMatches2.isNotEmpty || headerMatches3.isNotEmpty) {
      var headerMatch = headerMatches2.isNotEmpty
          ? headerMatches2.elementAt(0)
          : headerMatches3.elementAt(0);
      if (headerMatch.group(1) != null) {
        String headerStr = '# ${headerMatch.group(1)}';
        parsedHeader.add(headerStr);
        String definition = '';
        definition = '> ${headerMatch.group(2)!}';
        definition = collapseWhiteSpace(definition);

        // parsedHeader.add(tidyDefinition(definition));
        parsedHeader.add(definition);
      }
    } else {
      // line = removeSpaces(line);
      parsedHeader.add(line);
    }
  }
  return parsedHeader;
}

String removeTabs(String line) {
  // Remove any remaining \|, *\|*, **\|**
  line = line.contains("**\\|**") ? line.replaceAll("**\\|**", "") : line;
  line = line.contains("*\\|*") ? line.replaceAll("*\\|*", "") : line;
  line = line.contains("\\|") ? line.replaceAll("\\|", "") : line;
  return line;
}

String cleanOCRErrors(String line) {
  line = line.replaceAll("\\*1", "'l");
  line = line.replaceAll("'1", "'l");
  line = line.replaceAll("\\^6\\^", "'");
  line = line.replaceAll("\\^9\\^", "'");
  line = line.replaceAll("\\^66\\^", '"');
  line = line.replaceAll(RegExp('• *'), '');

  // Clean up orphan characters
  line = line.replaceAll('. .', '.');
  return line;
}

String collapseWhiteSpace(String line) {
  // Collapse whitespace
  line = line.replaceAll(RegExp(r'\s{2,}'), ' ');
  line = line.replaceFirst(RegExp(r'\*\*VEDI.*\*\*'), ' ');
  return line;
}

String tidyItalics(String line) {
  // Collapse italics
  if (line.contains('* **')) {
  } else if (line.contains('* *')) {
    line = line.replaceAll('* *', ' ');
  }
  // Butt italics against word
  line = line.replaceAllMapped(RegExp(r' \* (\w)'), (Match m) => ' *${m[1]}');
  // Fix (word *word)* word to *(words)* word
  if (line.contains(RegExp(r'^\*\((\w.*?)\*(\w.*?)\)\*'))) {
    print('bef: $line');
    line = line.replaceAllMapped(RegExp(r'^\*\((\w.*?)\*(\w.*?)\)\*'),
        (Match m) => ' *(${m[1]}${m[2]})*');
    print('aft: $line');
  }
  return line;
}

String convertBoldItalics(String line) {
  line = line.replaceAll('***', '*');
  return line;
}

String tidyHyphens(String line) {
  // remove multiple hyphens
  line = line.replaceAll(RegExp(r'--+'), '');
  // remove other hyphen sequences - -
  line = line.replaceAll('- -', '');
  // remove hyphenated words
  line = line.replaceAllMapped(
      RegExp(r'(\w)- *(\w)'), (Match m) => '${m[1]}${m[2]}');
  line = line.replaceAllMapped(
      RegExp(r'([àèìòù])- *(\w)'), (Match m) => '${m[1]}${m[2]}');
  line = line.replaceAllMapped(
      RegExp(r'(\w)- *(\w)'), (Match m) => '${m[1]}${m[2]}');
  return line;
}

String tidyDefinition(String line) {
  String cleanLine = '';

  // Collapse ** to *
  cleanLine = cleanLine.replaceAllMapped(
      RegExp(r'\*\*^\*(.*)\*\*^\*'), (Match m) => '*${m[1]}*');

  return cleanLine;
}

String splitLines(String line) {
  // Split line on a full stop
  line = line.replaceAll(". ", ". \n");
  line = line.replaceAll(".* ", ".* \n");
  // Split line on /
  line = line.replaceAll("*/ ", "\n*");
  line = line.replaceAll("*/", "\n*");
  line = line.replaceAll("/ ", "\n");
  line = line.replaceAll("/", "\n");
  // Split line before (word)
  if (line.contains(RegExp(r'. \*\(\w.*?\)\*'))) {
    line = line.replaceAllMapped(
        RegExp(r'(.) (\*\(\w.*?\)\*)'), (Match m) => '${m[1]}\n${m[2]}');
  }
  // Split line before italics
  if (line.contains(RegExp(r'( )\*(\w)'))) {
    print('splitLines: $line');
  }
  line = line.replaceAllMapped(
      RegExp(r'( )\*(\w)'), (Match m) => '${m[1]}\n*${m[2]}');
  line = removeSpaces(line);
  line = removeOrphans(line);
  return line;
}

String removeOrphans(String line) {
  // Clean up orphan characters
  line.replaceAll(RegExp(r'^.$'), '');
  return line;
}

String removeBlanks(String line) {
  line.replaceAll(RegExp(r'\n *\n'), '\n');
  return line;
}

String removeSpaces(String line) {
  // Remove leading and trailing whitespace
  line = line.replaceAll(RegExp(r'^ *'), '');
  line = line.replaceAll(RegExp(r' *$'), '');
  return line;
}

String tidyCommasAndDots(String line) {
  // Add spaces after commas
  line = line.replaceAllMapped(RegExp(r',(\S)'), (Match m) => ', ${m[1]}');

  // remove multiple dots
  line = line.replaceAll(RegExp(r'\.\.\.\.*'), '.');
  if (line.contains('...')) {
  } else if (line.contains('..')) {
    line = line.replaceAll('..', '.');
  }
  return line;
}

Future<void> _handleError(String markdown) async {
  if (await FileSystemEntity.isDirectory(markdown)) {
    stderr.writeln('error: $markdown is a directory');
  } else {
    exitCode = 2;
  }
}

Future<String> docxToMarkdown(String fileName) async {
  var docx = '$fileName.docx';
  var markdown = '$fileName.md';

  var result = await Process.run(
      'pandoc', ['-f', 'docx', '-t', 'markdown', '-o', '$markdown', '$docx']);
  return markdown;
}
