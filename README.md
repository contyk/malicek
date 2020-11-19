# Malíček

Malíček provides a REST interface for [Alík.cz](https://alik.cz/).

An experimental, toy middle layer that serves as an abstraction of Alík's
features.  Currently limited to chat.

Due to Alík's limitations, this service is inherently unsafe and using a public
instance is not recommended.  See below for details.  However, a public demo
instance is available at https://alik.contyk.dev/.

## Architecture

Malíček sits between the user and Alík, translating REST requests into standard
Alík web page requests, munching the responses and presenting them in
machine-friendly, lightweight JSON.

Since Alík does not provide authentication methods for third parties, Malíček
needs to handle the user's username and password directly, passing it through
and holding the session cookies.  In turn, Malíček issues its own session
cookies for the REST interface.  The API is documented below.  Both request and
response bodies must be in JSON.

No actions are performed automatically on the user's behalf.  Each REST request
directly translates into a synchronous Alík request.

The code relies heavily on regular expressions for parsing Alík's responses.
Unfortunately, this is necessary as the responses are often broken, invalid
HTML.  The parsing code is therefore very fragile and needs to be updated
whenever Alík changes.  Fortunately that doesn't happen very frequently.

## API

Reponses are in JSON, request bodies must also be in JSON.

### `GET /`

Returns `200` for authenticated sessions, `401` otherwise.

```json
{
  "app": "malicek",
  "version": "0.1.12",
  "agent": "Malicek/v0.1.12",
  "state": true
}
```

Provides the app identification, its name, version, its User-Agent string, and
whether the session is active or not.

### `POST /login`

Creates a session with the following request:

```json
{
  "user": "username",
  "pass": "p4s5w0rd"
}
```

Redirects to `/`.

### `GET /logout`

Destroys the session.  Redirects to `/`.

### `GET /status`

Provides generic user status information:

* Whether they have any in-mail.
* How many users are currently online.
* Their points balance (*kačky*).

```json
{
  "mail": 3,
  "people": 42,
  "cash": 120031
}
```

Unauthenticated sessions get redirected to `/`.

### `GET /rooms`

Provides a list of currently available rooms and their users.

```json
[
  {
    "id": "alik",
    "name": "Alík",
    "users": [],
    "allowed": "all"
  },
  {
    "id": "tajny-stul",
    "name": "Tajný stůl!",
    "users": [
      {
        "id": "foo",
        "name": "FoO",
        "sex": "unisex",
        "admin": [
          "admin"
        ]
      },
      {
        "id": "bar",
        "name": "bar",
        "sex": "girl",
        "admin": []
      }
    ],
    "allowed": "friends"
  }
]
```

`allowed` can be either `all`, `friends`, `girls` or `boys`.

`sex` can be either `boy`, `girl` or `unisex`.

`admin` is currently either an empty list or a list containing a single item, `admin`.

Unauthenticated sessions get redirected to `/`.

### `GET /rooms/<id>`

Gets the list of curently visible messages in the selected room.  Joins the
room on the first request (although see the Shortcomings section).

A detailed list of users in the room is also provided.

```json
{
  "creator": "FoO",
  "users": [
    {
      "id": null,
      "name": "contyk",
      "link": "contyk",
      "since": "4:44",
      "last": "4:44",
      "admin": [],
      "sex": "boy",
      "age": 415
    }
  ],
  "messages": [
    {
      "nick": "contyk",
      "color": "#424242",
      "message": "Hmmm...",
      "avatar": "https://o00o.cz/obrazky/DF/QL/XDZ-avatar.png",
      "time": "04:56:35",
      "private": [],
      "type": "chat",
      "event": null
    },
    {
      "nick": null,
      "color": null,
      "message": "Kamarád contyk si přisedl ke stolu.",
      "avatar": null,
      "time": "04:44:00",
      "private": [],
      "type": "system",
      "event": {
        "type": "join",
        "source": "contyk",
        "target": null
      }
    }
  ]
}
```

User `id` is `null` for self, otherwise it's the numerical system ID, usable
for private messaging.

Messages are sorted by the most recent first.

Message `time` can be `null` if timestamps are disabled.

Message `avatar` can be `null` if avatars are disabled or in the case of system
messages.

Message `color` can be a bogus (but valid) value if colors are disabled, or
`null` for system messages.

`private` contains a list of nicks the message is intended for.  If empty,
the message is public.

Messages with `null` as the private recipient are filtered out.  These can be
used for keepalive messages.

For message of `type` `system`, `event` may contain additional data about the
message.  Currently supported types include `join`, `part`, `kick`, `oper`,
`clear`, `lock` and `unlock`.  Most set the `source`, `kick` sets the `target`.

Room settings can also be queried with `?query=settings`.

```json
{
  "color": "#424242",
  "refresh": 5,
  "highlight": true,
  "colors": true,
  "system": true,
  "time": true,
  "avatars": true
}
```

Own's message color is represented by `color`.  `refresh` is the number of
seconds between Alík's own refreshes.  `highlight` highlights one's name on
Alík, `colors` toggles whether other users' colors are shown, `system` toggles
whether system messages are shown, `time` toggles whether timestamps are shown,
and `avatars` toggles the visibility of user avatars in messages.

Unauthenticated sessions get redirected to `/`.

### `POST /rooms/<id>`

Sends a message or leaves the selected room.

To post a message:

```json
{
  "action": "post",
  "to": 0,
  "message": "Test message",
  "color": "#424242"
}
```

Where `message` is the message to send, `color` is the message color, and `to`
is the recipient of the message as their numerical ID.  A special value of `0`
means the message is public.  Negative values send broken messages, potentially
useful for keepalive.

To leave the room:

```json
{
  "action": "leave"
}
```

Redirects to `/rooms/<id>` with `post` or `/rooms` with `leave`.

Unauthenticated sessions get redirected to `/`.

### `GET /games/<game>`

Gets the status of a supported game.  Currently only *Lednička* is supported.

Unauthenticated sessions get redirected to `/`.

#### Lednička

```json
{
  "active": 1,
  "defrost": 0,
  "total": 0,
  "additions": [
    {
      "who": "contyk",
      "when": "18. listopadu v 4:41:12",
      "amount": 6,
      "method": "hodem"
    }
  ]
}
```

Where `active` deontes whether the user may play, `defrost` whether that method
is available, `total` holds the turn result after `POST` (see below), and
`additions` is a list of up to 50 last turns from all the users.

`additions` timestamps and methods are raw and generally in Czech.

### `POST /games/<game>`

Takes an action in a supported game.  Currently only *Lednička* is supported.

Unauthenticated sessions get redirected to `/`.

#### Lednička

Attempts to play a turn in *Lednička*.  Expects no request body.  The `method`
can be specified as an optional query parameter, e.g. `?method=k`.

Methods are passed directly to Alík.  Currently supported methods include `1`,
`h`, `m`, `M`, `d`, `k`, `c`, `r` and `o`.

If no method is specified, Malíček will choose a method with the highest
potential yield automatically.

Redirects to `/games/lednicka`.

### `GET /app/<file>`

Serves a file from the `public` directory.

If `malicek.tar.gz` is requested and the file doesn't exist or is older than
any of the currently used source files, Malíček creates a gzip'd tarball of
itself and serves that file.

## Clients

A very simple web client, suitable for handheld devices, is bundled; see the
Deployment section for how to access it.

Additionally, a proof-of-concept curses-based client can be found in
`public/cli.pl`.

Testing can be done directly with CUrl or any similar tool.

## Shortcomings

Due to Alík's chat design, it is impossible to join a room where you already
are without a valid chat cookie.  A simple workaround lies in joining a
different room to obtain the said chat cookie, leave, and join the original
room.  As an automatic workaround, Malíček attempts to leave every room before
joining.

Additionally Alík doesn't let users directly know when they've been kicked out
or have idled out.  Malíček could support additional workarounds to detect
these situations but currently does not.

Room admin features are currently unsupported.

## Deployment

Malíček is written in Perl and has several module dependencies:

* perl 5.16 or later
* Archive::Tar
* Dancer2
* File::stat
* File::Temp
* HTML::Entities
* HTTP::Cookies
* LWP::UserAgent

Dancer2 must support JSON serialization and Simple session caches.

### Simple endpoint

To run a simple endpoint, run Malíček directly and connect to port 3000:

`./malicek.pl`

### With the web application interface

To provide the bundled web application and TLS support (recommended), configure
a forward proxy that maps `/` requests to `/app/`, and `/api/` requests to `/`.

An example Nginx configuration snippet.

```
server {
  ...;
  port_in_redirect off;
  ...;
  location /api/ {
    proxy_pass http://192.168.0.10:3000/;
    proxy_redirect / $scheme://$host/api/;
    proxy_set_header Host malicek;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwaded_for;
  }
  location / {
    proxy_pass http://192.168.0.10:3000/app$uri$is_arg$args;
    proxy_set_header Host malicek;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwaded_for;
  }
```

## License

Petr Šabata <contyk@contyk.dev>, 2019-2020

Code licensed under MIT/X.  See `public/LICENSE.txt` for details.

The repository also includes `public/spinner.gif`, a CC0-licensed generated
loading animation from [Loading.io](https://loading.io).

Additionally, the `public/favicon.png` image is a glyph from the Noto Emoji
typeface, distributed under SIL Open Font License by
[Google](https://www.google.com/get/noto/).
