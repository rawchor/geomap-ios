# Chat WebSocket Protocol

Realtime messaging between confirmed friends, over a **plain WebSocket** — no STOMP. REST
endpoints for conversation list and history are documented in `API_CONTRACT.json`; this file
covers the part OpenAPI doesn't: the WebSocket handshake, auth, and message envelope.

Plain WebSocket rather than STOMP: Apple has no first-party STOMP client (hand-rolling STOMP frame
parsing on iOS is real, avoidable complexity), and this app's chat is simple 1:1 messaging that
doesn't need STOMP's pub/sub destination framework. A small JSON envelope over a native
`WebSocket`/`URLSessionWebSocketTask` connection is all this needs.

## Connecting

- Endpoint: `wss://<host>/ws/chat?token=<jwt>`
- The JWT goes in the `token` query param, not a header — a WebSocket handshake from a
  browser/mobile client can't easily attach a custom `Authorization` header the way a normal HTTP
  request can.
- A missing or invalid token rejects the upgrade outright (HTTP 401 on the handshake response) —
  there is no unauthenticated session that only fails later on the first message.
- One connection per user. Reconnect whenever it drops (e.g. app backgrounded then foregrounded) —
  there's no server-side session persistence across a dropped connection, and no need for a
  persistent background connection at this stage.

## Sending a message

Send a text frame with this JSON body:

```json
{
  "type": "message",
  "recipientId": "<uuid>",
  "content": "text, 1-1000 chars"
}
```

- Sender and recipient must be confirmed friends, or the send is rejected (see Errors below) and
  nothing is persisted.
- There is no ack frame on success — the message is simply persisted, and delivered to the
  recipient if they're currently connected (see below). The sender does not get their own message
  echoed back; append it to your local message list optimistically instead of waiting on a round
  trip.

## Receiving messages

When someone sends you a message and you're connected, you receive a text frame:

```json
{
  "type": "message",
  "id": "<uuid>",
  "senderId": "<uuid>",
  "recipientId": "<uuid>",
  "content": "text",
  "sentAt": "2026-09-16T13:03:02.050782Z",
  "readAt": null
}
```

- If you aren't connected when a friend sends you a message, it is still persisted — no error, no
  retry needed on the sender's side. You'll see it via `GET /chat/{friendId}/messages` the next
  time you open that conversation.
- `readAt` is not yet settable over this protocol (no read-receipt endpoint exists yet); it will
  always be `null` on freshly delivered messages.

## Errors

Any rejected send gets a text frame back on the same connection, sent only to the sender:

```json
{ "type": "error", "message": "You can only message confirmed friends" }
```

Cases that produce this: sending to a non-friend, an unparseable frame, an unrecognized `type`, a
missing `recipientId`, or `content` that's blank or over 1000 characters. The recipient never sees
a failed attempt, and nothing is persisted for a rejected send.

## Message envelope, extended

Every frame in either direction carries a `type` field, which is deliberate — it's what lets this
schema grow later (e.g. a `"type": "read_receipt"` frame) without breaking existing clients that
only look at frames whose `type` they recognize. Currently defined: `"message"` (both directions)
and `"error"` (server → client only).

## Notes for client implementers

- `/ws/**` is public at the HTTP layer (no bearer token needed for the upgrade path itself, since
  `SecurityConfig`'s ordinary per-request JWT filter doesn't apply to a single upgrade request) —
  auth is entirely the `?token=` query param above. Don't skip it.
- The session registry that routes a message to its recipient's connection is currently in-memory
  and single-instance — fine at today's scale. If the backend ever runs on more than one instance,
  this moves to a shared store (Redis pub-sub), transparent to clients either way.
- Message content is stored as plaintext in Postgres. Transport is encrypted (`wss://` = TLS), the
  same baseline most consumer chat apps use for default (non-"secret") conversations — this is not
  end-to-end encrypted.
