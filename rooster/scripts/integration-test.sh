#!/usr/bin/env bash
# The expanded reporter: the GitHub one prints "all tests passed" even when
# the run fails on an error outside a test (a teardown, an error after a
# test had completed), and does not print that error.
flutter test integration_test/runner.dart -d linux --reporter expanded --dart-define=HOMESERVER=$HOMESERVER --dart-define=BUILD_MODE=release --dart-define=USER1_NAME=$USER1_NAME --dart-define=USER1_PW=$USER1_PW
