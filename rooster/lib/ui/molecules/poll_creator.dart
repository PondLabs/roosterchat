import 'package:rooster/client/components/polls/poll_component.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class PollCreator extends StatefulWidget {
  const PollCreator({super.key});

  @override
  State<PollCreator> createState() => _PollCreatorState();
}

class _PollCreatorState extends State<PollCreator> {
  TextEditingController questionController = TextEditingController();
  bool openPoll = true;
  bool multiAnswer = false;

  List<TextEditingController> options = List.from([
    TextEditingController(),
    TextEditingController(),
  ], growable: true);

  String? errorMessage;

  String get labelPollQuestion => Intl.message("Question",
      name: "labelPollQuestion",
      desc: "Label of the field for the question in the poll creator");

  String get labelPollOpen => Intl.message("Open Poll",
      name: "labelPollOpen",
      desc: "Kind of poll in the poll creator whose results show as people "
          "vote");

  String get labelPollClosed => Intl.message("Closed Poll",
      name: "labelPollClosed",
      desc: "Kind of poll in the poll creator whose results stay hidden "
          "until it ends");

  String get labelPollOpenDescription =>
      Intl.message("Voters can see results as they come in",
          name: "labelPollOpenDescription",
          desc: "Under 'Open Poll' in the poll creator");

  String get labelPollClosedDescription =>
      Intl.message("Votes are hidden until the poll ends",
          name: "labelPollClosedDescription",
          desc: "Under 'Closed Poll' in the poll creator");

  String labelPollOption(int number) => Intl.message("Option $number",
      name: "labelPollOption",
      args: [number],
      desc: "Label of each answer field in the poll creator, with its "
          "number: Option 1, Option 2…");

  String get labelPollAllowMultipleAnswers =>
      Intl.message("Allow multiple answers",
          name: "labelPollAllowMultipleAnswers",
          desc: "Checkbox in the poll creator: voters may pick more than one "
              "answer");

  String get promptPollAddOption => Intl.message("Add Option",
      name: "promptPollAddOption",
      desc: "Button in the poll creator that adds another answer field");

  String get promptPollCreate => Intl.message("Create",
      name: "promptPollCreate",
      desc: "Button at the bottom of the poll creator that posts the poll");

  String get errorPollNoQuestion => Intl.message("Poll must have a question",
      name: "errorPollNoQuestion",
      desc: "Shown in the poll creator when the question was left empty");

  String get errorPollBlankOption =>
      Intl.message("Poll cannot have a blank option",
          name: "errorPollBlankOption",
          desc: "Shown in the poll creator when an answer field was left "
              "empty");

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: questionController,
              decoration: InputDecoration(
                labelText: labelPollQuestion,
                border: const OutlineInputBorder(),
              ),
            ),
            SizedBox(
              height: 8,
            ),
            tiamat.DropdownSelector(
              value: openPoll,
              items: [true, false],
              onItemSelected: (item) {
                if (item != null) {
                  setState(() {
                    openPoll = item;
                  });
                }
              },
              itemBuilder: (item) {
                var msg = item ? labelPollOpen : labelPollClosed;
                var descriptor = item
                    ? labelPollOpenDescription
                    : labelPollClosedDescription;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      tiamat.Text(msg),
                      tiamat.Text.labelLow(descriptor)
                    ],
                  ),
                );
              },
            ),
            SizedBox(
              height: 12,
            ),
            SizedBox(
              height: 200,
              child: ScrollConfiguration(
                behavior:
                    ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
                    child: Column(
                      spacing: 8,
                      children: [
                        for (int i = 0; i < options.length; i++)
                          Row(
                            spacing: 8,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: options[i],
                                  decoration: InputDecoration(
                                      suffixIcon: SizedBox(
                                          height: 34,
                                          width: 34,
                                          child: options.length > 2
                                              ? tiamat.IconButton(
                                                  icon: Icons.remove,
                                                  onPressed: () {
                                                    setState(() {
                                                      options.removeAt(i);
                                                    });
                                                  },
                                                )
                                              : null),
                                      border: const OutlineInputBorder(),
                                      labelText: labelPollOption(i + 1)),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: CheckboxListTile(
                      dense: true,
                      title: tiamat.Text(labelPollAllowMultipleAnswers),
                      value: multiAnswer,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            multiAnswer = value;
                          });
                        }
                      }),
                ),
                TextButton.icon(
                  label: Text(promptPollAddOption),
                  onPressed: () {
                    setState(() {
                      options.add(TextEditingController());
                    });
                  },
                ),
              ],
            ),
            if (errorMessage != null) tiamat.Text.error(errorMessage!),
            SizedBox(
              height: 12,
            ),
            tiamat.Button(
                text: promptPollCreate,
                onTap: () async {
                  setState(() {
                    errorMessage = null;
                  });

                  String question = questionController.text;
                  if (question.isEmpty) {
                    setState(() {
                      errorMessage = errorPollNoQuestion;
                    });
                    return;
                  }

                  List<String> parsedOptions = List.empty(growable: true);

                  for (var controller in options) {
                    if (controller.text.trim().isEmpty) {
                      setState(() {
                        errorMessage = errorPollBlankOption;
                      });
                      return;
                    }

                    parsedOptions.add(controller.text.trim());
                  }

                  Navigator.of(context).pop(PollCreateArgs(
                      question: question,
                      options: parsedOptions,
                      multiAnswer: multiAnswer,
                      publicAnswers: openPoll));
                })
          ],
        ),
      ),
    );
  }
}
