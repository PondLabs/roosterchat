// The course's awards card: after a course's last hole's results, before
// whatever comes next (the next course, the vote, the totals). A podium of
// the top three chicks in their hats, then the course's awards, one line
// each: what it is for, who earned it (their little egg and name) and the
// figure. The figures are the engine's own tally (core/awards.dart), so
// every client shows the same card.
part of 'putt_hud.dart';

/// The podium's places: up to three steps, each the players who share
/// that place (golf ranks: a tie shares a step, the next place skips
/// ahead), first place first.
List<(int, List<ScoreRow>)> puttPodium(List<ScoreRow> rows) {
  final ranks = _ranks(rows);
  final steps = <(int, List<ScoreRow>)>[];
  for (var i = 0; i < rows.length; i++) {
    if (ranks[i] > 3) break;
    if (steps.isEmpty || steps.last.$1 != ranks[i]) {
      steps.add((ranks[i], []));
    }
    steps.last.$2.add(rows[i]);
  }
  return steps;
}

/// The players a course's card ranks: everyone still in the match who is
/// not watching, by total.
List<ScoreRow> _rankedRows(PuttMatch match) => [
      for (final row in _presentRows(match))
        if (!match.engine.isSpectator(row.playerId)) row,
    ];

/// The awards the running course earned, for its card.
List<PuttAward> puttAwardsOf(PuttMatch match) => puttCourseAwards(
      match.engine.courseTally.all,
      standing: [for (final row in _rankedRows(match)) row.playerId],
    );

/// A course's end: the podium, the awards, the Continue.
class PuttCourseAwardsCard extends StatelessWidget {
  final PuttMatch match;
  final double? maxHeight;

  const PuttCourseAwardsCard({super.key, required this.match, this.maxHeight});

  @override
  Widget build(BuildContext context) {
    final rows = _rankedRows(match);
    final awards = puttAwardsOf(match);
    final course = match.courseName;
    return _PuttCard(
      maxHeight: maxHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            labelPuttAwardsTitle(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _Type.display(24, color: PuttPalette.yolk),
          ),
          if (course != null) ...[
            const SizedBox(height: 4),
            Text(
              labelPuttAwardsCourse(course).toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _Type.label(12, spacing: 1.4),
            ),
          ],
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (rows.isNotEmpty)
                    _Podium(match: match, steps: puttPodium(rows)),
                  if (awards.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final award in awards)
                      _AwardLine(match: match, award: award),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _ContinueButton(match: match),
        ],
      ),
    );
  }
}

/// The steps, second on the left, first in the middle, third on the right,
/// each as wide as the chicks on it; the chicks stand on top, their names
/// under them in their colour.
class _Podium extends StatelessWidget {
  final PuttMatch match;
  final List<(int, List<ScoreRow>)> steps;

  const _Podium({required this.match, required this.steps});

  static double _stepHeight(int rank) => switch (rank) {
        1 => 58,
        2 => 40,
        _ => 26,
      };

  /// Gold, silver (the cream), bronze: the third a warm bronze, not the
  /// palette's stone grey (a grey "3" on a grey step read as nothing).
  static Color _stepColour(int rank) => switch (rank) {
        1 => PuttPalette.yolk,
        2 => PuttPalette.cream,
        _ => const Color(0xFFDB8B47),
      };

  @override
  Widget build(BuildContext context) {
    final byRank = {for (final step in steps) step.$1: step.$2};
    // The podium's own order: 2, 1, 3 (a place nobody holds is left out).
    final order = [
      for (final rank in const [2, 1, 3])
        if (byRank[rank] case final players?) (rank, players),
    ];
    // A step is as wide as the chicks on it, and never narrower than a
    // chick and a half (the first a little more), so a crowd tied for
    // second does not squeeze the winner's step to a sliver.
    double units((int, List<ScoreRow>) step) =>
        math.max(step.$2.length.toDouble(), step.$1 == 1 ? 1.6 : 1.2);
    final total = order.fold<double>(0, (sum, step) => sum + units(step));
    return LayoutBuilder(builder: (context, constraints) {
      // Every chick gets the same room, up to a comfortable size.
      final room = math.min(94.0, constraints.maxWidth / math.max(total, 1));
      final chick = (room * 0.72).clamp(22.0, 64.0);
      return Row(
        key: const Key('putt-podium'),
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (rank, players) in order)
            SizedBox(
              width: units((rank, players)) * room,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final row in players)
                        Expanded(
                          child: _PodiumChick(
                            match: match,
                            playerId: row.playerId,
                            size: chick,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    key: Key('putt-podium-step-$rank'),
                    height: _stepHeight(rank),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: _stepColour(rank).withValues(alpha: 0.2),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(8)),
                      border: Border(
                        top: BorderSide(
                            color: _stepColour(rank).withValues(alpha: 0.8),
                            width: 2),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$rank',
                      style: _Type.display(rank == 1 ? 26 : 20,
                          color: _stepColour(rank)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }
}

/// A chick in its half shell and its player's hat, their name under it.
class _PodiumChick extends StatelessWidget {
  final PuttMatch match;
  final String playerId;
  final double size;

  const _PodiumChick(
      {required this.match, required this.playerId, required this.size});

  @override
  Widget build(BuildContext context) {
    final tint = puttTintOf(match, playerId);
    final name = displayNameOf(match, playerId);
    final mine = playerId == match.localPlayerId;
    return Column(
      key: Key('putt-podium-chick-$playerId'),
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size.square(size),
          painter:
              _ChickPainter(tint: tint, hat: puttLookOf(match, playerId).hat),
        ),
        const SizedBox(height: 2),
        Text(
          mine ? labelPuttYouName(name) : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: _Type.body(12, color: tint, weight: mine ? 900 : 800),
        ),
      ],
    );
  }
}

class _ChickPainter extends CustomPainter {
  final Color tint;
  final HatchlingHat hat;

  const _ChickPainter({required this.tint, required this.hat});

  @override
  void paint(Canvas canvas, Size size) {
    // The hat rises over the head: the chick keeps to the box's lower
    // part so a top hat still fits.
    final box = Rect.fromLTWH(size.width * 0.12, size.height * 0.2,
        size.width * 0.76, size.height * 0.8);
    paintPuttChick(canvas, box, tint, hat);
  }

  @override
  bool shouldRepaint(_ChickPainter oldDelegate) =>
      oldDelegate.tint != tint || oldDelegate.hat != hat;
}

/// One award: its mark, its name and the figure, then who earned it.
class _AwardLine extends StatelessWidget {
  final PuttMatch match;
  final PuttAward award;

  const _AwardLine({required this.match, required this.award});

  @override
  Widget build(BuildContext context) {
    final id = award.playerId;
    final name = displayNameOf(match, id);
    final mine = id == match.localPlayerId;
    final what = [
      Text(
        puttAwardName(award.kind),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _Type.display(15, color: PuttPalette.yolk),
      ),
      Text(
        puttAwardFigure(award, match.config.physics.ballRadius),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _Type.body(12, color: PuttPalette.cream.withValues(alpha: 0.72)),
      ),
    ];
    final who = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TintDot(puttTintOf(match, id), look: puttLookOf(match, id), size: 18),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            mine ? labelPuttYouName(name) : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _Type.body(14, weight: mine ? 800 : 700),
          ),
        ),
      ],
    );
    return Container(
      key: Key('putt-award-${award.kind.name}'),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: mine
            ? PuttPalette.yolk.withValues(alpha: 0.14)
            : PuttPalette.cream.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        // Side by side when there is room for both; on a narrow card the
        // winner goes under the figure, so neither is cut short.
        final wide = constraints.maxWidth >= 360;
        return Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                _awardMark(award.kind),
                textAlign: TextAlign.center,
                style: _Type.emoji(22),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...what,
                  if (!wide) ...[const SizedBox(height: 3), who],
                ],
              ),
            ),
            if (wide) ...[
              const SizedBox(width: 8),
              Expanded(flex: 2, child: who),
            ],
          ],
        );
      }),
    );
  }
}

/// Each award's mark (a Twemoji glyph).
// Not translated: emoji glyphs, not words.
String _awardMark(PuttAwardKind kind) => switch (kind) {
      PuttAwardKind.ace => '⛳',
      PuttAwardKind.bowlingBall => '🎳',
      PuttAwardKind.highFlyer => '🦅',
      PuttAwardKind.stickyFingers => '💰',
      PuttAwardKind.hardBoiled => '🥚',
      PuttAwardKind.makingASplash => '💦',
    };

/// An award's name on the card.
String puttAwardName(PuttAwardKind kind) => switch (kind) {
      PuttAwardKind.ace => labelPuttAwardAce(),
      PuttAwardKind.bowlingBall => labelPuttAwardBowlingBall(),
      PuttAwardKind.highFlyer => labelPuttAwardHighFlyer(),
      PuttAwardKind.stickyFingers => labelPuttAwardStickyFingers(),
      PuttAwardKind.hardBoiled => labelPuttAwardHardBoiled(),
      PuttAwardKind.makingASplash => labelPuttAwardMakingASplash(),
    };

/// What an award was for: a count, or a flight in egg lengths (the world
/// has no metres; an egg is two [ballRadius] long).
String puttAwardFigure(PuttAward award, double ballRadius) {
  final count = award.figure.round();
  return switch (award.kind) {
    PuttAwardKind.ace => labelPuttAwardAceFigure(count),
    PuttAwardKind.bowlingBall => labelPuttAwardKnocksFigure(count),
    PuttAwardKind.highFlyer => labelPuttAwardFlightFigure(
        math.max(1, (award.figure / (2 * ballRadius)).round())),
    PuttAwardKind.stickyFingers => labelPuttAwardStealsFigure(count),
    PuttAwardKind.hardBoiled => labelPuttAwardBlocksFigure(count),
    PuttAwardKind.makingASplash => labelPuttAwardDunksFigure(count),
  };
}

// ---- strings ---------------------------------------------------------------------------

String labelPuttAwardsTitle() => Intl.message("And the awards go to…",
    name: "labelPuttAwardsTitle",
    desc: "Title of the card at the end of a minigolf course, with a podium "
        "of the top three players and a few playful awards");

String labelPuttAwardsCourse(String course) => Intl.message("$course is done",
    name: "labelPuttAwardsCourse",
    args: [course],
    desc: "The line under the awards card's title; the placeholder is "
        "the name of the minigolf course that just ended");

String labelPuttAwardAce() => Intl.message("Ace",
    name: "labelPuttAwardAce",
    desc: "Name of the minigolf course award for the most holes in one");

String labelPuttAwardBowlingBall() => Intl.message("Bowling ball",
    name: "labelPuttAwardBowlingBall",
    desc: "Name of the minigolf course award for knocking the most other "
        "players' eggs (balls) at rest");

String labelPuttAwardHighFlyer() => Intl.message("High flyer",
    name: "labelPuttAwardHighFlyer",
    desc: "Name of the minigolf course award for the longest flight off a "
        "ramp (kicker)");

String labelPuttAwardStickyFingers() => Intl.message("Sticky fingers",
    name: "labelPuttAwardStickyFingers",
    desc: "Name of the minigolf course award for stealing the most power-ups "
        "from other players");

String labelPuttAwardHardBoiled() => Intl.message("Hard-boiled",
    name: "labelPuttAwardHardBoiled",
    desc: "Name of the minigolf course award for the egg whose shield "
        "stopped the most attacks (a pun on a tough egg)");

String labelPuttAwardMakingASplash() => Intl.message("Making a splash",
    name: "labelPuttAwardMakingASplash",
    desc: "Name of the minigolf course's joke award for the egg that fell "
        "in the water (or off the course) the most");

String labelPuttAwardAceFigure(int count) => Intl.plural(count,
    one: "$count hole in one",
    other: "$count holes in one",
    name: "labelPuttAwardAceFigure",
    args: [count],
    desc: "What the Ace award was for; the placeholder is how many holes "
        "the player sank with their first stroke");

String labelPuttAwardKnocksFigure(int count) => Intl.plural(count,
    one: "$count egg knocked",
    other: "$count eggs knocked",
    name: "labelPuttAwardKnocksFigure",
    args: [count],
    desc: "What the Bowling ball award was for; the placeholder is how many "
        "resting eggs the player's egg rolled into");

String labelPuttAwardFlightFigure(int eggs) => Intl.plural(eggs,
    one: "$eggs egg long",
    other: "$eggs eggs long",
    name: "labelPuttAwardFlightFigure",
    args: [eggs],
    desc: "How far the High flyer award's flight went, measured in egg "
        "lengths (the game has no metres); the placeholder is the count");

String labelPuttAwardStealsFigure(int count) => Intl.plural(count,
    one: "$count power-up pinched",
    other: "$count power-ups pinched",
    name: "labelPuttAwardStealsFigure",
    args: [count],
    desc: "What the Sticky fingers award was for; the placeholder is how "
        "many power-ups the player stole");

String labelPuttAwardBlocksFigure(int count) => Intl.plural(count,
    one: "$count attack shrugged off",
    other: "$count attacks shrugged off",
    name: "labelPuttAwardBlocksFigure",
    args: [count],
    desc: "What the Hard-boiled award was for; the placeholder is how many "
        "attacks the player's shield stopped");

String labelPuttAwardDunksFigure(int count) => Intl.plural(count,
    one: "$count dunk",
    other: "$count dunks",
    name: "labelPuttAwardDunksFigure",
    args: [count],
    desc: "What the Making a splash award was for; the placeholder is how "
        "many times the player's egg fell in the water or off the course");
