// The actors: the eggs (a true egg profile turned on a lathe, painted with
// an Easter band in the player's colour and the pattern they picked,
// rolling by their velocity and settling on their side when they stop, a
// soft contact shadow under them and, under the viewer's own, a marker
// ring and a bobbing arrow), the hen (legs that step with her walk, a head
// that bobs), and the "?" crates floating over their glow.
part of '../putt_world3d.dart';

/// The egg's height over its radius: the long axis' half-length.
const double _eggAspect = 1.28;

/// The drawn egg runs a little bigger than the physics' disc, so it reads
/// from the camera's height; at a rail the overlap stays a sliver.
const double _eggVisualScale = 1.2;

/// An egg the nest just took: it slides to the cup's middle and drops in,
/// below the opening (where the turf's depth hides it).
class _SinkingEgg {
  _SinkingEgg(this.view, this.nest, {required this.depth});

  static const double life = 0.42;

  /// When (of [life]) it stops sliding and falls.
  static const double fallFrom = 0.25;

  final _EggView3D view;
  final Vec2 nest;

  /// How far it falls: the cup's depth, and at least its own height.
  final double depth;
  double age = 0;

  /// Its size, [t] of the way through: a touch smaller, to fit the cup.
  double scaleAt(double t) => 1 - t * t * 0.15;

  /// Its height over the turf at the nest, [t] of the way through.
  double heightAt(double t) {
    final rest = view.restHeight * scaleAt(t);
    final fall = ((t - fallFrom) / (1 - fallFrom)).clamp(0.0, 1.0);
    return rest - fall * fall * math.max(depth, rest * 2.4);
  }
}

/// One egg on the green. Its [group] carries the roll (position and
/// quaternion); [ground] stays level under it with the shadow and the
/// viewer's marker; [trail] holds the puffs a fast egg leaves behind.
class _EggView3D {
  _EggView3D(this._radius, ui.Color tint,
      {required int trailHex,
      required this.onBounce,
      EggPattern pattern = EggPattern.zigzag,
      _Ground? terrain,
      int glow = 0x2A2622})
      : terrain = terrain ?? _Ground(),
        _glow = glow,
        _pattern = pattern {
    group = tjs.Group()..name = 'egg';
    _tintHex = _hexOf(tint);
    _texture = _eggTextureFor(_tintHex, _pattern);
    body = tjs.Mesh(_eggGeometry(_radius), _shellMaterial(_texture, _glow))
      ..name = 'egg-shell'
      ..castShadow = true;
    group.add(body);
    // The egg's silhouette through whatever hides it (a rail, the silo, a
    // hay bale): drawn only where something nearer already stands.
    final xrayMaterial = tjs.MeshBasicMaterial({
      tjs.MaterialProperty.color: _lin(_mix(_tintHex, 0xFFFFFF, 0.25)),
      tjs.MaterialProperty.transparent: true,
      tjs.MaterialProperty.opacity: 0.5,
      tjs.MaterialProperty.depthWrite: false,
      tjs.MaterialProperty.fog: false,
    })
      ..depthFunc = tjs.GreaterDepth;
    _xray = tjs.Mesh(body.geometry, xrayMaterial)
      ..name = 'egg-xray'
      ..renderOrder = 20;
    body.add(_xray);
    // The ink outline (the shell's back faces, a size up): the eggs are the
    // characters, drawn with a line round them so they pop from the farm
    // at any distance. The world sets its weight from the camera's.
    _outline = tjs.Mesh(
      body.geometry,
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.color: _lin(_hexOf(PuttPalette.ink)),
        tjs.MaterialProperty.side: tjs.BackSide,
        // Transparent from the start, like the shell: a Ghost Egg fades
        // them by their opacity alone, and no program ever recompiles.
        tjs.MaterialProperty.transparent: true,
      }),
    )..name = 'egg-outline';
    body.add(_outline);
    outlineFor(24);

    ground = tjs.Group()..name = 'egg-ground';
    _shadow = tjs.Mesh(
      tjg.CircleGeometry(radius: _radius * 1.15, segments: 24),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.map: _shadowTexture,
        tjs.MaterialProperty.color: _lin(0x1A140E),
        tjs.MaterialProperty.transparent: true,
        tjs.MaterialProperty.opacity: 0.55,
        tjs.MaterialProperty.depthWrite: false,
      }),
    )
      ..name = 'egg-shadow'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.02
      ..renderOrder = 2;
    // Every egg sits on a soft disc of its player's colour: who is who
    // reads from the ground even when the band faces away.
    _tintDisc = tjs.Mesh(
      tjg.RingGeometry(_radius * 0.95, _radius * 1.4, 32, 1),
      _unlit(_tintHex, opacity: _tintDiscOpacity, depthWrite: false),
    )
      ..name = 'egg-tint-disc'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.025
      ..renderOrder = 2;
    // A waiting egg's mark (it has not putted, a ghost to the others): a
    // dashed ink ring at its foot, turning slowly.
    _waitRing = tjs.Mesh(
      _dashedRing(_radius * 1.45, _radius * 1.62, 14, 0.55),
      _unlit(_hexOf(PuttPalette.ink), opacity: 0.6, depthWrite: false),
    )
      ..name = 'egg-wait-ring'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.028
      ..renderOrder = 3
      ..visible = false;
    _marker = tjs.Mesh(
      tjg.RingGeometry(_radius * 1.55, _radius * 1.85, 36, 1),
      _unlit(_tintHex, opacity: 0.9, depthWrite: false),
    )
      ..name = 'egg-marker'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.03
      ..renderOrder = 3
      ..visible = false;
    // The viewer's pin over the egg: a round yolk cone, tip down, inside an
    // ink outline (its back faces, a size up), so it reads from any angle.
    // Drawn last and over everything (the transparent pass, no depth
    // test): no egg in front ever hides where the viewer's egg is.
    _arrow = tjs.Mesh(
      tjg.ConeGeometry(_radius * 0.6, _radius * 1.3, 24),
      _matte(_hexOf(PuttPalette.yolk), roughness: 0.45)
        ..transparent = true
        ..depthTest = false,
    )
      ..name = 'egg-arrow'
      // Tip down, toward the egg.
      ..rotation.x = math.pi
      ..castShadow = false
      ..renderOrder = 22
      ..visible = false;
    _arrow.add(tjs.Mesh(
      tjg.ConeGeometry(_radius * 0.6, _radius * 1.3, 24),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.color: _lin(_hexOf(PuttPalette.ink)),
        tjs.MaterialProperty.side: tjs.BackSide,
        tjs.MaterialProperty.transparent: true,
        tjs.MaterialProperty.depthTest: false,
      }),
    )
      ..name = 'egg-arrow-outline'
      ..renderOrder = 21
      ..scale.setValues(1.22, 1.14, 1.22));
    ground
      ..add(_shadow)
      ..add(_tintDisc)
      ..add(_waitRing)
      ..add(_marker)
      ..add(_arrow);
    trail = tjs.Group()..name = 'egg-trail';
    // Turf flecks kicked up behind it, darker than the grass.
    final trailColor = _lin(trailHex);
    _turfColor = trailColor;
    for (var i = 0; i < _trailLength; i++) {
      final puff = _Billboard(map: _shadowTexture, color: trailColor)
        ..name = 'egg-trail-puff'
        ..visible = false
        ..renderOrder = 3;
      _puffs.add(puff);
      trail.add(puff);
    }
    // The Thick Shell's bubble, facing the camera round the egg (it rides
    // the unturned trail group, the shell's roll would turn it away).
    _bubble = _Billboard(map: _bubbleMap, color: _lin(_bubbleHexOf(_tintHex)))
      ..name = 'egg-bubble'
      ..visible = false
      ..renderOrder = 11;
    trail.add(_bubble);
  }

  /// The bubble's colour for an egg of [tint]: a pale sky with a touch of
  /// the player's own.
  static int _bubbleHexOf(int tint) => _mix(0xFFFFFF, tint, 0.18);

  /// The soap-film disc every egg's bubble wears (shared, like the
  /// shadow's disc).
  static final tjs.DataTexture _bubbleMap = _bubbleTexture();

  late final _Billboard _bubble;

  /// How long the bubble has been up (it blows up when the shell comes).
  double _bubbleAge = 0;

  /// The shell's opacity now: 1 solid, lower while a Ghost Egg lasts or
  /// while it stands aside for the viewer's egg.
  double _ghostOpacity = 1;

  /// Whether this egg stands in front of the viewer's resting egg on the
  /// screen (the world says, each frame): it fades to a ghost of itself,
  /// so the viewer's egg, its pin and the aim read through it.
  bool screening = false;

  /// How far it has faded for that, 0 to 1 (eased over a fifth of a
  /// second).
  double _screened = 0;

  static const int _trailLength = 18;

  /// Told when the egg slams into something (a rail, a bumper, another
  /// egg): where, how hard (0..1), and whether it is the viewer's.
  final void Function(Vec2 at, double strength, bool mine) onBounce;

  /// The ground the egg stands on (its hills).
  final _Ground terrain;

  /// Whether this egg has ever been the viewer's own (the frame marks it
  /// only while its shot is ready).
  bool everMine = false;

  late final tjs.Mesh _tintDisc;
  late final tjs.Mesh _waitRing;
  late final tjs.Mesh _xray;
  late final tjs.Mesh _outline;

  /// The outline's weight for a camera [distance] away: about the same
  /// width on screen near or far.
  void outlineFor(double distance) {
    final k = 1 + (0.03 + distance * 0.0026).clamp(0.05, 0.15);
    _outline.scale.setValues(k, k, k);
  }

  Vec2? _lastVelocity;
  double _squash = 0;

  late final tjs.Group trail;
  final List<_Billboard> _puffs = [];

  /// The trail's recent spots and their ages, newest last.
  /// The trail's spots: where, how old, and for a flight the height it
  /// was drawn at (null: on the ground - a turf fleck, every other one a
  /// puff in the player's colour).
  final List<(Vec2, double, double?)> _trailSpots = [];

  /// Counts the ground spots, so they alternate fleck and colour.
  int _trailCount = 0;

  /// The turf flecks' colour, and the flight's puffs' (a cream wisp of
  /// air behind the egg).
  late final tjs.Color _turfColor;
  static final tjs.Color _airColor = _lin(0xFFF8EE);

  /// The trail's puffs in the player's colour, lightened a little (made
  /// again only when the colour changes).
  tjs.Color get _tintGlow {
    if (_trailTintHex != _tintHex) {
      _trailTintHex = _tintHex;
      _trailTint = _lin(_mix(_tintHex, 0xFFFFFF, 0.25));
    }
    return _trailTint!;
  }

  tjs.Color? _trailTint;
  int _trailTintHex = -1;
  double _sinceSpot = 0;

  /// Where the egg stood last frame, and how high its centre rode at rest
  /// (the sink starts from both).
  Vec2 lastPosition = Vec2.zero;
  double get restHeight => _radius * _eggAspect;

  late final tjs.Group group;
  late final tjs.Group ground;
  late final tjs.Mesh body;
  late final tjs.Mesh _shadow;
  late final tjs.Mesh _marker;
  late final tjs.Mesh _arrow;
  late tjs.DataTexture _texture;
  late int _tintHex;
  EggPattern _pattern;

  /// The hat its player's chick wears: the hatch reads it.
  HatchlingHat hat = HatchlingHat.none;

  final double _radius;

  /// Seconds the egg has been still, and whether it ever rolled (an egg
  /// fresh on the tee stands up; one that has rolled lies on its side).
  double _still = 0;
  bool _rolled = false;

  /// The ground the egg is drawn on and how fast that drawn ground sinks:
  /// it follows rising ground at once and sinking ground no faster than a
  /// fall, so off a ledge's lip the egg drops through the air (null until
  /// the first frame).
  double? _floor;
  double _sinkSpeed = 0;

  /// The fall's pull, units/s^2: a drop of one unit takes a third of a
  /// second, which reads as a fall at the egg's size.
  static const double _gravity = 18;

  /// The shadow's soft disc, shared by every egg of every world.
  static final tjs.DataTexture _shadowTexture = _discTexture(hardness: 1.4);

  /// The egg in [tint] wearing [pattern]: a new seat's colour or a new
  /// pick of its player's.
  void restyle(ui.Color tint, EggPattern pattern) {
    final hex = _hexOf(tint);
    if (hex == _tintHex && pattern == _pattern) return;
    final retinted = hex != _tintHex;
    _tintHex = hex;
    _pattern = pattern;
    // The shared paint for that colour and pattern, on a fresh material:
    // no paint is freed mid-play, and no compiled material has its map
    // swapped under it (the renderer once drew such an egg not at all).
    _texture = _eggTextureFor(hex, pattern);
    final old = body.material;
    body.material = _shellMaterial(_texture, _glow);
    old?.map = null;
    old?.emissiveMap = null;
    old?.dispose();
    _ghostOpacity = -1; // the fresh shell takes the fade on the next frame
    if (!retinted) return;
    _marker.material?.color = _lin(hex);
    _tintDisc.material?.color = _lin(hex);
    _xray.material?.color = _lin(_mix(hex, 0xFFFFFF, 0.25));
    _bubble.look.color = _lin(_bubbleHexOf(hex));
  }

  /// The shell: the colour's paint, a soft sheen, and a whisper of light
  /// so eggs never sit muddy in the shade. The light takes the paint's
  /// colours: at dusk the shell stays white and the band glows in the
  /// player's colour.
  static tjs.MeshStandardMaterial _shellMaterial(
      tjs.DataTexture paint, int glow) {
    final material = tjs.MeshStandardMaterial({
      tjs.MaterialProperty.map: paint,
      tjs.MaterialProperty.emissiveMap: paint,
      tjs.MaterialProperty.roughness: 0.36,
      tjs.MaterialProperty.metalness: 0.0,
      // Transparent from the start (opacity 1, depth still written): a
      // Ghost Egg only moves the opacity, so no program recompiles mid-play.
      tjs.MaterialProperty.transparent: true,
    });
    material.emissive = _lin(glow);
    return material;
  }

  /// The shell's own light (the theme's: warmer and stronger at dusk, so
  /// a white egg stays white in the blue hour).
  final int _glow;

  /// Holed: the shell and its outline draw with the cup's inside (the
  /// opaque pass, [_cupOrder]), before the opening's depth-only disc, so
  /// the turf line does not cut the egg as it sinks into the cup. Opaque
  /// from here on: the view goes when the chick hatches.
  // ponytail: the first hole-out compiles the opaque shell's program; warm
  // it up with the others if that frame ever hitches.
  void intoCup() {
    for (final mesh in [body, _outline]) {
      mesh.renderOrder = _cupOrder;
      mesh.material!
        ..transparent = false
        ..needsUpdate = true;
    }
  }

  /// The stand (ground spot plus the hop's lift, or the flight's altitude
  /// off a kicker), then the roll: world axis from the horizontal
  /// velocity, omega = |v| / r, pre-multiplied so world space holds the
  /// accumulated spin - the egg tips exactly where it goes (and keeps
  /// spinning in the air). Still, it eases onto its side, the way an egg
  /// rests.
  void sync(PuttWorldEgg egg, double dt, double time) {
    final speed = egg.speed;
    if (egg.mine) everMine = true;
    // The viewer's egg draws after the aim (which skips the depth test, so
    // no other egg hides it): the arrow comes out from under this one.
    final order = egg.mine ? 10 : 0;
    if (body.renderOrder != order) {
      body.renderOrder = order;
      _outline.renderOrder = order;
    }
    // The silhouette through whatever hides it is for finding one's own
    // egg: on another player's it read as a stray translucent oval over the
    // silo.
    _xray.visible = everMine;
    // A bounce: the heading swings hard in one frame while it is quick.
    final last = _lastVelocity;
    if (last != null && dt > 0) {
      final before = last.length;
      if (before > 2.2 && speed > 0.5) {
        final turn = last.dot(egg.velocity) / (before * speed);
        if (turn < 0.82) {
          final strength = ((before - 2.2) / 10).clamp(0.0, 1.0);
          _squash = 0.6 + strength * 0.4;
          onBounce(egg.position, strength, everMine);
        }
      } else if (before < 0.3 && speed > 4) {
        // The putt itself: a stretch as it leaves.
        _squash = 0.5;
      }
    }
    _lastVelocity = egg.velocity;
    if (_squash > 0) {
      _squash = math.max(0, _squash - dt / 0.16);
      final k = math.sin(_squash * math.pi) * 0.16;
      body.scale.setValues(1 + k, 1 - k, 1 + k);
    } else {
      body.scale.setValues(1, 1, 1);
    }
    if (speed > 1e-4 && dt > 0 && egg.radius > 0) {
      final axis = tjs.Vector3(egg.velocity.x, 0, egg.velocity.y);
      if (axis.length > 1e-6) {
        axis.normalize();
        // Rolling toward +x spins about -z: the wheel axis is up x velocity.
        final rollAxis = tjs.Vector3(0, 1, 0).cross(axis);
        if (rollAxis.length > 1e-6) {
          rollAxis.normalize();
          final delta =
              tjs.Quaternion().setFromAxisAngle(rollAxis, speed * dt / _radius);
          group.quaternion.premultiply(delta);
          _rolled = true;
        }
      }
      _still = 0;
    } else {
      _still += dt;
    }
    if (_rolled && _still > 0.05 && dt > 0) _settle(dt);

    // The lowest point of the (roughly ellipsoidal) shell under this
    // orientation: the world's up read in the egg's own frame.
    final up =
        tjs.Vector3(0, 1, 0).applyQuaternion(group.quaternion.clone().invert());
    final a = _radius;
    final h = _radius * _eggAspect;
    final support = math
        .sqrt(a * a * up.x * up.x + h * h * up.y * up.y + a * a * up.z * up.z);
    final floor = terrain.at(egg.position);
    final air = egg.air;
    final drawn = air != null
        ? _flyAt(air, floor, egg.position, dt)
        : _fallTo(floor, egg.position, dt);
    group.position.setValues(
        egg.position.x, drawn + support + egg.height, egg.position.y);

    lastPosition = egg.position;
    _syncTrail(egg, dt);

    // The ground pieces: the shadow shrinks and fades as a hop, a fall or
    // a flight lifts the egg off it (it stays on the ground below); on a
    // slope they lie along it.
    // Over a pond (a flight across it) the shadow lies on the water's
    // sheet, not on the bed under it, where the sheet hid it.
    final onWater = terrain.overWater(egg.position) ? _overWater : 0.0;
    ground.position.setValues(egg.position.x, floor + onWater, egg.position.y);
    if (!terrain.flat) ground.quaternion.setFrom(terrain.tiltAt(egg.position));
    final lift = ((egg.height + drawn - floor) / (_radius * 3)).clamp(0.0, 1.0);
    // Up in the air (a flight, a hop, a fall) the soft spot right under the
    // egg is its shadow: dark enough to read where it will come down, and
    // the sun's own (off to one side, far from a high egg) is put out.
    _aloft = lift > 0.12;
    final shadowScale = 1 - lift * 0.3;
    _shadow.scale.setValues(shadowScale, shadowScale, 1);
    // A ghost's shadow thins with it.
    _shadow.material?.opacity =
        0.55 * (1 - lift * 0.2) * (0.35 + 0.65 * _ghostOpacity.clamp(0.0, 1.0));

    _syncBubble(egg, dt, time, drawn + support + egg.height);
    _waiting = egg.waiting;
    _waitRing.visible = egg.waiting;
    if (egg.waiting) _waitRing.rotation.z += dt * 0.5;
    _syncGhost(egg, time, dt);

    final resting = speed < 0.05;
    final showMarker = egg.mine && resting;
    _marker.visible = showMarker;
    _arrow.visible = showMarker;
    if (showMarker) {
      final pulse = 0.5 + 0.5 * math.sin(time * 4);
      final s = 1 + pulse * 0.08;
      _marker.scale.setValues(s, s, 1);
      _marker.material?.opacity = 0.65 + 0.3 * pulse;
      _arrow.position.y = h * 2 + 0.6 + math.sin(time * 3.2).abs() * 0.35;
    }
  }

  /// The Thick Shell's bubble: blown up round the egg when the shield
  /// comes, wobbling like a soap film while it holds; gone the frame the
  /// shield is spent (the game pops it in shards).
  void _syncBubble(PuttWorldEgg egg, double dt, double time, double centre) {
    if (!egg.shielded) {
      _bubbleAge = 0;
      _bubble.visible = false;
      return;
    }
    _bubbleAge += dt;
    final blow = (_bubbleAge / 0.3).clamp(0.0, 1.0);
    // Out with a little overshoot, then the film's slow wobble.
    final grow = blow < 1 ? 1.15 * math.sin(blow * math.pi * 0.62) : 1.0;
    final wobble = math.sin(time * 3.4) * 0.035;
    final size = _radius * 4.4 * grow;
    _bubble
      ..visible = true
      ..position.setValues(egg.position.x, centre, egg.position.y)
      ..scale.setValues(size * (1 + wobble), size * (1 - wobble), 1);
    _bubble.look.opacity = 0.95;
  }

  /// A Ghost Egg: the shell and its ink go see-through and flicker while
  /// it lasts, blinking back toward solid as it runs out; its shadow
  /// thins. Opacity only - every material was made transparent at build.
  void _syncGhost(PuttWorldEgg egg, double time, double dt) {
    var target = 1.0;
    final left = egg.ghostSeconds;
    if (left > 0) {
      final wave = 0.5 + 0.5 * math.sin(time * 7.3) * math.sin(time * 2.9 + 1);
      // The viewer's own ghost stays findable (they still aim it): a
      // ghost, not gone.
      target = everMine ? 0.46 + 0.2 * wave : 0.26 + 0.22 * wave;
      if (left < 0.9) {
        // The last beat: it blinks back toward solid.
        final blink = math.sin(time * 26) > 0 ? 1.0 : 0.0;
        target += (0.95 - target) * blink * (1 - left / 0.9);
      }
    }
    // Waiting (it has not putted, a ghost to the others): see-through.
    if (_waiting) target = math.min(target, _waitingOpacity);
    // Standing aside for the viewer's egg: a third of itself, still there,
    // in a tenth of a second (an egg passing through mine went by half
    // faded) - at once when it is inside mine ([screenAtOnce]).
    _screened = (_screened + (screening ? dt : -dt) * 10).clamp(0.0, 1.0);
    target = math.min(target, 1 - 0.66 * _screened);
    body.castShadow = target > 0.9 && !_aloft;
    if ((target - _ghostOpacity).abs() < 1e-3) return;
    _ghostOpacity = target;
    body.material?.opacity = target;
    _outline.material?.opacity = target >= 1 ? 1 : target * 0.7;
    _xray.material?.opacity = 0.5 * target;
    _tintDisc.material?.opacity = _tintDiscOpacity * (0.45 + 0.55 * target);
    body.castShadow = target > 0.9 && !_aloft;
  }

  /// Off the ground this frame (its sun shadow out, the spot under it on).
  bool _aloft = false;

  /// How far over the ground a pond's sheet stands, and a little more: the
  /// ground pieces lie on it over water.
  static const double _overWater = 0.05;

  /// Another player's egg that has not putted on the hole, this frame.
  bool _waiting = false;

  /// How see-through a waiting egg is (its pattern still reads).
  static const double _waitingOpacity = 0.55;

  /// Inside the viewer's egg on the ground: fully aside this frame.
  void screenAtOnce() => _screened = 1;

  /// The colour disc's opacity under a solid egg.
  static const double _tintDiscOpacity = 0.78;

  /// Where the drawn egg stands, given the [ground] under it: on rising
  /// ground at once, on sinking ground as fast as it sinks - unless that is
  /// faster than a fall: then the egg is in the air, falling from where it
  /// was, and it lands with a squash and a puff of dust. A jump (a reset, a
  /// rabbit hole, a new hole) puts it down at once.
  double _fallTo(double ground, Vec2 position, double dt) {
    final floor = _floor;
    final last = _drawnAt;
    _drawnAt = position;
    final jumped = last == null || last.distanceTo(position) > 2.5;
    if (floor == null || dt <= 0 || jumped || ground >= floor) {
      _floor = ground;
      _sinkSpeed = 0;
      _inAir = false;
      return ground;
    }
    final speed = _sinkSpeed + _gravity * dt;
    final fallen = floor - speed * dt;
    if (fallen > ground) {
      _floor = fallen;
      _sinkSpeed = speed;
      if (fallen - ground > 0.02) _inAir = true;
      return fallen;
    }
    if (_inAir && speed > 2.5) {
      // Down off a drop (or a flight): the shell squashes, the dust flies.
      _land(position, speed);
    }
    _inAir = false;
    _fallPeak = 0;
    _sinkSpeed = math.min(speed, (floor - ground) / dt);
    _floor = ground;
    return ground;
  }

  /// Where the drawn egg stands in the air off a kicker: at the engine's
  /// [air], never under the [ground] drawn. Its fall's pace is kept for the
  /// drop's bookkeeping ([_fallTo]), which brings it down the last of the
  /// way once the engine has it rolling again, with the landing's squash;
  /// a hard landing the engine bounces back up squashes here, where the
  /// egg turns from falling to rising by the ground.
  double _flyAt(double air, double ground, Vec2 position, double dt) {
    final last = _floor;
    if (last != null && dt > 0 && _inAir) {
      final falling = (last - air) / dt;
      if (falling > 0) {
        _fallPeak = math.max(_fallPeak, falling);
      } else if (falling < 0) {
        if (_fallPeak > 2.5 && math.min(last, air) - ground < 0.3) {
          _land(position, _fallPeak);
        }
        _fallPeak = 0;
      }
      _sinkSpeed = math.max(0.0, falling);
    } else {
      _sinkSpeed = 0;
      _fallPeak = 0;
    }
    _floor = air;
    _drawnAt = position;
    _inAir = true;
    return math.max(air, ground);
  }

  /// Down on the ground at [speed]: the shell squashes and the dust flies,
  /// harder the faster it came.
  void _land(Vec2 position, double speed) {
    final strength = ((speed - 2.5) / 5).clamp(0.0, 1.0);
    _squash = 0.6 + strength * 0.4;
    onBounce(position, strength, everMine);
  }

  Vec2? _drawnAt;
  bool _inAir = false;

  /// The fastest the drawn egg has fallen since it last rose, for the
  /// squash where a flight's bounce turns it back up.
  double _fallPeak = 0;

  /// The trail: a fast egg drops a soft puff every few hundredths of a
  /// second; the puffs fade and shrink over half a second.
  void _syncTrail(PuttWorldEgg egg, double dt) {
    const life = 0.6;
    for (var i = 0; i < _trailSpots.length; i++) {
      final (at, age, y) = _trailSpots[i];
      _trailSpots[i] = (at, age + dt, y);
    }
    _trailSpots.removeWhere((spot) => spot.$2 >= life);
    _sinceSpot += dt;
    if (egg.air == null && egg.speed > 2.6 && _sinceSpot > 0.03) {
      // Rolling fast: turf flecks kicked up behind it, and puffs in the
      // player's colour between them - who rolls where reads in a still.
      _sinceSpot = 0;
      _trailCount++;
      _trailSpots.add((egg.position, 0, null));
    } else if (egg.air != null && egg.speed > 1.5 && _sinceSpot > 0.035) {
      // In the air it kicks up no turf: a wisp of air at its own height,
      // so a flight reads as one in a still.
      _sinceSpot = 0;
      _trailSpots.add((egg.position, 0, group.position.y));
    }
    if (_trailSpots.length > _trailLength) _trailSpots.removeAt(0);
    for (var i = 0; i < _puffs.length; i++) {
      final puff = _puffs[i];
      if (i >= _trailSpots.length) {
        puff.visible = false;
        continue;
      }
      final (at, age, y) = _trailSpots[i];
      final fade = 1 - age / life;
      puff.visible = true;
      if (y == null) {
        // Fleck or colour by the spot's place in the run (stable as the
        // oldest go).
        final tinted = (_trailCount - (_trailSpots.length - 1 - i)).isOdd;
        puff.position.setValues(at.x, terrain.at(at) + _radius * 0.35, at.y);
        final size = _radius * (tinted ? 0.9 + 0.9 * fade : 0.7 + 0.8 * fade);
        puff.scale.setValues(size, size, 1);
        puff.material?.color = tinted ? _tintGlow : _turfColor;
        puff.material?.opacity = (tinted ? 0.5 : 0.55) * fade;
      } else {
        puff.position.setValues(at.x, y, at.y);
        final size = _radius * (0.8 + 0.9 * fade);
        puff.scale.setValues(size, size, 1);
        puff.material?.color = _airColor;
        puff.material?.opacity = 0.85 * fade;
      }
    }
  }

  /// Eases the long axis down to the horizontal: an egg at rest lies on
  /// its side.
  void _settle(double dt) {
    final long =
        tjs.Vector3(0, 1, 0).applyQuaternion(group.quaternion).normalize();
    final flat = tjs.Vector3(long.x, 0, long.z);
    if (flat.length < 1e-3) flat.setValues(1, 0, 0);
    flat.normalize();
    final tip = tjs.Quaternion().setFromUnitVectors(long, flat);
    final target = tip.multiply(group.quaternion.clone());
    final k = 1 - math.exp(-2.6 * dt);
    group.quaternion.slerp(target, k);
  }

  void dispose() {
    body.geometry?.dispose();
    // The shell's paint is shared by colour and outlives the egg.
    body.material?.map = null;
    body.material?.emissiveMap = null;
    body.material?.dispose();
    group.dispose();
    _marker.geometry?.dispose();
    _marker.material?.dispose();
    _tintDisc.geometry?.dispose();
    _tintDisc.material?.dispose();
    _waitRing.geometry?.dispose();
    _waitRing.material?.dispose();
    for (final piece in [_arrow, ..._arrow.children.whereType<tjs.Mesh>()]) {
      piece.geometry?.dispose();
      piece.material?.dispose();
    }
    _shadow.geometry?.dispose();
    _shadow.material?.map = null;
    _shadow.material?.dispose();
    ground.dispose();
    for (final puff in [..._puffs, _bubble]) {
      puff.material?.map = null;
      puff.material?.dispose();
    }
    trail.dispose();
  }
}

/// The egg's profile turned on a lathe: fuller at the base, narrower at the
/// crown, standing [_eggAspect] times its radius high either way.
tjs.BufferGeometry _eggGeometry(double radius) {
  const steps = 22;
  final h = radius * _eggAspect;
  final points = <tjs.Vector2>[];
  for (var i = 0; i <= steps; i++) {
    final theta = i / steps * math.pi;
    final y = -math.cos(theta) * h;
    final r =
        math.max(radius * math.sin(theta) * (1 + 0.1 * math.cos(theta)), 0.0);
    points.add(tjs.Vector2(r, y));
  }
  return tjg.LatheGeometry(points, segments: 28);
}

/// The shells' paints, one per player colour and pattern, made once (the
/// first time an egg wears them) and shared by every egg of every world.
final Map<(int, EggPattern), tjs.DataTexture> _eggTextures = {};

tjs.DataTexture _eggTextureFor(int tint, EggPattern pattern) =>
    _eggTextures.putIfAbsent((tint, pattern), () => _eggTexture(tint, pattern));

/// The shell's paint: a pastel of the player's colour with fine speckles
/// (so whose egg it is reads from the overview too), [pattern] in the full
/// colour, its edges a shade deeper, and the face. u runs around the egg, v
/// from the base (0) to the crown (1); the face sits at u = 0 (the side
/// that looks at the camera on the tee), and every pattern keeps clear of
/// it.
tjs.DataTexture _eggTexture(int tint, EggPattern pattern) {
  const width = 256;
  const height = 128;
  final bitmap = _Bitmap(width, height);
  final rand = _Rand(tint);
  final shell = _mix(0xFFF8EE, tint, 0.25);
  final deep = _shade(tint, 0.78);
  final paint = [shell, tint, deep];
  for (var y = 0; y < height; y++) {
    final v = (y + 0.5) / height;
    for (var x = 0; x < width; x++) {
      final u = (x + 0.5) / width;
      var color = paint[_eggPatternAt(pattern, u, v)];
      // The face: two ink eyes with a glint, and a little yolk beak. In
      // surface units u runs about 6.3 radii around, v about 3.6 up.
      final su = u < 0.5 ? u : u - 1; // signed, the face at 0
      for (final side in const [-1.0, 1.0]) {
        final ex = (su - side * 0.05) * 6.3;
        final ey = (v - 0.725) * 3.6;
        if (ex * ex + ey * ey < 0.125 * 0.125) {
          color = 0x211614;
          final gx = ex - 0.045;
          final gy = ey - 0.045;
          if (gx * gx + gy * gy < 0.045 * 0.045) color = 0xFFFFFF;
        }
      }
      final beak = (v - 0.632) / 0.05; // 0 at the tip, 1 at its top
      if (beak >= 0 && beak <= 1 && su.abs() * 6.3 < 0.11 * beak) {
        color = 0xF89B17;
      }
      bitmap.set(x, y, color);
    }
  }
  // Speckles on the shell.
  for (var i = 0; i < 260; i++) {
    final x = rand.below(width);
    final y = rand.below(height);
    bitmap.blend(x, y, 0xC9B79E, 0.35);
  }
  return bitmap.texture();
}

/// What [pattern] paints at (u, v) of the shell: 0 the shell, 1 the
/// player's colour, 2 its deep shade (the edges).
int _eggPatternAt(EggPattern pattern, double u, double v) {
  switch (pattern) {
    case EggPattern.zigzag:
      return _zigzagAt(u, v);
    case EggPattern.stripes:
      // Bold rings, one wide at the waist with a pale line through it, and
      // a thin deep edge on every one.
      var paint = 0;
      for (final (low, high) in const [
        (0.08, 0.16),
        (0.25, 0.33),
        (0.42, 0.58),
        (0.85, 0.93),
      ]) {
        if (v > low && v < high) {
          return (v - 0.5).abs() < 0.014 ? 0 : 1;
        }
        if ((v - low).abs() < 0.02 || (v - high).abs() < 0.02) paint = 2;
      }
      return paint;
    case EggPattern.dots:
      // Polka dots on staggered rings, round on the shell (fewer toward
      // the ends, where the rings are short), none over the face.
      var paint = 0;
      final ring = _eggRingAt(v);
      for (var row = 0; row < 7; row++) {
        final rowV = 0.2 + row * 0.11;
        final dy = (v - rowV) * 3.9;
        if (dy.abs() > 0.24) continue;
        final count = math.max(5, (12 * _eggRingAt(rowV)).round());
        final offset = row.isOdd ? 0.5 : 0.0;
        final cell = u * count - offset;
        final nearest = cell.roundToDouble();
        final centre = ((nearest + offset) / count) % 1.0;
        final faceU = math.min(centre, 1 - centre) * 2 * math.pi * ring;
        if (rowV > 0.58 && rowV < 0.82 && faceU < 0.75) continue;
        final dx = (cell - nearest) / count * 2 * math.pi * ring;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d < 0.17) return 1;
        if (d < 0.21) paint = 2;
      }
      return paint;
    case EggPattern.hearts:
      // A ring of six hearts round the waist (one on the egg's chest,
      // under the face) between two thin lines.
      final shape = _ringShapeAt(u, v, count: 6, ringV: 0.47, inside: (x, y) {
        // The heart curve (x^2 + y^2 - 1)^3 = x^2 y^3, lobes up.
        final a = x * x + y * y - 1;
        return a * a * a - x * x * y * y * y <= 0;
      }, scale: 0.36, lift: 0.12);
      if (shape != 0) return shape;
      if ((v - 0.335).abs() < 0.009 || (v - 0.61).abs() < 0.009) return 1;
      return 0;
    case EggPattern.stars:
      // A ring of six stars round the waist, a dot between each.
      final shape = _ringShapeAt(u, v,
          count: 6,
          ringV: 0.47,
          inside: (x, y) => _insideStar(x, y),
          scale: 0.42);
      if (shape != 0) return shape;
      final between = _ringShapeAt(u, v,
          count: 6,
          ringV: 0.47,
          phase: 0.5,
          inside: (x, y) => x * x + y * y <= 1,
          scale: 0.07);
      return between == 0 ? 0 : 1;
    case EggPattern.waves:
      // A wavy band round the waist, a ripple under it and one near the
      // crown, over the face.
      final band = 0.48 + 0.045 * math.sin(u * 2 * math.pi * 6);
      final d = (v - band).abs();
      if (d < 0.075) return 1;
      if (d < 0.095) return 2;
      final low = 0.24 + 0.025 * math.sin(u * 2 * math.pi * 6 + math.pi);
      if ((v - low).abs() < 0.022) return 1;
      final high = 0.885 + 0.02 * math.sin(u * 2 * math.pi * 5 + math.pi);
      if ((v - high).abs() < 0.018) return 1;
      return 0;
  }
}

/// The classic band: zig-zag edged in the player's colour, a pale line
/// through it and deep edges, a ring of seven dots above (but over the
/// face) and below.
int _zigzagAt(double u, double v) {
  var paint = 0;
  final zig = ((u * 9) % 1.0 - 0.5).abs() * 2; // 0..1 triangle
  final top = 0.6 + zig * 0.05;
  final bottom = 0.42 - zig * 0.05;
  if (v > bottom && v < top) {
    paint = 1;
    if ((v - (bottom + top) / 2).abs() < 0.018) paint = 0;
  } else if ((v - bottom).abs() < 0.025 || (v - top).abs() < 0.025) {
    paint = 2;
  }
  final faceU = math.min(u, 1 - u); // distance round from the face
  // Dots above and below the band, a ring of seven each.
  for (final (row, size) in const [(0.75, 0.05), (0.27, 0.055)]) {
    if (row > 0.5 && faceU < 0.17) continue;
    const count = 7;
    final cell = ((u + 0.5 / count) * count) % 1.0 - 0.5;
    final du = cell / count * 3.2; // around the egg, in its height's units
    final dv = v - row;
    if (du * du + dv * dv < size * size) paint = 1;
  }
  return paint;
}

/// The shell's ring radius at height [v], in egg radii (the lathe's own
/// profile): how far round the egg a step of u goes there.
double _eggRingAt(double v) {
  final theta = v * math.pi;
  return math.sin(theta) * (1 + 0.1 * math.cos(theta));
}

/// [count] shapes round the shell on the ring at [ringV] (the first at
/// the face, or [phase] of a step past it), each the region [inside] holds
/// for in its own units ([scale] radii to one, y toward the crown, raised
/// by [lift] of them): 1 inside, 2 on the deep edge just outside, 0 off.
int _ringShapeAt(
  double u,
  double v, {
  required int count,
  required double ringV,
  required bool Function(double x, double y) inside,
  required double scale,
  double phase = 0,
  double lift = 0,
}) {
  final dy = (v - ringV) * 3.9;
  if (dy.abs() > scale * 1.6) return 0;
  final cell = u * count - phase;
  final nearest = cell.roundToDouble();
  final dx = (cell - nearest) / count * 2 * math.pi * _eggRingAt(v);
  final x = dx / scale;
  final y = dy / scale + lift;
  if (inside(x, y)) return 1;
  // The edge: the same shape a size up.
  return inside(x / 1.14, (y - lift) / 1.14 + lift) ? 2 : 0;
}

/// Whether (x, y) is inside a five-point star of outer radius 1, a point
/// up (y toward the crown).
bool _insideStar(double x, double y) {
  const inner = 0.44;
  final distance = math.sqrt(x * x + y * y);
  if (distance > 1) return false;
  if (distance < inner * math.cos(math.pi / 5)) return true;
  // Fold the angle (from the top point) into the first half-sector, where
  // the edge runs from the point (1, 0) to the inner corner.
  const sector = 2 * math.pi / 5;
  var angle = math.atan2(x, y) % sector;
  if (angle < 0) angle += sector;
  if (angle > sector / 2) angle = sector - angle;
  final cornerX = inner * math.cos(sector / 2);
  final cornerY = inner * math.sin(sector / 2);
  final edgeX = cornerX - 1;
  final edgeY = cornerY;
  // The ray at [angle] meets the edge at t: t * (cos, sin) = (1, 0) + s * edge.
  final reach = edgeY / (math.cos(angle) * edgeY - math.sin(angle) * edgeX);
  return distance <= reach;
}

/// Something that walks (or swims) a moving obstacle's path.
abstract class _Walker {
  tjs.Group get group;
  void sync(PuttWorldHen hen, double time);
}

/// Fades a figure out of the way (a hen walking into the camera's face,
/// the host behind the HUD): its materials are made transparent once, at
/// build, so a fade only moves a uniform and never recompiles a program.
/// Faded all the way, the figure is not drawn at all (it would still hide
/// what stands behind it in the depth buffer).
mixin _Fadable {
  final List<tjs.Material> _fadeMaterials = [];

  /// The parts that cast a shadow when solid: a fading figure lets its
  /// shadow go (a faded rooster's full shadow on the meadow read as a
  /// glitch).
  final List<tjs.Object3D> _fadeCasters = [];
  double _fade = 1;
  tjs.Object3D? _fadeRoot;

  /// The root's own scale, which the pop shrinks from.
  tjs.Vector3? _fadeScale;

  /// How long a figure takes to go, or to come back: a pop, not a ghost
  /// lingering half-seen.
  static const double _fadeSeconds = 0.15;

  /// The figure's own height scale (not shrunk by the pop).
  double get fadeBaseScaleY => _fadeScale?.y ?? 1;

  void _prepareFade(tjs.Object3D root) {
    _fadeRoot = root;
    _fadeScale = root.scale.clone();
    root.traverse((object) {
      if (object.castShadow) _fadeCasters.add(object);
      final material = object.material;
      if (material == null || _fadeMaterials.contains(material)) return;
      material.transparent = true;
      _fadeMaterials.add(material);
    });
  }

  /// Goes toward [target] (1 solid, 0 gone) in [_fadeSeconds], shrinking
  /// a little toward its feet as it goes.
  void fadeToward(double target, double dt) {
    if (_fade == target) return;
    final step = dt / _fadeSeconds;
    _fade = target > _fade
        ? math.min(target, _fade + step)
        : math.max(target, _fade - step);
    for (final material in _fadeMaterials) {
      material.opacity = _fade;
    }
    final solid = _fade >= 0.9;
    for (final caster in _fadeCasters) {
      caster.castShadow = solid;
    }
    final root = _fadeRoot;
    if (root == null) return;
    root.visible = _fade > 0.02;
    final base = _fadeScale;
    if (base != null) {
      final k = 0.6 + 0.4 * _fade;
      root.scale.setValues(base.x * k, base.y * k, base.z * k);
    }
  }
}

/// The host's two builds: in full for when he stands tall on the screen
/// (the opening shot, a close-up), light - the same shapes in fewer facets,
/// under half the vertices - while he stands small beyond the fence, as he
/// mostly does. Each part's two builds hang from the same pivots, so his
/// breath, his head's turns and his wings' flaps move both.
class _HostDetail {
  _HostDetail(tjs.Object3D host) {
    host.traverse((object) {
      if (object is! tjs.Mesh) return;
      final name = object.name;
      if (name.endsWith('-outline')) return;
      if (_parts.contains(name)) _full.add(object);
      if (name.endsWith('-light') &&
          _parts.contains(name.substring(0, name.length - 6))) {
        _light.add(object);
      }
    });
  }

  static const Set<String> _parts = {
    'host-body',
    'host-wing-feathers',
    'host-face',
  };

  final List<tjs.Object3D> _full = [];
  final List<tjs.Object3D> _light = [];
  bool _inFull = true;

  /// Whether his full build is the one drawn.
  bool get inFull => _inFull;

  /// How tall, in pixels, he stands on the screen now: in full past 260,
  /// light under 220 (the slack between keeps him from flickering).
  void standing(double pixels) {
    final full = _inFull ? pixels > 220 : pixels > 260;
    if (full == _inFull) return;
    _inFull = full;
    for (final mesh in _full) {
      mesh.visible = full;
    }
    for (final mesh in _light) {
      mesh.visible = !full;
    }
  }
}

/// A duck where the obstacle paddles over water (the Pond's ducks): a
/// mallard sitting low in the water - brown body, green head over a white
/// collar, a yolk bill, a blue patch on the wing - bobbing as it goes, a
/// wake round it.
class _DuckView3D implements _Walker {
  _DuckView3D(MovingObstacle obstacle) {
    final r = obstacle.radius;
    group = tjs.Group()..name = 'duck/${obstacle.id}';
    _body = tjs.Group()..name = 'duck-body';
    final ink = _hexOf(PuttPalette.ink);
    final yolk = _hexOf(PuttPalette.yolk);
    final shape = _Merged()
      ..add(
          tjs.SphereGeometry(1, 20, 14),
          _place(0, r * 0.32, -r * 0.05,
              sx: r * 0.66, sy: r * 0.42, sz: r * 1.0),
          0x8A6A4A,
          baseShade: 0.7)
      ..add(
          tjs.SphereGeometry(1, 16, 12),
          _place(0, r * 0.3, r * 0.42, sx: r * 0.5, sy: r * 0.36, sz: r * 0.42),
          0xC9B79A)
      ..add(tjg.ConeGeometry(r * 0.3, r * 0.55, 8),
          _place(0, r * 0.42, -r * 1.0, tilt: -math.pi / 2 - 0.35), 0x5E4630);
    for (final side in [-1.0, 1.0]) {
      shape
        ..add(
            tjs.SphereGeometry(1, 12, 8),
            _place(side * r * 0.5, r * 0.42, -r * 0.12,
                sx: r * 0.2, sy: r * 0.24, sz: r * 0.7),
            0x6E5236)
        ..add(tjs.BoxGeometry(r * 0.05, r * 0.12, r * 0.3),
            _place(side * r * 0.69, r * 0.44, -r * 0.3), 0x3B5BDB);
    }
    shape
      ..add(tjg.TorusGeometry(r * 0.27, r * 0.05, 6, 20),
          _place(0, r * 0.72, r * 0.5, tilt: math.pi / 2 - 0.3), 0xFCF8F1)
      ..add(tjs.SphereGeometry(r * 0.34, 16, 12), _place(0, r * 0.98, r * 0.62),
          0x2E6B3C)
      ..add(tjs.BoxGeometry(r * 0.26, r * 0.08, r * 0.36),
          _place(0, r * 0.9, r * 1.02), yolk);
    for (final side in [-1.0, 1.0]) {
      shape.add(tjs.SphereGeometry(r * 0.055, 8, 6),
          _place(side * r * 0.24, r * 1.06, r * 0.82), ink);
    }
    final duckShape = shape.mesh('duck-shape', flat: false, roughness: 0.6)!;
    _inkOutline(duckShape, r * 0.05);
    _body.add(duckShape);
    group.add(_body);
    _wake = tjs.Mesh(
      tjg.RingGeometry(r * 1.05, r * 1.3, 32, 1),
      _unlit(0xFFFFFF, opacity: 0.35, depthWrite: false),
    )
      ..name = 'duck-wake'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.06
      ..renderOrder = 3;
    group.add(_wake);
    group.traverse((object) {
      if (object.name != 'duck-wake' && !object.name.endsWith('-outline')) {
        object.castShadow = true;
      }
    });
  }

  @override
  late final tjs.Group group;
  late final tjs.Group _body;
  late final tjs.Mesh _wake;
  Vec2 _heading = const Vec2(0, 1);

  @override
  void sync(PuttWorldHen hen, double time) {
    if (hen.heading.length > 1e-4) {
      _heading = hen.heading.normalized(_heading);
    }
    group.rotation.y = math.atan2(_heading.x, _heading.y);
    // Sitting low in the water, bobbing, rocking a little as it paddles.
    _body.position.y = -0.12 + math.sin(time * 2.2 + hen.position.x) * 0.05;
    _body.rotation.z = math.sin(time * 3.1) * 0.05;
    final swell = 1 + math.sin(time * 2.6) * 0.06;
    _wake.scale.setValues(swell, swell, 1);
    group.position.setValues(hen.position.x, 0, hen.position.y);
  }
}

/// A hen where the obstacle walks (built in `world3d/birds.dart`): plump
/// and white, her wings' feathers cut along the edge, a small cream tail,
/// a little comb and wattle, and two scaly legs that step with her walk.
class _HenView3D with _Fadable implements _Walker {
  _HenView3D(MovingObstacle obstacle, [_Ground? terrain])
      : _terrain = terrain ?? _Ground(),
        _r = obstacle.radius {
    final r = _r;
    group = tjs.Group()..name = 'hen/${obstacle.id}';
    // The body rides the bob and the waddle; forward is local +z.
    _body = tjs.Group()..name = 'hen-body';
    final shape = _Merged();
    _henBody(shape, tjs.Matrix4(), r);
    final henShape = shape.mesh('hen-shape', flat: false, roughness: 0.8)!;
    _inkOutline(henShape, r * 0.05);
    _body.add(henShape);
    _head = tjs.Group()
      ..name = 'hen-head'
      ..position.setValues(0, r * _henHeadY, r * _henHeadZ);
    final face = _Merged();
    _henHead(face, tjs.Matrix4(), r);
    final henFace = face.mesh('hen-face', flat: false, roughness: 0.7)!;
    _inkOutline(henFace, r * 0.05);
    _head.add(henFace);
    _body.add(_head);
    group.add(_body);
    // Each leg on its own hip, so it steps: drumstick, scaly shank, toes,
    // inked thinner than her body.
    for (final side in [-1.0, 1.0]) {
      final hip = tjs.Group()
        ..name = 'hen-leg'
        ..position.setValues(side * r * 0.32, r * _henHip, 0);
      final leg = _Merged();
      _henLeg(leg, tjs.Matrix4(), r, side);
      final foot = leg.mesh('hen-foot', flat: false, roughness: 0.6)!;
      _depths.add(_depthsBySwing(foot.geometry!));
      _inkOutline(foot, r * 0.025);
      hip.add(foot);
      _legs.add(hip);
      group.add(hip);
    }
    group.traverse((object) {
      if (!object.name.endsWith('-outline')) object.castShadow = true;
    });
    _prepareFade(group);
  }

  @override
  late final tjs.Group group;
  late final tjs.Group _body;
  late final tjs.Group _head;
  final List<tjs.Group> _legs = [];
  final double _r;

  /// For each leg, how deep under its hip its lowest point hangs, swung
  /// to each angle of the table ([_depthAt] reads it).
  final List<List<double>> _depths = [];

  /// The table's swings: from -0.7 radians, a twentieth apart.
  static const double _swingFrom = -0.7;
  static const double _swingStep = 0.05;
  static const int _swings = 29;

  /// The leg [geometry]'s depth under its hip at each swing of the table
  /// (turned about the hip's x, forward +z), read off its own vertices: a
  /// planted foot stands right on the ground, on its claws or its heel.
  static List<double> _depthsBySwing(tjs.BufferGeometry geometry) {
    final position = geometry.attributes['position'] as tjs.BufferAttribute;
    final depths = <double>[];
    for (var k = 0; k < _swings; k++) {
      final angle = _swingFrom + k * _swingStep;
      final c = math.cos(angle);
      final s = math.sin(angle);
      var deepest = 0.0;
      for (var i = 0; i < position.count; i++) {
        final y = position.getY(i)!.toDouble();
        final z = position.getZ(i)!.toDouble();
        deepest = math.max(deepest, z * s - y * c);
      }
      depths.add(deepest);
    }
    return depths;
  }

  /// How deep under its hip leg [leg] reaches, swung to [angle].
  double _depthAt(int leg, double angle) {
    final depths = _depths[leg];
    final at = ((angle - _swingFrom) / _swingStep).clamp(0.0, _swings - 1.0);
    final i = math.min(at.floor(), _swings - 2);
    return depths[i] + (depths[i + 1] - depths[i]) * (at - i);
  }

  Vec2 _heading = const Vec2(0, 1);
  Vec2? _last;

  /// How far a leg swings either way of straight down while she walks.
  static const double _stride = 0.5;

  /// The stand and the facing (the last non-stop direction she had), and
  /// the walk: each leg swings ahead with its foot lifted and back with it
  /// planted, the planted foot kept to the ground (on its toes as it
  /// leans back, on its heel as it reaches ahead); her body bobs and rocks
  /// from foot to foot and her head bobs with her steps.
  @override
  void sync(PuttWorldHen hen, double time) {
    if (hen.heading.length > 1e-4) {
      _heading = hen.heading.normalized(_heading);
    }
    // Local +z turned onto the heading.
    group.rotation.y = math.atan2(_heading.x, _heading.y);
    final moved = _last == null ? 0.0 : _last!.distanceTo(hen.position);
    _last = hen.position;
    final walking = moved > 1e-4;
    final step = hen.phase * 0.9;
    final swing = walking ? math.sin(step) : 0.0;
    // Above 0, the first leg is the one swinging ahead.
    final ahead = walking ? -math.cos(step) : 0.0;
    for (var i = 0; i < _legs.length; i++) {
      final sign = i == 0 ? 1.0 : -1.0;
      final angle = sign * swing * _stride;
      final lift = math.max(0.0, sign * ahead) * _r * 0.12;
      _legs[i]
        ..rotation.x = angle
        ..position.y = _depthAt(i, angle) + lift;
    }
    final bob = walking ? math.sin(hen.phase * 1.8).abs() * 0.08 : 0.0;
    _body.position.y = bob;
    _body.rotation.z = walking ? math.cos(step) * 0.06 : 0.0;
    // Pecking now and then while she stands.
    final peck = walking ? 0.0 : math.max(0.0, math.sin(time * 2.2)) * 0.5;
    _head
      ..rotation.x = peck
      ..position.z =
          _r * _henHeadZ + (walking ? math.sin(step * 2) * _r * 0.05 : 0);
    group.position
        .setValues(hen.position.x, _terrain.at(hen.position), hen.position.y);
  }

  final _Ground _terrain;
}

/// The "?" crate: a yolk carton floating over its glow, turning slowly,
/// until its id lands in the frame's collected set.
class _CrateView3D {
  _CrateView3D(this.box, tjs.DataTexture texture, {double floor = 0}) {
    final size = box.radius * 1.35;
    group = tjs.Group()
      ..name = 'crate/${box.id}'
      ..position.setValues(box.position.x, floor, box.position.y);
    _spin = tjs.Group()..name = 'crate-spin';
    final body = tjs.Mesh(
      tjs.BoxGeometry(size, size, size),
      tjs.MeshStandardMaterial({
        tjs.MaterialProperty.map: texture,
        tjs.MaterialProperty.roughness: 0.5,
        tjs.MaterialProperty.metalness: 0.0,
        tjs.MaterialProperty.emissive: _lin(0x3C2400),
      }),
    )
      ..name = 'crate-body'
      ..castShadow = true;
    _spin.add(body);
    _hover = size * 0.5 + 0.45;
    _spin.position.y = _hover;
    _glow = tjs.Mesh(
      tjg.CircleGeometry(radius: box.radius * 1.35, segments: 28),
      tjs.MeshBasicMaterial({
        tjs.MaterialProperty.map: _EggView3D._shadowTexture,
        tjs.MaterialProperty.color: _lin(_hexOf(PuttPalette.yolk)),
        tjs.MaterialProperty.transparent: true,
        tjs.MaterialProperty.opacity: 0.6,
        tjs.MaterialProperty.depthWrite: false,
        tjs.MaterialProperty.blending: tjs.AdditiveBlending,
      }),
    )
      ..name = 'crate-glow'
      ..rotation.x = -math.pi / 2
      ..position.y = 0.04
      ..renderOrder = 2;
    group
      ..add(_spin)
      ..add(_glow);
  }

  final QuestionBox box;
  late final tjs.Group group;
  late final tjs.Group _spin;
  late final tjs.Mesh _glow;
  late final double _hover;

  /// A per-crate offset so two cartons never breathe in sync (never
  /// changes for a crate's life, computed once).
  late final double bobPhase = () {
    var phase = 0.0;
    for (final code in box.id.codeUnits) {
      phase = (phase + code) % 17;
    }
    return phase;
  }();

  String get id => box.id;

  /// Seconds since the crate was taken (the pop plays), or null while it
  /// stands.
  double? _poppedAt;

  void sync({required bool visible, required double time}) {
    if (!visible) {
      // Taken: a quick swell and spin, then gone.
      final start = _poppedAt ??= time;
      final t = ((time - start) / 0.28).clamp(0.0, 1.0);
      group.visible = t < 1;
      if (t < 1) {
        final swell = 1 + t * 0.7;
        _spin
          ..scale.setValues(
              swell * (1 - t), swell * (1 - t) + 0.001, swell * (1 - t))
          ..rotation.y += 0.35
          ..position.y = _hover + t * 1.2;
        _glow.material?.opacity = 0.6 * (1 - t);
      }
      return;
    }
    if (_poppedAt != null) {
      _poppedAt = null;
      _spin.scale.setValues(1, 1, 1);
    }
    group.visible = true;
    final breathe = math.sin(time * 2.4 + bobPhase);
    _spin.position.y = _hover + breathe * 0.14;
    _spin.rotation.y = time * 0.9 + bobPhase;
    _spin.rotation.x = math.sin(time * 1.3 + bobPhase) * 0.08;
    _glow.material?.opacity = 0.42 + 0.22 * (0.5 + 0.5 * breathe);
  }
}
