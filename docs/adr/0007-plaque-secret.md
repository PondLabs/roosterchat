# The plaque secret: who holds a plaque, and how it gets there

**Status: accepted (2026-11-14).**

In Cock-a-Doodle-Who? every player has a plaque on their forehead that everyone reads but them. The call-activity session could not keep that: the host sent one state to everyone, the players' inputs reached only the host, and an elected host carried on from the last state it had heard. A host that also plays would have held its own plaque, and so would every client that received the state.

The requirement (R3 of the plan): the owner's client does not receive what is written on its own plaque before the reveal. The secret is kept by what each client is sent, not by what its screen hides, and it holds for the host too.

## Who the secret is kept from

From the owner's own, unmodified client, on the assumption that it reads everything it is delivered. So the test is on the wire: no message delivered to a client before the reveal carries its plaque's text, the card's id, or anything the card can be worked out from (a position in the deck, the seed of a draw).

It is not kept from a client changed on purpose; "What a changed client could do" below says what that buys.

## Decision

### Everyone holds every plaque but their own

A plaque has two halves.

- **The content** (`Plaque`: the text, the kind, and the card's id and caption or the author) goes in messages addressed to the session's players and spectators except the owner, and each of them keeps it. There is no single holder to lose: a plaque is held by every client that may read it.
- **The ledger** (`PlaqueLedger`) is public. The host keeps it and it rides the session's state, in `parts` under `plaques`, apart from the game's payload. Per owner it has a version, a state (`pending`, `dealt`, `revealed`, `retired`), a random tag that names the content, the kind (the owner sees the kind on their own video) and, for a card, which half of the deck it is in. It also lists the cards the session has spent. A client shows the content it holds under the tag the ledger names.

This needed two additions to the session, which Sunny Side Putt does not use: `sendTo(identities, message)`, an addressed lane open to any participant (LiveKit's `destinationIdentities`), and `hostPart(key, json)`, a component's own part of the state. A message for an empty list of identities is not sent: LiveKit reads an empty list as everyone.

`PlaqueCustody` runs in every client and does the rest. The match's engine tells it when a round starts, when a card is swapped or dealt, and when a plaque is revealed or retired.

### Homemade: the author sends it

The engine draws who writes for whom and tells each author their owner with `sendTo`, so the pairs are in nobody else's client. The author's client sends the content to everyone in the session but the owner. The host, holding it, marks the plaque dealt. When the owner is the host, the author sends the host a note instead: the tag and the kind, without the text.

### Deck: the host draws for the others, another player for the host

The host draws each player's card with its own random generator and sends it to everyone but that player. It cannot draw its own, so the ledger names a dealer for it: the present player with the lowest identity. That client draws the host's card, sends it to everyone but the host, and sends the host a note (tag, kind, half of the deck).

No card may come up twice, and whoever draws cannot see one card in play: their own. No order of drawing avoids that (each card would have to be drawn after the drawer's own, by someone who sees it, all the way round), so the ledger gives away one bit. Each round a salt splits the deck in two halves (`plaquePool`, a hash of the salt and the card's id), and the ledger says which half each player's card is in. **A dealer draws from the half its own card is not in**, and leaves out every card it holds or has held and every card the ledger lists as spent. One dealer draws at a time: while the host's card is being drawn, the host draws none, and the player drawing it first makes sure it holds every other plaque of the round.

When a theme has no card left for a dealer, the draw takes any theme; a spent card comes back only when the whole deck is spent.

### The swap, and the card for a plaque nobody wrote

Both are `hostDeal(owner, filter)`: the next version of that owner's plaque, drawn as above. A request to swap is the engine's own input to the host. The card swapped out is spent and listed in the ledger, so its former owner learns what they had; when it was the host's own, the host first asks a holder for it (it is public by then) and draws nothing until it knows. What an author sends for a version that was replaced is dropped.

### The reveal

The host marks the plaque `revealed` and puts its content in the ledger, author included: the state carries it to everyone, the owner too. The host's own plaque it does not hold, so it asks a holder, which answers the owner only for a plaque the ledger shows as public. `retired`, for the plaque of someone who left, works the same way.

### Joining mid-round

A newcomer gets the ledger with the state and asks a holder (the host first) for each plaque it lacks. It owns none this round, so it ends up holding all of them, and plays the next round. Someone who is in the call but not in the session is refused.

### A holder leaving, an author leaving, the host changing

- The author's name is in the content, so the reveal shows it after the author has left.
- Every other client of the session holds the plaque, so one leaving loses nothing. A request that gets no answer goes to the next holder (at once on a refusal, after two seconds otherwise). When the dealer of the host's card leaves the game, the ledger names the next one.
- A host that takes the seat over continues from the ledger it last heard and from what it holds: every plaque but its own. Anything dealt under the old host that the ledger did not show yet is taken from what the new host holds; an author re-sends to the new host what the ledger does not show; the new host's own plaque is asked from a holder at the reveal, as before.

With two clients the other one is the only holder. If it leaves, the match is over (fewer than two players) and the plaque's text is gone with it.

## What the owner can still work out

- The kind of their plaque, by design.
- In Deck, that their card is of the theme, packs and difficulties the host picked, and is none of the cards they see or the ledger lists as spent.
- Which half of the deck their card is in. The unmodified client does nothing with it.
- That their plaque was replaced, and afterwards which card they had.
- Whether their plaque is a card or was written: only a card has a half of the deck in the ledger. In a Homemade round that says their author ran out of time.
- In Homemade, nothing about the text. The host's client draws who writes for whom, so it has the name of its own author before the reveal; it does not show it.

## What a changed client could do

- List the cards its own could be: the theme's unspent cards in its half of the deck, about half of what it could list anyway.
- Ask a holder for its own plaque. A holder that runs the unmodified client refuses, so this takes two changed clients, and then one could simply tell the other.
- As host, mark its own plaque revealed early: the holders then send it. Being host already means being trusted with the match.
- Join with a second device as a spectator: that is another client of the session, and it holds what every spectator holds.

## Alternatives considered

- **Encrypt the plaque for everyone but the owner inside the broadcast state.** The owner's client would still receive its plaque, and a key to manage per player.
- **The host holds everything and the screen hides the host's own.** It breaks the requirement for the one player who is always there.
- **A dealer who does not play.** There is none: a call activity has no server, and a spectator is not always there.
- **Let two dealers collide and deal again.** A redeal tells the dealer whose card collided what that card was.
- **One slice of the deck per player.** No coordination at all, but each owner's card would be one of an eighth of the theme.
