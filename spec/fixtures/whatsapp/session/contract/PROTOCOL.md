# WhatsApp session protocol v1: the normative half

This is the contract a client is held to, and it travels with the directory: the Chatwoot
side vendors it and counts it in the checksum recorded in `CONTRACT_REF`. The connector's
repository also has a `README.md` here, which is orientation for somebody reading the
directory there; it is deliberately not vendored, so a vendored copy does not contain it and
nothing in this file depends on it.

## Transport

Frames travel as Redis stream entries. Every stream field is a string on the wire;
the schema describes the **decoded** frame, where `v`, `epoch`, `seq`, `ts`,
`deadline` and `max_runtime_ms` are integers and `payload` is an object (transported
JSON-encoded).

**A command carries two different ceilings, and they answer different questions.**
`deadline` is an instant and says *do not start this after that moment*: a command that
reaches its owner late is dropped unrun, answered `expired`. `max_runtime_ms` is a
duration, measured from the moment the work begins, and says *do not let this run longer
than that*; it says nothing about arriving late. A command carrying both gets whichever
runs out first, and one carrying neither is bounded by something the caller did not
choose, which the next paragraph names.

The distinction exists because a teardown needs one without the other: a `session.logout`
dropped for arriving late is a device left linked on somebody's phone with nothing saying
so, while the same command parked on a socket write holds every other command for that
account behind it. With one field a client had to choose, and chose neither.

**A command with neither field is still bounded, and mostly not by this connector.** Most of what this connector sends carries a ceiling that is the WhatsApp library's and not this connector's, seventy five seconds, which covers a message send and an information query alike, and several paths are held to something tighter that this connector chooses. What comes back when one of those runs out is `timeout`, the same word a caller's own `max_runtime_ms` produces and with the same meaning: nobody here knows the outcome and nothing afterwards will. But some paths escape every ceiling, two of them named below, and this contract does not claim the list is complete. So a client that has a deadline of its own enforces it on the reply rather than inferring one from this paragraph.

**A client may resend such a command, and for anything that changes something the identifier is not what makes that safe.** The connector records only what succeeded, so a command answered `timeout` has left no record at all, and a resend under the same `idempotency_key` finds nothing to answer from and runs the work again. What the identifier buys is narrower and still worth having: a frame redelivered after the first attempt *succeeded* is answered from the record instead of being run twice. For a send that is enough on its own, because the resend carries the `message_id` the first attempt used and every client downstream discards a repeat of an id it already has. For everything else it is not: a `group.invite.get` that rotates the link, a participant added or removed, a name set, may already have happened, and resending does it again. A client that cannot afford that reads the state back before resending rather than resending blind.

**`group.create` is the exception, and keeping the key is what makes the recovery work.** It writes down what it is about to do before it asks WhatsApp, so a record exists whether or not the attempt succeeded, and a retry under the same `idempotency_key` consults that record: it returns the group the first attempt made, or answers `not_settled` while WhatsApp's notification is still deciding which request made which group. Retrying with a fresh key instead makes a second group. This is the one command for which "left no record at all" above does not hold, and it is why `not_settled` exists.

**Two paths are not bounded, and a client that names no ceiling of its own inherits both.** The first is a node already being written to the socket: that write is not interruptible by any ceiling, this connector's or the caller's, so a command waiting behind one can outlast every number above. The second is a message send that was interrupted by the connection dropping and is retried once the connection is back: that retry waits for its answer with no timer of its own, so it ends when the answer arrives or when the session does. Neither is this connector's to fix from here, and the two do not have the same remedy. `max_runtime_ms` reaches the second: the retry watches the context it was given, so a ceiling ends it and a `timeout` comes back. It does **not** reach the first, and a client should not set it expecting one to. The lock is taken before the context is looked at and the connector carries a command out on the goroutine that is waiting there, so neither ceiling runs and no reply is produced until the write ahead finishes. **A client that cannot wait indefinitely needs its own timeout on the reply**, not a field on the command: this connector will answer, and what no field here can promise is when.

**Neither ceiling reaches `session.wake`, and a client should not expect `expired` for one.**
It is carried out before any session is involved, and nothing on that path reads `deadline`.
That is the whole point for a wake: it is the only thing that starts a session with no entry
yet in the connector's own record of what each session should be, so retiring one for
arriving late leaves an account paired, owned by nobody and silent. What paces a wake that
keeps coming back is instead the fleet's own backoff described under `wa:quarantine:<sid>`
below: not a count of deliveries and not a clock, but the connector declining to make the
same attempt again for a minute, then two, up to an hour.

`admin.ping` goes the other way, and the difference is what refusing costs. A ping asks what
this instance is running *now*, so one answered after its deadline is a true sentence about
the wrong instant, sent to a caller that stopped waiting; refusing starts nothing and tears
nothing down. A late ping is answered `expired`, and a client that sent one without a
`reply_to` sees nothing at all: the refusal is recorded as
`wac_command_duration_seconds{type="admin.ping",outcome="expired"}` on the instance and
nowhere else, with no line in its log.

`session.delete` is the exception among the three, and it is the one that costs a client
something. It travels the control stream but it is not carried out there: the connector
adopts the account so that the account's own executor can tear it down, which puts the
teardown under both ceilings like any other command. **A client should not put a `deadline`
on a teardown** -- `session.delete` or `session.logout` -- and should bound it with
`max_runtime_ms` alone. One that arrives after its deadline is answered `expired` and the
account is not torn down, which is the device left linked on somebody's phone that the two
fields exist to keep apart, and it is the whole of what the refusal costs. The adoption
behind it costs nothing further: an account opened so that a teardown can reach its
executor is never connected, and one whose teardown was then refused for arriving late is
given back, by a heartbeat rather than by the answer, so a refused teardown does not
leave the account owned by the instance that refused it. A client that sends another
command for that account in between is talking to the instance that still owns it, and one
that arrives while the lease is going back is left pending for whoever takes the account
next, which is what every hand-back does.

**A teardown that ran out of time answers `not_attempted` when nothing was sent, and a
client should retry that one.** The two ways a teardown fails on time are not the same
fact and the connector tells them apart. `timeout` is the ordinary one: the request was
on its way and how far it got is not known here, so a retry may be repeating something
that already happened. `not_attempted` is the connector saying it is certain nothing was
written to WhatsApp -- the socket was being dialled and its lock was never free, so the
unlink was never called. The account is exactly as it was, the device is still linked on
somebody's phone, and a retry does the whole thing rather than the half that is left.
Retrying with the same `idempotency_key` is correct: a command that failed is not
recorded, so the key answers nothing and the retry runs. The same word answers a
`session.logout` in the same state, because it is the same fact about the socket; a
logout whose request did reach WhatsApp and whose answer was lost is the other case and
keeps `timeout`. A client that treats `not_attempted` as final leaves a device linked
that no later command can remove, because the credentials that would sign the unlink are
the ones the teardown would have thrown away.

**A `group.create` whose outcome is not decided yet answers `not_settled`, and a client
should ask again in a moment.** Two requests for a group of the same name, both still
open, make a group on WhatsApp that is evidence for either and proof for neither.
Answering one of them with it would hand that request the other's conversation and skip
the creation it asked for, so the connector refuses until WhatsApp's own notification
names which request made which group, which ordinarily arrives within seconds. This is
the third answer about time and it is not either of the other two: `timeout` says nobody
here can tell and nothing afterwards will, `not_attempted` says the request never went
out, and `not_settled` says it did and the connector expects to know which shortly.
Retrying with the same `idempotency_key` is correct and is the point: a command that
failed is not recorded, so the key answers nothing and the retry runs, and the retry is
what collects the group the first attempt made rather than making a second one. A client
that treats it as final leaves the operator with a group nobody's conversation points at;
a client that treats it as `internal` pages somebody for a case that settles itself.

**`not_settled` is not a promise that asking again will settle it, and a client bounds its
retries.** The word says the outcome is undecided here, not that a decision is coming. One
state does not resolve: an attempt whose intent was recorded and whose request never
reached WhatsApp, because the process died between the two. No group was made, so no
notification will ever name one, and every redelivery gets `not_settled` again. Retrying is
also what keeps that record alive -- each delivery pushes the intent's clock forward, and
the connector's own sweep, which would drop an untouched intent after its retention window,
never reaches one that is still being asked about. So a client retries a few times over
seconds, and a `not_settled` that survives that is a stranded intent: stop, tell somebody,
and do not send the same key again expecting a different answer.

**Both ceilings bound the wait on WhatsApp, not the bookkeeping that follows it.** Once a
teardown's unlink has been answered, the connector finishes deleting the credentials, the
device mapping and the session's epoch counter on a bound of its own, and a ceiling that
ran out during the unlink does not cancel any of it: an account whose remote half is gone
and whose local half survived is one the connector would go on adopting and resuming over
credentials WhatsApp has already revoked. So a client may set the ceiling to how long it
is willing to wait for an answer, not to how long the teardown is allowed to take in all.

| Stream / key | Direction | Frame |
|---|---|---|
| `wa:events:<shard>` | connector → client | `event` |
| `wa:cmd:<sid>` | client → connector | `command` |
| `wa:control` | client → any connector | `command` (`session.wake`, `admin.ping`, `session.delete`) |
| `wa:reply:<command_id>` (LIST) | connector → client | `reply` |

`seq` is monotonic per `(sid, epoch)` and, together with the per-session shard
assignment, is what lets the consumer drop out-of-order redeliveries.

**A client must deduplicate on `message.id`, and `seq` does not do it for you.** Delivery
is at-least-once per event, and the two mechanisms cover different things. `seq` catches
the same event handed over twice by the transport. It does not catch the case where one
WhatsApp message reaches the client as *two different events*, each with its own `seq`,
which is what a redelivered `message.send` produces: WhatsApp does not deduplicate a
stanza id, so the second attempt puts a second copy of the message on the wire, and the
connector publishes both. Measured, from an immediate resend out to thirty minutes
apart, and for direct chats and groups alike (#215).

This is not an edge case the client may skip. The connector's inbound path publishes a
message more than once **on purpose** in several places -- a placeholder published before
the real body arrives, a decryption that resolves after the fact, a session that changed
hands mid-publish -- and every one of them is written on the assumption that the client
keeps the first row and discards the repeat. A client that does not deduplicate on
`message.id` will show the same message twice without having done anything wrong.

**Which stream a command goes on is part of the contract, not a detail.** A connector
reads `wa:cmd:<sid>` only for the sessions it is running, so a command addressed to a
session nobody has adopted is delivered to no connector at all and is lost when the
stream is trimmed. `wa:control` is read by every connector, which is why the commands
that have to reach an account nobody owns ride it:

- `session.wake` starts a session nobody is running, which is the whole point of it.
- `session.delete` tears one down, and the account it matters most for is exactly the
  one that is down: an inbox destroyed while its session was not connected, or
  destroyed while the fleet was restarting.

Both are accepted on `wa:cmd:<sid>` as well, and a connector running the session
carries them out from there. A client that publishes `session.delete` only to the
session's own stream therefore gets the teardown whenever the session happens to be
up, and silence otherwise.

What `wa:control` guarantees is delivery to *some* connector, not to a particular one.
Every connector reads the stream under one consumer group, so an entry naming a session
another connector is running is given up by the one that read it and reclaimed later,
possibly by the same one. For `session.delete` that means: an account **nobody** owns is
torn down by whoever reads the entry, which is the case this route exists for and is
deterministic; an account a connector is **running** is torn down when the entry reaches
that connector, which happens but is not bounded. Nothing in the protocol asks an owner to
give a session up **on demand**: a `wa:handoff:<sid>` key was declared for that once and
removed here, having never had anything behind it. An owner giving a session up **of its
own accord** is a different thing and does exist -- it is `wa:handback:<sid>` in the table
below, and it is the reason a wake can meet an account that is owned and on its way to
being unowned.

Around those four keys sit the ones that decide who reads and who writes. They are not
frames, but both sides have to agree on them, so they are part of the contract:

| Key | Type | Owner | Meaning |
|---|---|---|---|
| `wa:meta` | HASH | connector | `protocol_min`, `protocol_max`, `event_shards`; a connector whose `event_shards` disagrees refuses to start |
| `wa:instances`, `wa:instance:<inst>` | SET, HASH (PX 15s) | connector | live instances and what they advertise: `version`, `protocol_min`, `protocol_max`, `advertise_url`, `media_token` |
| `wa:handback:<sid>` | STRING (PX 30s, not renewed) | connector | the instance that holds a session's lease and has started giving it up. Written before the release, compared against the lease holder by the acquire, cleared by the release, and left to expire when the release never lands. A `session.wake` that arrives in that window is left pending rather than acknowledged, so a client can see up to one lease TTL of silence before the account is picked up |
| `wa:lease:<sid>` | STRING (PX 30s, renewed) | connector | which instance owns a session. It expires on its own, which is what lets an account whose owner died be taken over |
| `wa:lease-epoch:<sid>` | STRING (**no expiry**) | connector | the epoch that owner holds the session under, incremented on every acquisition. It must outlive every disconnection, logout and re-pairing of the account, and only a `session.delete` removes it |
| `wa:idem:<sid>:<key>` | STRING | connector | command idempotency (`msg:<message_id>` for sends) |
| `wa:resume:<sid>` | STRING (EX 60s) | connector | a turn taken to bring an unowned session back, so the fleet asks about one account once per window |
| `wa:quarantine:<sid>` | HASH (EX wait + 1h) | connector | `strikes` and `until`: how many times a session failed to come back, and how long the fleet leaves it alone. `attempt` is the connector's own bookkeeping, telling one failure from a retry of the same one |
| `wa:events:<shard>:lease` | STRING (EX 30s) | client | which consumer reads a shard; exactly one at a time, which is what preserves order |
| `wa:consumer:<cid>` | STRING (EX 15s) | client | consumer heartbeat and the shards it holds |
| `wa:cursor:<sid>` | STRING | client | last `epoch:seq` the client processed for a session |

**The epoch counter is the one key here with no lifetime, and that is a decision.** A
client keeps the highest epoch it has seen for a session and drops every event below it,
which is what stops a late event from a previous owner overwriting the state of the
instance running the account now. A counter that expired while nobody held the session
would start again at one on the next acquisition, and an owner still holding eight -- a
paused process, a socket that outlived its lease, a delivery that sat in a queue -- would
then out-rank the live one and be accepted. So a client must never treat a lower epoch as
fresh, whatever the gap, and nothing but the connector deletes this key. An account logged
out, whether it asked to be or WhatsApp imposed it, keeps its counter: the inbox is still
there and the account can be paired again under the same `sid`, so a counter starting over
would have the client discard the pairing itself.

There is exactly one moment the connector knows an account is gone, and it is the teardown
itself. Everything else is a guess, and the guesses are left unclosed: an id a
`session.wake` named and nothing ever paired keeps its counter, so does an account deleted
before this rule existed, and so does one whose `session.delete` was **delivered twice** --
the second delivery is answered from the command record without the teardown running, while
the adoption that answered it has written the counter back. Roughly sixty bytes each.

Reclaiming any of them means telling a deleted account from one waiting to be paired again,
and from this side those are identical: both have no rows at all. The record of a delete
does not settle it either, because it is kept for a day and the same `sid` can be paired
again inside that day -- dropping the counter on the strength of it restarts a live
session's fencing token under a cursor that is already higher, which is a TTL's damage
arriving by another road. The client is the only side that knows which sessions it still
has an inbox for, which is why no sweep is offered here rather than offered with a caveat.

**Four keys left this table rather than being explained in it.** `wa:sessions` and
`wa:session:<sid>` described a registry of session state that was never built, and
`wa:dlq:events` and `wa:dlq:commands` a dead letter queue neither side has ever written;
all four had a key constructor and nothing else. A row for a key nobody writes is worse
than an absent row -- a client vendoring this directory reads that the connector keeps
the last known state of every session, or that an operator can go and look at what
failed, and writes code against either. The registry cost a holdout agent a set of
acceptance criteria built on that premise while #151 was being verified, and the DLQ
would send an operator to a key that is empty whether or not anything failed. A client
that still reads those names in an older vendored copy of this contract should stop: they
are not written, and they were not written then either. Wanting a DLQ is an issue to open, not a
constructor to leave lying around.

`wa:quarantine:<sid>` was in the same state and is not any more: it counts the failures
of a session the connector could not bring back and says how long the fleet leaves it
alone, from a minute up to an hour, doubling. It gates what the connector does on its own,
which is two things: its resume sweep, and a `session.wake` the fleet has already handed
out once. A wake read for the first time is a client asking, and a client that asks for a
connection gets one, quarantine or not, which is why no command is ever answered
`quarantined`. Every copy after that one is this fleet repeating an attempt it already
made, and it waits out the backoff. **A client whose session does not come up should
publish another `session.wake` rather than wait on the one it already sent**, which is the
difference between asking again and being retried. Whether a session registry should exist
at all is a separate question from this table telling clients that one does.

**The one thing that registry was for does exist, and not here.** A connector keeps what
a client asked each session to be -- connected or disconnected -- in its own database,
written by `session.connect` and `session.disconnect` and deleted by `session.logout` and
`session.delete`. It is what makes a paired account survive the instance that was running
it: a lease dies with its holder and a `session.wake` is a frame read once, so without a
record of intent a restarted fleet leaves every account unowned and silent. A sweep reads
it and brings back what nobody is running, taking `wa:resume:<sid>` first so the fleet
spends one attempt per account per window rather than one per instance per pass.

It is deliberately not in Redis and not in this table. Desired state that a client could
write is a client deciding when the connector dials WhatsApp; what the client says is a
command, and this is the connector's record of having been told.

The client reads events with a consumer group named `chatwoot`, created at `0` so that
whatever the connector published while no client was running is still delivered.

## Compatibility

`v` is the major version. Additive changes (new event type, new optional field) do
NOT bump it: consumers must ignore unknown event types and unknown payload fields,
which is why payload objects allow additional properties while frames do not.

Removing an event type that no producer has ever published does not bump it either:
no consumer can have received one, so there is nothing for an older one to lose. That is
how `account.reachout_timelock` and `account.new_chat_cap` left. Removing a type that
something does publish, a command, or an error code is a breaking change.

A connector advertises `protocol{min,max}` in its Redis registry entry and supports
`N` and `N-1`. Clients refuse to talk to a connector whose range does not overlap
theirs, and the connector is always upgraded first.

## Conventions

- Identity is always an `address` (`kind` + bare `id`, no `@server`, no device or
  agent suffix) or a `party` (`phone` and/or `lid` plus display names). Raw JIDs
  never cross the wire.
- Timestamps are epoch milliseconds. A frame's `ts` is when the connector learned the
  thing it reports, not when it managed to write it: an event that spent time in a queue
  is not news from now, and a reader has only this to tell the two apart.
- `chat.presence` describes a moment rather than a state that holds, and the reader is
  what bounds how long it is worth showing: a `composing` or `recording` older than a
  few seconds by its own `ts` should not start an indicator. The connector drops one it
  can see has gone stale before it writes it, but it cannot promise more than that --
  nothing on the write side bounds how long a consumer takes to get there, and an
  indicator started late has nothing coming to clear it, because the `paused` that would
  have was published while the stale one was still on its way. `paused`, and both
  `presence.update` states, are facts that hold until something says otherwise and carry
  no such rule.
- `presence.set` takes effect when WhatsApp says so, not when the reply comes back: the
  node is written and acknowledged locally, and a `chat.presence` sent in the same breath
  as the `available` before it has been observed not to render on the other phone, while
  later ones in the same session do. What the first one is missing was not pinned down --
  the availability landing and the peer's own subscription to it are not separable from
  outside -- so the rule a client can rely on is only that the first typing indicator of
  a session may not show. An account marks itself available once when its session opens
  and types much later, so this bites only a client that does both at once.
- Neither an account's availability nor its presence subscriptions survive the
  connection they were set on: WhatsApp forgets both when the socket goes, and nothing
  replays them. `session.state: open` is therefore where a client re-establishes what it
  still wants, and that is both commands. The connector reapplies the last
  `presence.set` it carried out as soon as a connection comes up, which closes a window
  a client's own round trip cannot -- while the account is not marked available every
  message it receives is receipted as if nobody were there, and no sender's client
  renders that tick. What it puts back is kept next to the account rather than in the
  session, so an ownership change is covered too: the instance that takes the account
  over reapplies the last `presence.set` without ever having heard the command. Sending
  it again on `session.state: open` is harmless and stays the safe habit -- the
  connector's copy is only as current as the last command it carried out. Subscriptions are
  not reapplied at all: which parties are worth watching is the client's to know, and a
  connector holding that set would either re-subscribe an address book nobody is looking
  at or refuse the one contact somebody has open. Until the client asks again,
  `presence.update` stops arriving and the last state it published stands.
- Outbound message ids are generated by the client (`"3EB0" + 18 hex`, the
  whatsmeow/Baileys shape) so the echo can be matched before the reply arrives.
  Providers that cannot accept a caller-supplied id use `client_ref` instead.
- Media bytes never travel in a frame. Inbound media carries a `media_ref` the
  client fetches over HTTP; outbound media carries a URL the connector fetches.
- A media message published with no `ref` is followed by `media.download_failed`, and
  `recoverable` on it is what says whether that is the end. False is every reason the
  file is not coming back -- the key lapsed, the bytes did not check out, the file is
  past what the instance keeps -- and the client flags the bubble. True is WhatsApp
  having dropped the file while the sender's phone may still hold it, and it is an
  invitation: `message.download_media` asks the phone to upload it again and answers
  with a fresh `media_ref`. The connector does not ask on its own, because the inbound
  path runs on a node handler it cannot spend somebody's phone waking up. A producer
  that predates the field leaves it out, and absent reads as false, which is the
  behaviour every client already had.
- `message.revoked` carries `message_author` where the deletion's key named one, and it
  is a claim rather than a fact. WhatsApp addresses a message by (id, participant), so
  any member of a group can send a deletion naming somebody who did not write the
  message: the phones apply nothing, and a client matching on the id alone marks the
  bubble deleted while every other member still sees it. Compare the claim against the
  author of the message you resolved, and drop the deletion when the two disagree. The
  check is necessary and not sufficient -- WhatsApp also requires the sender to be that
  author or an admin of the group, and a connector answers neither without keeping every
  message's author or spending a round trip per deletion -- so it closes the case a
  member can exploit rather than the whole rule. A key that says the message is the
  deleter's own names the deleter, whatever participant it also carries, because that is
  how WhatsApp resolves it. Absent means the key named nobody WhatsApp reads, which is a
  one-to-one chat: a key there addresses the message by the conversation rather than by a
  participant, so `sender` and `by` are the whole answer and a participant that turns up
  in one is dropped rather than passed on. A message sent through a broadcast list is
  shown in the direct conversation with whoever sent it and is published there, but its
  key is a list's and carries the field. A `message.revoked` for a
  group always carries the field -- a key with neither a participant nor `from_me` names
  no message, and this connector drops that deletion rather than publishing one no phone
  applied -- so a client can require it there.
- An absent field and an explicit `null` mean the same thing to a client, so a field
  that has to distinguish "there is none" from "this producer does not say" carries
  its own flag. `group_info.has_picture` is the one such field today: a `picture_url`
  of `null` cannot tell a group with no photo from a snapshot that does not mention
  one, and the client needs the difference to clear a photo removed while its session
  was out of the group. A producer that cannot answer leaves it out.
- Errors carry an `error_code`. The enum grows the way everything else here does: a
  consumer that meets a code it does not know treats it as `internal`, which both
  implementations already do -- `protocol.NewError` on the Go side, `Errors.build` on
  the Ruby one -- so a connector answering with a newer code gets exactly the behaviour
  an older client had before that code existed. The Ruby classes are not a 1:1 mapping
  in either direction: some of them (`event_out_of_order`, `message_already_processing`)
  never travel, and they exist to be rescued rather than to be sent.
- Three codes are published and never sent, so a client branching on them writes a branch
  that never runs. `session_not_found` is not answered at all: a command for a session no
  instance owns stays pending and its caller waits out its own deadline. `quarantined` is not
  answered either, and never will be: the backoff behind it paces what the connector does
  on its own, and refusing a client that asks would put it in front of the person fixing
  the account.
  `client_outdated` reaches a client as the `session.client_outdated` event instead, never
  as a reply. They stay in the enum because
  removing one narrows what a client may already match on, and each is marked in
  `internal/protocol/errors.go` with what arrives in its place.
- Four command types have no handler here -- `session.update`, `history.request`,
  `contact.info` and `call.reject` -- and a client that sends one is answered
  `unsupported`. That answer only reaches a client whose session some instance owns: a
  command for a session nobody is running is delivered to nobody, so the caller waits out
  its own deadline instead. Which four is marked in `internal/protocol/types.go` and held
  there by a test, so wiring one up without saying so fails the build.
- Nine of the event types have no producer in this connector either, and the same
  reasoning holds: a client may match on one and never see it. Unlike a command, nothing
  says so at the time -- a command it does not implement comes back `unsupported`, while
  an event that is never published is indistinguishable from one that has not happened.
  Which nine is marked in `internal/protocol/types.go` and held there by a test, so
  the marking is what the build does rather than what it did when somebody last looked.
  An unproduced type stays only while some producer could emit it one day:
  `account.reachout_timelock` and `account.new_chat_cap` were removed because none can.
  whatsmeow exposes no WhatsApp Business messaging limit, and uazapi, the other provider
  behind this contract, reports its limits through the instance status rather than by
  event.
- A `party` carries both of WhatsApp's namespaces for one person only where this account was in a position to know they are the same person. A LID exists so somebody can take part in a conversation without handing over their number, and which accounts get to see the number behind one is granted per account. So the two halves are linked only where WhatsApp showed this account they belong together: an event that carried both, a group listing that named a participant by each, or the account's own pair. Otherwise a party goes out with the half the event carried, and a client should treat the other as not yet known rather than as absent for good: the next message from the same person usually carries both. A deployment hosting accounts for more than one operator is where this is load-bearing, because the device store's mapping table is shared by all of them.
- Three of the codes are about *who* failed, and the distinction is what an operator
  reads first: `wa_error` is WhatsApp refusing, `provider_unavailable` is a dependency
  the command itself named -- the storage a `message.send` points its `ref.url` at --
  not answering, and `internal` is this connector. All three are worth retrying; only
  the last one means the connector's own logs are where to look.

## RPC results

The `reply` frame carries `result` as an opaque object: the schema does not describe
it per command type, because a result is only ever read by the caller of that one
command. What the two sides agreed on is listed here, and it is what a command answers
when a connector carries it out at all: one that does not implement a command refuses
it with `unsupported` rather than answering a result of the wrong shape. In this
connector that is `contact.info` and `history.request` below, plus `session.update` and
`call.reject`, which have no result of their own to list.

| Command | `result` |
|---|---|
| `session.connect`, `session.status` | `connection_state`, which also carries `reachout_time_lock` and `new_chat_cap` where a connector reports them. This one does not fill either: whatsmeow exposes no WhatsApp Business messaging limit to fill them with |
| `admin.ping` | `{ "inst": string, "version": string, "sessions": integer }` |
| `message.send`, `message.edit`, `message.react` | `{ "message_id": string, "timestamp": timestamp_ms, "client_ref": string\|null }`. `message.react` is refused with `unsupported` on a channel, which names a post by a server id the contract has no field for |
| `message.revoke` | `null`. Refused with `unsupported` on a channel: WhatsApp answers the deletion without an error and leaves the post up, so reporting success would tell the client a post is gone while every follower still sees it |
| `history.request` | `null`. The phone answers later, as `history.sync` events, and may never answer at all: the reply says the request went out, not that history is coming |
| `message.download_media` | `media_ref`, fetchable from `url` until `expires_at`. The connector answers with a `connector_blob`, the same shape its events carry: what it hands back is a blob it just wrote, instance-local and time-bounded like any other |
| `contact.check` | array of `{ "phone": digits, "exists": boolean, "address": address\|null }` |
| `contact.profile_picture` | `{ "url": string\|null }` |
| `contact.resolve` | `party`. Both of WhatsApp's namespaces for one person, out of what the connector already holds, plus the display names it has learned. Local: no round trip, and a session that is paired but not connected still answers it. It answers out of what this account was shown -- see the party rule under Conventions -- so a pairing nothing has shown it is answered with the half the caller already had |
| `contact.info` | `party` |
| `group.create`, `group.info` | `group_info`. `topic_id` is WhatsApp's own id for the description, passed on as it arrives and never interpreted: a group whose description came back with the literal string `undefined` refuses every later edit with a conflict, and this is the only reading that says so. The connector does not turn it into an error code, because a conflict is genuinely ambiguous between a frozen description and another admin writing in between, and what to tell an operator is the client's to decide. `participants` is absent when the connector cannot account for every one of them -- an anonymous participant it has no address for, or a list shorter than `size` -- because a roster reads as the whole of the group and half of one takes people out of it. Absent means *not answered*, never *empty*: `size` is what says how many there are |
| `group.list` | array of `group_info`, empty when the account is in no groups, and **without `participants`**: an account can be in hundreds of groups of hundreds of people, and a listing that carried every membership would answer with the whole address book of every conversation to say which conversations exist. `size` still says how big each one is, and `group.info` answers the roster for the group a caller opens |
| `group.invite.get` | `{ "code": string, "url": string\|null }` |
| `group.participants.update`, `group.join_requests.update` | array of `{ "address": address, "status": "success"\|"failed", "code": error_code\|null }` |
| `group.join_requests.list` | array of `{ "party": party, "requested_at": timestamp_ms }`, empty when nobody is waiting. `requested_at` is `timestamp_ms\|null`, null when the provider did not date the request: a request with no date is still one somebody is waiting on, and a zero reads as January 1970 and sorts as one |
| `group.leave`, `group.name.set`, `group.description.set`, `group.photo.set`, `group.settings.set` | `null` |

A command whose result is `null` still answers `{"ok": true}`: the caller is waiting
for the confirmation, not for data.
