# Sunny Side Putt

The first call activity: a minigolf whose balls are EGGS and whose
holes are NESTS, on a farm, with power-ups. Inspired by Discord's Putt
Party — the numbers follow it; the identity is the Rooster's own.

![the eggs on the tee: name tags, the viewer's pin and ring](images/sunny-side-putt/01-the-egg-on-the-tee.jpg)
![aiming: the arrow and the dotted guide toward the bumper crown](images/sunny-side-putt/02-aiming-the-putt.jpg)

In play:

![a hole in one: the egg hatches in the nest](images/sunny-side-putt/05-in-the-nest.jpg)
![the hole's results](images/sunny-side-putt/06-hole-end.jpg)

A short gameplay clip (the coach, the aim, the roll, the hatch, the
results):

[putt-sunny-side-putt-3d.mp4](images/sunny-side-putt/putt-sunny-side-putt-3d.mp4)

## The game

- A course is 6 holes; a match seats 1-8 players (the ninth onward
  watches from the fence). Strokes are simultaneous: everyone lines up
  their putt when they like, and the hole ends when every egg is in or
  the 2-minute clock runs out (warning sounds on the last fifteen
  seconds).
- Out of time: the hole scores max(strokes taken, par + 2). Putt
  Party's exact rule is not documented anywhere we could verify; this
  is ours, and it punishes stalling without ending a comeback.
- Aiming is a slingshot drag, and the putt goes exactly where the arrow
  points at release; the engine adds no hidden error. A soft putt (under
  40% power) or a quick one (released within 0.8 seconds) holds still; a
  hard pull held longer starts to sway, up to 2 degrees either side at
  full power, so on a long putt the timing of the release is the skill.
  The Hawk Eye power-up holds the arrow still.
- After each hole the results card stays up for 8 seconds in a live
  session (Continue counts the seconds down while a band sweeps across
  it), then the match moves on by itself; the host's Continue moves on at
  once. The pause runs on the engine's ticks like a hole's clock (every
  client keeps ticking through it), and rides the engine's snapshot, so a
  host handoff keeps it.
- Quick reactions: a cheer, a laugh, a wow, fire or a nice one, from the
  button under the pause button or the keys 1-5, pop as a bubble over the
  sender's egg for everyone (over the nest once their egg is in). They
  ride the engine's journal as `ReactInput`s and change nothing in the
  game; the button keeps a short cooldown (`putt_reactions.dart`).
- Mid-join: entering now puts you on the current hole's tee; the holes
  you missed score par.
- Eggs waiting to putt are ghosts: until an egg has putted on the hole,
  the others pass through it and it through them, so nobody's first putt
  (nor a cast's push) knocks a waiting egg off the tee. Two that met
  while one was a ghost go on passing through until they part, rather
  than spring apart when it putts; two at rest inside each other roll
  just clear (a putted egg out of a waiting one, which stays put; two
  waiting ones half each; never into water, and a pair at most four times
  a hole). All of it rides the world's snapshot. An egg at rest that
  another rolls into hears who did it in the cast feed ("Jonas knocked
  your egg!", or "You knocked Lou's egg").

### Modes

- **Casual** - one course, then the group votes the next.
- **Tournament** - 3, 6 or 9 drawn courses; the scores add up and
  power-ups travel with you.
- **Barnyard Chaos** - casual, but everyone starts with two random
  power-ups and the mystery boxes come doubled.

### Looks

Each player picks the Easter band on their egg and a hat for the chick
that hatches from it, in "Your egg" off the pause menu: the egg and the
chick drawn as the green shows them, a row of patterns, a row of hats. The
colour is not part of it: it comes with the seat, so eight eggs never
share one. The pick is kept on the device like the volumes (the
`putt_egg_look` preference, `pattern/hat`) and worn in every match after;
one made mid-match goes on at once, with a puff on the egg.

- Patterns: zigzag (the classic band with its rings of dots, the
  default), stripes, dots (polka dots all over), hearts and stars (a ring
  round the waist), waves.
- Hats: none (the default), a straw hat with a red band, a red bow, a
  little gold crown, headphones like the host's, a daisy over one eye.

Everyone sees it: the pattern on the egg on the green, the hat on the
chick at the sink, and both on the little egg by the name on the tags, the
scorecard, the results cards and the player picker (`putt_look.dart` draws
them flat, the world in 3D).

A look is the player's state in the engine (`PuttLook` in `core/look.dart`,
`PuttPlayer.look`): the join brings it (the host's own at launch), a
`LookInput` changes it in any phase, the player's snapshot keeps it and the
journal replays it on a handoff. Nothing in the rules or the physics reads
it. A host seats its guests knowing no look, so a guest's match asks the
host for its own whenever the engine has it otherwise (a new seat, a fresh
pick, a snapshot from before it): worn at home at once like a shot, through
the host for everyone, three asks at most, a few seconds apart, so a host
that never takes it is not pestered. A snapshot from before looks and a
name only a newer version knows read as the default, and a move of a kind
the client does not know is dropped (the next snapshot carries what it
did).

### Power-ups

Earned at the "?" boxes (a maximum of 3 in hand; extras discarded), and
**the one who casts never suffers their own bad effects** - the wind
spares their egg, the sprinkler waters around it. A power-up that lands
in the carton says its name above its slot for a couple of seconds (the
tooltip, on hover, says what it does).

| Power-up | Does |
|---|---|
| Hawk Eye | removes the aim wobble on your next shot |
| Nest Magnet | the egg is drawn home when it nears the nest |
| Ghost Egg | passes through fences and obstacles briefly |
| Chicken Hop | your next putt flies over whatever is in the way |
| Rabbit Hole | teleports your egg a short way, costing no stroke |
| Gust | a wind of your choosing pushes every egg but yours |
| Thick Shell | shield: the next negative effect bounces off, a Thieving Crow or a Nest Swap aimed at the egg included |
| Strong Coffee | your next shot leaves 30% harder |
| Nest Swap | trade places with a chosen player's egg |
| Sprinkler | mark a spot; nearby eggs are pushed away |
| Corn Rain | kernels bounce around, nudging every egg but yours |
| Thieving Crow | steal a power-up from a chosen player |

Using one: a tap on its slot casts the ones that need nothing. One that
acts on a spot (Rabbit Hole, Gust, Sprinkler) waits for it: the slot
glows, the green shows what it would reach (the hop's range and landing,
the spray and the eggs it soaks, the pull on every other egg), and the
next press on the green casts it there; Esc, a right click, pausing or
the slot tapped again puts it away. One that acts on a player (Nest
Swap, Thieving Crow) opens a list of the players it can reach, and says
so when nobody can be picked. Nothing is spent on a cancel, or on a cast
that could do nothing (no other egg to push, my egg already in the
nest). The targeting lives in `putt_targeting.dart`, the reticle in
`putt_reticle.dart`.

#### What everyone sees

Every cast is everyone's, so an egg never jolts and a power-up never
vanishes without its cause on screen:

- **The call.** A toast under the top bar (`putt_cast_feed.dart`), clear
  of the green's middle: the caster's picture (or colour dot), the
  power-up's icon and a short line - "Lou: Corn Rain", "You: Gust",
  "Maya stole your Gust!", "You stole Maya's Gust!", "Maya swapped places
  with you!", "Jonas's shell blocked Lou's Corn Rain", "Your shell blocked
  Maya's Thieving Crow!" (a theft or a swap a shell stops says so in its
  own toast, at once). Its
  edge says how it sits with the viewer: comb red when they were robbed
  or swapped, yolk for their own, the caster's colour otherwise. Calls
  queue: a run of casts reads one after another, a toast hurrying on
  once read when others wait (a cast and the shells that held against it
  come in that order).
- **The sound.** The cast's chime for everyone, plus the scene's own: the
  corn's patter, the gust's wind, the sprinkler's splash, the swap's and
  the rabbit hole's zap, the crow's caw on a theft, a pop and a ting when
  a shell holds (`tools/gen_game_audio.dart` synthesizes them all).
- **The burst.** Sparkles and a ring in the power-up's colour at the
  caster's egg, where it stood as it cast.
- **The scene,** on the green, for everyone:

| Power-up | Everyone sees |
|---|---|
| Hawk Eye | on the putt, glints light up one after another along its dead-straight line, ahead of the egg |
| Nest Magnet | a ring breathing round the nest in the egg's colour, rings drawn in toward it and glints running round, while the magnet waits or pulls |
| Ghost Egg | the egg goes see-through and flickers while it lasts, blinking back to solid at the end, pale wisps rising off it; its shadow thins |
| Chicken Hop | feathers puff off the egg as it takes off, then the hop lifts it over what stands in the way |
| Rabbit Hole | a puff and dirt where the egg goes down, dirt, sparkles and a ring where it comes up |
| Gust | wind streaks converging on the chosen spot, and streaks running behind every egg it pushes |
| Thick Shell | a soap bubble round the egg while the shield holds; a cast it stops pops it in a ring and shards |
| Strong Coffee | wisps of steam off the egg while the coffee waits, a trail of steam behind its boosted putt |
| Nest Swap | a poof, a violet ring and a swirl on both eggs as they trade places, and a dotted line lighting up between their spots |
| Sprinkler | the splash and its rings at the spot, spray on every egg it soaks |
| Corn Rain | kernels falling out of the sky round every egg it nudges, bouncing twice and lying a moment |
| Thieving Crow | a black crow swoops onto the robbed egg, flies an arc to the thief's with the stolen power-up's icon in its beak, and drops it in |

The engine says what each cast did: `PowerUpUsed` carries the target and
the caster's spot, `PowerUpStolen` the theft, `ShieldBlocked` a shell
that held, `PowerUpHit` the eggs it moved, and `ShotApplied` the
next-shot power-ups riding the putt (`core/rules.dart`); the shell, the
ghost and the magnet are read off the engine every frame. The match turns
the events into calls, sounds and fx spots (`putt_match.dart`); the game
into particles and the crows' flights (`sunny_side_putt_game.dart`); the
world draws them (`world3d/casts.dart` for the crow and the magnet, the
eggs for the bubble and the ghost, the fx pool for the particles). The
crows and the shimmer are built once and pooled, every particle rides a
pool of its own texture (no material ever changes its map), the eggs'
materials are transparent from the start so a ghost only moves an
opacity, and a new hole clears it all.

### Courses

Five launch courses, six holes each, themselves teaching their
gimmicks: the Coop (a hen walks the floor and bumps eggs), the Corn
Maze (rabbit holes as speed-preserving portals), the Pond (water
returns the egg, stroke charged), Farm Road (speed strips) and the
Barn (hay bales, the silo's pull).

Tiers (see below) stack nine holes on more than one level, at least one
on every course:

- **The Coop**: First Light's tee yard is the coop's raised floor; the
  putt drops off its step through the door into the run, and an egg the
  hen knocks back meets the step's face and stays in the run. Feeding
  Time's top lane is the hayloft, the nest on it and its edge railed by
  the middle board: up the ladder, a narrow ramp through the gap in the
  board that takes a firm, straight putt, or the long way round the far
  bend, whose kickers throw the egg up the wide ramp at the loft's end.
  Nesting Boxes' boxes stand up on the roost along the back wall (see
  Kickers below).
- **Corn Maze**: Grand Maze's north road climbs a ramp at its far end
  onto a lookout over the nest's garden; a hedge in its corner turns an
  egg that comes up with pace off the lookout's edge, down into the
  garden toward the nest. Short of the climb rolls back down the road.
- **The Pond**: Island Green's last leg is a stone pier raised over the
  water, up a ramp from the elbow and dropping onto the island by the
  nest. Too soft rolls back to the elbow, off the pier's side swims, too
  hard drops off the end, runs past the nest and swims.
- **Farm Road**: Front Stretch's road runs on a bank with a ditch across
  it past the speed strip, a drop into it and a ramp out the far side.
  The strip's pace carries an egg through and up; one that misses the
  strip drops in and needs a firm putt to climb out. Home Stretch's
  middle stretch is a flyover: the climb up out of the first hairpin
  takes a firm putt (one short of it rolls back into the bend), and the
  flyover's strip throws the egg off its far end into the second
  hairpin, which an egg cannot climb back out of.
- **The Barn**: Threshing Floor's nest is up in the hayloft, a terrace in
  the far corner walled with rubber on the west, its front a drop to the
  floor with a railed ramp up it behind a bale. Short up the ramp rolls
  back down; long past the nest comes back off the barn's wall and drops
  off the loft's front or down the ramp. Hay Bale Pinball's nest is up on
  the threshing deck at the far end, a drop to the floor all along its
  edge but for the railed ramp between the bumpers: the alley through the
  bales has to line up with it and come with pace.

Hills (see below) shape nine of the thirty holes:

- **The Coop**: a hump of packed earth across Pop Hole's far lane
  guards the nest from the safe road (the tunnel's line passes it by),
  and a dust-bath mound on Pinball Parlor's straight line throws a putt
  aimed at the crown off its line.
- **Corn Maze**: First Furrow's spur is dug into a trough that steers a
  straight putt into the rabbit hole, and Crossroads' garden dips round
  the nest, gathering an egg out of the rabbit hole that is a little
  short or long.
- **The Pond**: the Weir's far bank dishes gently down to the nest, Duck
  Walk's nest sits on a green raised at the end of the causeway, and
  Frog Pond's island rises to its nest.
- **Farm Road**: a speed bump on the Roundabout's road out turns back an
  egg that leaves the ring short of pace, and two more stand in Home
  Stretch's top lane before the farm gate.

Kickers (see below) throw the egg into the air on five holes, one per
course, each the bold line beside a longer, safer one:

- **The Coop**: Nesting Boxes' four boxes stand up on the roost along the
  back wall, its front a drop to the yard, the nest in the second box and
  a hen pacing the roost before them. Straight up from the tee, a plank
  kicker throws a firm putt over the roost's edge and the hen into the
  third box (the "?"), a putt from the nest; a soft one bumps over it into
  the roost's face, one too firm comes back off the wall and drops off the
  roost again. The long way is up the ladder at the roost's east end,
  round the feed trough that stands across the way to it.
- **Corn Maze**: Hedge Hop's garden lies across the corn from the tee,
  behind a hedge with a muddy ditch in its gap. A dirt kicker right under
  the gap hops a firm, straight putt over the ditch into the garden, a putt
  from the nest at its west end; soft drops in the ditch, crooked meets the
  corn, and too firm comes back off the garden's far rail all the way into
  the ditch. The long way runs east along the corridor, up its open end and
  back west through the garden.
- **The Pond**: Lily Pad Lane's pond has no causeway: a stone jetty runs
  out into the lilies straight at the nest, a stone kicker at its end. A
  firm, straight putt flies the rest of the pond onto the far bank and runs
  on to the nest, or back to it off the far rail; a soft one rolls off the
  lip into the lilies, a crooked one off the jetty's side. Round the banks
  is the safe two.
- **Farm Road**: Cattle Grid's dirt ramp before the first conveyor throws a
  firm, straight putt over its push and through the first grid; a very
  firm one carries on through the second grid too, which now stands a
  little south of the first, toward the nest's corner. A soft one only
  bumps over the ramp onto the conveyor, and the grids are aimed off as
  before.
- **The Barn**: Twin Silos' hay kicker in the chute's mouth flies a firm,
  straight putt over the chute, clear of both pulls, onto the far side to
  run on to the nest; a soft one only hops into the chute, where the silos
  have it if it strays (the "?" in the chute is for whoever rolls it), and
  one too firm runs on past the nest into the water trough behind it.

### Hills

A hole can carry hills (`Hill` in `core/hole.dart`): mounds, ridges,
dips and troughs, round a point or along a line, with a flat top for a
plateau. The profile is `height * (1 - u^2)^2` across the slope, level
at both edges, so there is never a kink. The physics stays planar: an
egg feels `slopeGravity` (24) times the grade downhill. A pull stronger
than the rolling friction (7) rolls an under-hit egg back down; a
ridge has to be putted over with pace; a dip gathers eggs toward its
bottom. An egg pressed into a rail by a slope settles there instead of
rattling. Since there is no height in the physics, a hill's reach must
stay clear of walls, water, the tee and the nest's rim, unless its
plateau carries the nest. The course test checks every hill for this:
0.3 units off every rail, rock, pond, speed strip, rabbit hole, "?"
box, silo and spawn spot, and the nest either half a unit past the
skirt or on the plateau with 0.6 units of flat round its rim. A
reference putt up to a raised nest passes the climb to the course
kit's `putt` as `rise`. The aim's guide runs the same physics, so it
bends with the slope.

### Tiers

A hole can stand on more than one level (`Terrace` and `Ramp` in
`core/hole.dart`). A terrace is a polygon raised flat to its height (0.5
to 1.6 units), wound counter-clockwise as drawn; a ramp is a rectangle
from a foot on the green's level to a top on a terrace's edge, rising
along its axis on a smooth step (`height * t^2 * (3 - 2t)`, level at both
ends) and level across. The ground's height takes the highest tier under
a point; a ramp's gradient joins the hills' in the slope pull, so an egg
too slow for the climb rolls back down (near a ramp's ends, where the
pull is under the rolling friction, it can rest).

The physics stays planar: what a step does comes from what covers its
edges. A drop is a `WallSegment.ledge`, a one-way edge whose high side is
the left of its run as drawn (the terrace's own outline direction). An
egg rolling over its lip passes and falls - the physics carries it off at
least `ledgeDropSpeed` (3.2) away from the face, so it never rests inside
the step - and one coming from below bounces off the face like a rail.
Only the low face collides, and only for an egg heading up into it; the
face pushes out an egg below it that is not on its way out; an egg
pressed into it by a slope rests there, and one on the high side hangs
over the lip. Eggs a step apart (one on a lip, one at the face's foot)
pass over and under each other. Ordinary rails cover a terrace's railed
sides and a ramp's sides; the reach flood fill crosses ledges, both
levels being the course. A reference putt up a ramp passes the climb to
the course kit's `putt` as `rise`; a drop gives no pace back.

The course test checks every tier: each terrace edge covered by a ledge
(the terrace on its high side), a rail, a ramp's top of its height or the
fence; a ramp's sides railed or ledged, its foot on the green's level, its
top on a terrace's edge, its steepest grade 0.6 at most; ledges along
tier edges, high side up all along. Ponds, rabbit holes and silos keep
0.3 units off every tier; a speed strip or a "?" box stands on a
terrace's flat with 0.3 of room or keeps off; a rock or a bumper stands
wholly on one level (off the tiers, or on a terrace's flat, where it may
stand against a step's face), never across a step; hills keep their reach
0.3 off; the tee, a full table's spawn ring and every hen's walk stay on one
level, an egg's radius and 0.3 clear of every tier's outline; the nest
sits on a terrace with 0.6 of flat round its rim or half a unit clear.

### Kickers

A kicker (`Kicker` in `core/hole.dart`) is a short launch ramp on the
green: a deck from its foot to its lip, a width, the lip's height, a speed
threshold and a pitch, the launch angle as rise over run (0.5 is about 27
degrees). The physics reads only the lip. An egg whose centre crosses it
the way the kicker throws, at the threshold or faster along it, leaves
the ground: off the lip's height, its ground speed kept, climbing at its
pace along the kicker times the pitch - capped at 6.6 units/s, about 1.2
units over the lip at the top of the arc, so a harder putt only flies
farther - under 18 units/s^2, the view's own fall. A slower egg rolls over
the lip, a small bump that keeps 0.88 of its pace, and so does one
crossing it the other way; past the deck's sides nothing happens. The
flight runs a tick at a time on + - * / alone, so every platform flies
the same arc.

In the air (`BallBody.air`, the altitude of its lowest point, and
`airSpeed`, its climb) nothing on the ground pulls or rubs the egg: no
friction, no slope, no silo, no magnet. It passes over the water, the
speed strips, the rabbit holes, the "?" crates, the silos, the hens, the
other eggs and the nest, and over any step whose top it clears, so a
kicker can throw an egg up onto a terrace over its ledge; below the top
it meets the face like a rail. It never passes a rail, a rock, a bumper
or the fence, however high it flies. It comes down on the ground under
it (a terrace's top, a hill's slope) keeping 0.9 of its ground speed; a
hard landing gives 0.3 of its fall's speed back as a bounce, one little
hop more, and a touchdown in the pond swims, bounce or not. A Rabbit Hole
or a Nest Swap puts a flying egg on the ground; a Gust or a Sprinkler
moves it in the air without drowning it over the water. The flight rides
the snapshot (`air`, `vz`) and replays from the journal like everything
else, and the world echoes `BallLaunched`, `BallLanded` and `BallBumped`
for the sounds and the bursts.

The course test checks every kicker: its shape in range (height 0.3 to
0.6, pitch 0.3 to 0.8, threshold 5 to 12, width 2 to 4, length 1.5 to 3,
a deck that never bulges); its deck on one level, on dry turf inside the
bounds, 0.3 off every rail, rock, pond, hill, step, ramp, speed strip,
rabbit hole, "?" box and silo's reach, off the nest's rim, a full table's
spawn ring and every hen's walk; a run-up two units before its foot that
an egg can roll to from the tee (stopped by rails and water, carried
through the rabbit holes, down a ledge but never up one), with a straight
run up the deck; and a landing zone: thrown off the lip at every speed
from its threshold to a full putt's, the egg comes down on open, dry turf
clear of walls, and meets no rail in the air on the way, over a span of at
least 3 units/s. Slower or harder throws may land in the pond or come off
the far rail: that is the kicker's risk.

## How it looks

The green is a minigolf course on a raised wooden table in a farm
meadow, under a sky dome. Every course is its own corner of the farm at
its own hour, read off the hole's id (`world3d/theme.dart`):

| Course | Hour | Rails | Around it |
|---|---|---|---|
| The Coop | clear morning | timber | the hen house and its hens, the barn, a patch of sunflowers turned to the sun, a feeding trough with its feed sacks and hens at breakfast |
| Corn Maze | noon | corn hedges | a corn field (plants on ploughed rows) with a scarecrow, a pumpkin patch along the corn and at the scarecrow's feet, a corn crib on stilts |
| The Pond | soft afternoon | dry stone | a lake with a dock, reeds and ducks, a rowboat tied at the dock, lily pads laid like stepping stones along the shallows, the windmill |
| Farm Road | golden hour | striped road barriers | the dirt road, a red tractor, an eggs-crossing sign and a chevron sign, milk churns on their stand, a water tower, telephone poles, wheat fields, the windmill |
| The Barn | dusk | red barn boards | the big barn, haystacks, lanterns, strings of glowing bulbs over the yard, a hay wagon, fireflies; its round obstacles are hay bales stood on end |

Each course's own props stand at set spots round the table - mostly on
the far side and the tee's side, where the overview and the wide shots
see them - nudged clear of the table, the picket fence, the landmarks,
the host and one another, never on the camera's side (`_Scenery._settle`);
the scatter of trees, plants and flowers keeps off them, and there are
fewer groves than before. They are merged geometry
poured into the farm's own meshes, so they cost no draw call of their
own; the Barn's bulbs are one emissive mesh with one cloud of soft halos
(no lights: the corners' four lanterns stay the yard's only lamps). The
road signs carry pictures only, never words. The farm group lists what
it stood in `userData['props']` (name, spot, footprint) for the tests.

Each course also grows plants of its own round the table and in the
garden beds the walls carve off it (`world3d/plants.dart`), in place of
the round bushes every course once shared: clipped boxwood balls, potted
topiary and mophead hydrangeas in pink and blue at the Coop; rows of
cabbages with curled outer leaves on beds of dark soil along the maze's
edges, and in rows in its garden beds; clumps of reeds and brown-headed
cattails round the table and on the lake's shore at the Pond; a hawthorn
hedgerow in white blossom along Farm Road's far verge, field gates in its
gaps, and a few hawthorns in blossom on the meadow; shrubs turned orange,
rust and gold and plumes of fountain grass at the Barn. They keep off the
table, the fence line, the landmarks, the host, the props and one
another, and the tall ones grow short on the camera's side. They and the
meadow's stones pour into one smooth-shaded mesh (`farm-soft`) built of
few-faced shapes whose normals round them off, and the ones past the
sun's shadow box into a second one that casts no shadow
(`farm-soft-far`): two draw calls a hole, at no more vertices than the
bushes cost (the tests hold each course to the bushes' count). The farm group lists them in
`userData['plants']` and `userData['bed plants']` (kind, spot,
footprint).

Beside every tee a painted wooden sign shows the hole's number, lettered
like the flag's, in the course's colours (cream and comb red at the Coop,
corn yellow and green in the maze, pond blue and white, road-sign yellow
and black, barn red and cream; a little of its own light, more at dusk).
It stands on the meadow just off the table, as near the tee as the table
allows, its board leaning back and turned between the close camera and
the overview: never on the camera's side, never within 70 degrees of
where the close camera at the tee looks from (`PuttCameraRig.yawToward`),
clear of the host and the corners' lanterns (`_CourseKit.teeSignSpot`).
Off the table, no egg ever rolls through it; it is decoration only. A
hole with no number has no sign.

The host - a big white rooster with his headphones on, a few eggs tall -
stands on the grass beyond the picket fence on the nest's side, about
level with the green's middle. He is built for close-ups (`world3d/birds.dart`): two
legs in bands of yellow-orange scales, each foot three toes forward and
a short one back, knuckled and clawed, a spur on each shank; folded
wings whose secondaries scallop the lower edge, the long primaries
layered along the back; a cream-gold cape of hackles over his
shoulders; and a fan of sickles arching over his tail, near-black with a
green sheen. He breathes (his body swells about two per cent), looks
about with a bird's quick turns and tilts of the head, follows the egg in
play, bobs his head to the beat now and then and cheers when an egg drops
in. While the camera sweeps in over a new hole (the frame's `opening`,
from the camera director's) he turns and looks at it, his body coming
round where his neck will not reach.

The hens are built from the same parts at their size: a plump white
body, wings with their feathers cut along the edge, a small cream fan of
a tail, a little comb and wattle, and the same legs and toes. A walking
hen's legs step with her walk: each swings ahead with its foot lifted
and back with it planted, and the planted foot stays on the ground (on
its claws as it leans back, on its heel as it reaches ahead: the leg's
own lowest point at each swing, read off its vertices once); her body
bobs and rocks from foot to foot, her head bobs with her steps. The yard
hens by the hen house are merged into the farm's props in fewer facets,
some pecking at the grass. Each bird stays a few meshes, feathers and
toes merged: the host's body (legs and tail in it), his two wings and
his head, each with its ink; a hen's body, head and two legs, each with
its ink.

Whenever the host's head would stand under the HUD's top bar or corner
buttons, or he stands right in front of the camera, he pops out of the
way, a quick shrink and fade over 0.15 s (and so does a hen that walks
into the camera's face: all there or not at all, never a half-seen
ghost), every feather with him: his materials are made transparent once
at build, so a fade only moves a uniform.

Ground the walls close off from the tee (a flood fill stopped by walls,
carried through rabbit holes) is planted as the theme's garden beds
instead of turf, so a hole shaped with walls reads as its shape.

The turf rides the hills and the tiers: its vertices sit at the ground's
height and take their normals from its gradient, and it is cut along
every terrace edge and ramp side, each piece laid by the tier it lies
on, so the levels part exactly on the line. Every drop wears a face in
the course's build - dark timber sleepers by the coop and along the road,
dry stone by the pond, stacked hay bales under the barn's loft - and a
rail on a step stands on the high ground with the face under it, a
ramp's rails climbing with it. The lawn draws a pale lip along the top
of every drop where no rail stands, shades the floor at a step's foot
(deeper and wider the taller the step), lifts a terrace's top a touch,
and lights a ramp by the side it faces, with chevrons mown into it
pointing up its rise. An egg rolling off a
lip falls through the air from where it was (18 units/s^2) while its
shadow is already on the floor below, and lands with a squash and a puff
of dust; rising ground, up a ramp, it follows at once. A kicker stands
on the turf in the course's build (`world3d/kicker.dart`): timber planks
on a dark frame at the Coop, a ramp of baled hay bound with twine at the
Barn, packed earth with dry corn stalks laid across it and a shock of them
at either corner of the lip in the maze, a pale stone slab on a dry-stone
wedge at the Pond, a dirt ramp with a striped takeoff board along its lip
on Farm Road. Its deck curves up to the lip at the launch angle (the
core's own profile, the one the eggs ride), and two chevrons painted up
it, a bright fill in an ink rim, point the way it throws. An egg rides up
the deck and flies the engine's arc, its altitude drawn between ticks like
its position and its shadow left on the ground below, shrinking as it
climbs; straw (the Coop, the Barn) or dust (the maze and Farm Road, stone
grit at the Pond) kicks up behind it off the lip, and it lands with a
squash and a puff, a ring of the course's dust and, in the farmyard, a few
stalks. The hop off a hard landing squashes too. Rolled over slowly, an
egg rides the deck and drops off the lip like off a ledge. The lawn
texture lightens the
slopes facing the sun and darkens the far ones, mows rings along the
contours and shades the crease at the foot. Eggs, their shadows (tilted
along the slope), the aim, the crates, the hens, the nest and every
burst stand on the ground's height, and the pointer's ray walks onto it.

On the green: mown turf with stripes and contact shade along the rails,
rubber bumpers (rails and pinball mushrooms), rounded smooth-shaded boulders, ponds
that ripple, speed belts whose chevrons run, rabbit holes glowing their
pair's colour, the silo over its spiral pull, floating "?" crates, the
straw nest with a flag flying the hole's number, the tee mat. The characters - the eggs, the
hens, the ducks and the host - are drawn with a line of ink round them
(their back faces pushed out along their normals; the eggs' line weighs
more as the camera pulls back), so they pop from the softer farm. Eggs are
true egg profiles painted in the player's colour with the band they
picked (see Looks; one paint per colour and pattern, made the first time an
egg wears it and shared after), and their shells' own light takes the
paint's colours, so at the Barn's dusk the shell stays white and the band
glows; they roll
by their velocity, leave a trail when fast, settle on their side, and
slide into the nest when they sink. There the egg hatches
(`world3d/hatch.dart`): the shell's cap pops off in the player's colour
and a chick rises out of the cup in the other half onto the nest's lip,
wearing its player's hat (each of the three pooled chicks carries every
hat and shows one), hops three times flapping at the camera and drops
back in (the viewer's
own a size up, the camera in on it for 3 s). The viewer's egg wears a
marker ring and a bobbing pin drawn over everything; the others carry
name tags, which keep clear of every egg and of the pin, are not drawn
under the HUD's widgets, and show the player's picture alone while their
egg draws under 26 pixels tall (the opening's wide shot, the whole-hole
view). An egg standing in front of the viewer's resting egg on the
screen fades to a third of itself until the viewer putts (the close
camera behind a fresh egg looks along the tee's ring). The nest's cup
falls from a lit wall to a deep brown floor with straw lying on it; the
confetti crown of the viewer's own sink keeps near the nest, and paper
that lands fades away. The power-ups' marks on the green - the
targeting rings and push arrows, the wind's streaks, the swap's violet -
wear ink or depth enough to read on light turf.

When frames run slow (an integrated GPU on a high-density screen) the
surface draws fewer pixels: after three seconds under 42 fps it steps
its pixel ratio down by a fifth, settles, and judges again, never below
half the device's ratio (0.75 on a one-to-one screen) and never back up
(`PuttResolutionGovernor`). Its first step also drops the world to a
low tier: the sun's shadow map from 2048 to 1024 pixels a side, and the
ink outlines off the walkers, the host and the scenery (the eggs, the
aim and the casts' characters keep theirs).

At the Barn's dusk a cool rim light from behind the green edges what the
low sun misses (the light is always in the scene, at nothing by day, so
a course change never recompiles the materials). A figure that fades out
of the way (a hen in the camera's face or during my hatch's close-up,
the host under the HUD) stops casting its shadow as it goes. A splash is
water: drops in the pond's blues with white highlights, a crown kept
close to where the egg went in, four thin jets and a spout, and rings no
wider than the water reaches all round the spot.

Colour is linear-correct: three_js takes hex values as linear, so every
designer's hex goes through `_lin` first; the lights are tuned for the
engine's legacy units (intensities scaled by pi), with ACES tone mapping
and a per-course exposure. three_js's own `PlaneGeometry` tears grids
that are not square (it swaps its segment counts when indexing), so the
world builds those with `_gridPlane`.

### Playing it

- Aim from anywhere: press on the green, drag back, let go. The arrow's
  length and colour say the power (green, yolk, comb red), a ring fills
  around the egg, and a dotted guide shows the first stretch of the roll
  - the engine's own physics run ahead on a copy of the world, cut a
  short way after the first rail. When the egg would stop inside the
  guide (a soft putt), the spot is marked with an egg's footprint drawn
  over everything, and the arrow ends there instead of past it. Off a
  kicker the guide runs the engine's flight to where it comes down,
  however far: its dots climb off the lip and fall, and a yolk ring marks
  the landing. A guide whose length ends on a kicker's deck, or a couple
  of units short of one, runs on to show the flight. The aim draws over
  the other eggs (no egg in the way hides where the putt goes) and under
  the viewer's own. The viewer's last roll on the hole lies under it as
  dots in their colour, from where it stood to where it stopped.
- Until the first putt of the match (and after 14 seconds idle with the
  egg ready), a coach shows the gesture over the egg: a hand presses,
  pulls back away from the nest and lets go while a ghost arrow grows
  (`putt_coach.dart`).
- The camera opens with a low sweep over the nest, then frames the egg
  and the nest inside the part of the screen the HUD leaves free (the
  points are projected through the camera the glide ends at) and
  follows the egg; C toggles the whole-hole view, a right drag orbits,
  the wheel or a pinch zooms. At rest the frame comes no farther out
  than keeps my egg 30 pixels tall: a nest too far for that gives way to
  the stretch toward it (the egg low in the frame), and a marker on the
  edge of the free view - the flag with the hole's number - points at
  the nest while it is off the screen, behind the camera or under one of
  the HUD's widgets, never beside a nest in sight (`putt_nest_marker.dart`).
  While the viewer aims with the nest out of sight, a small map of the
  hole under the course's chip shows the walls, the water, the nest, the
  eggs and where the arrow points, turned with the camera so that ahead
  is up (`putt_mini_map.dart`).
- With the system's reduced motion on, the hole opens on its play
  framing without the sweep, and the camera never shakes nor punches in.

## Sound

Every sound is synthesized by `rooster/tools/gen_game_audio.dart` (the
instruments, the score and the effects in `tools/game_audio/`) with fixed
seeds: no samples, nothing licensed, and a re-run writes the same bytes.
From `rooster/`, with `ffmpeg` (libmp3lame) on the PATH:
`dart run tools/gen_game_audio.dart`.

- The music is a farm band's 112-second loop in G at 120 bpm: the tin
  whistle's tune over banjo rolls, a boom-chick guitar, a two-step upright
  bass, brushes and an egg shaker (A, then A' with the fiddle in thirds);
  the banjo's B over clip-clop wood blocks; B' on the fiddle doubled by a
  chiptune pulse, ending in a stop where the hens cluck; a bridge in E
  minor with chip arpeggios and a stop for the rooster's crow; the banjo's
  break; the reprise and a stop-time tag. The strings are Karplus-Strong,
  the whistle and the fiddle monophonic lines with vibrato, all in a small
  stereo room. It ships as a 44.1 kHz stereo MP3 (about 2 MB), the one
  compressed format every platform's player decodes. The samples wrap
  seamlessly, and the file starts inside the tag's stop, so the gap most
  players leave when they loop (they seek back to the start) falls where
  the band is silent.
- The effects are 44.1 kHz mono, WAV for the hits and MP3 for the longer
  cues, each levelled to a loudness for its kind. My putt tocks in three
  strengths by its power; an egg knocks on timber, boings off rubber,
  clacks on another egg, and a hen clucks or a duck quacks when one bumps
  it, each as loud as the hit; water plops; the nest rustles and chimes,
  the chick peeps as it hatches and the host crows for a hole in one;
  speed strips whoosh, a "?" crate pops, a rabbit hole goes thwup, the
  silo sucks and booms, a fall off the table whistles down; an egg thrown
  off a kicker gets the ramp's thunk under a rising whoosh and thumps down
  into the straw (the thump, softer, for a bump over a lip); a banjo opens
  each hole, a sting closes it, a fanfare ends the match; a cowbell warns
  at 60, 30, 15 and 5 seconds and the last fourteen tick and tock.
- The hits come from the physics: the engine echoes the world's reports
  (`PuttEngine.drainWorldEvents`, never journaled nor snapshotted) and the
  match turns them into sounds, with a short cooldown per egg and at most
  two a frame.

## The layers

- `core/` (pure Dart, headless-testable): deterministic physics with
  fixed timestep and swept collision (and the flights off the kickers),
  the hole model (walls, sensors, the wandering hen, the kickers), the
  rules engine (phases, clocks, scoring,
  mid-join, snapshot round-trips for host handoff) and the power-up
  contracts.
- `courses/` - the five launch courses, each hole shipped with a
  reference solution that a test replays, so an unfinishable hole
  cannot land.
- `ui/organisms/sunny_side_putt/` - the view: a real 3D scene on
  `three_js` (`putt_world3d.dart`, its builders under `world3d/`) under
  the Flutter HUD (`putt_hud.dart`: the hole bar - hole, par, my strokes,
  the clock turning comb red through the last fifteen seconds - with the
  course's holes as dots under it, the course chip, the camera and pause
  buttons, banners by kind, the scorecard, the hint line, the power-up
  carton and its targeting, and the results and match-over cards), the
  cast feed under the top bar (`putt_cast_feed.dart`), the
  name tags, pause/settings/vote menus, the spectator strip, and the
  audio (see Sound; volume per bus in the settings). The world only reads the engine's snapshots; the physics
  stays planar.
- `putt_demo.dart` - the demo mode (`--dart-define=PUTT_DEMO=true`): the
  game plays itself on the real courses for captures; on the web the query
  picks the course, the hole, the crew, a held camera (`cam=host`, `nest`,
  `wide`, `tee`, or `hen` to follow a walking hen) and a script of
  casts (`script=me.thick_shell@3,maya.corn_rain@5,lou.thieving_crow@7.5`;
  see its header). The crew wear looks of their own (a full table shows
  every pattern and hat), and `look=hearts/daisy` dresses the viewer's
  (stars and a crown by default).
- `putt_session.dart` - the live-session bridge: the host's engine is
  the truth; guests feed their own engine with the accepted-move
  journal and resnapshot, so play is smooth without a game server.

## Testing

- `flutter test unit_test/sunny_side_putt` - physics, rules, every
  power-up, the kickers and their flights, every hole's reference solution
  and the courses' lints, the session bridge (two clients on the in-memory
  wire), the view widgets, the looks (`core/looks_test.dart` for the engine
  and the wire, `ui/looks_world_test.dart` for the paints and the hats,
  `ui/looks_view_test.dart` for "Your egg" and the little eggs).
- The voice e2e plays a hole between two real clients; see
  call-activities.md for the environment.
