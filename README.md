# joke-wall

A LEZ/SPEL voting app. Admin creates a session, participants submit jokes, and anyone can vote for the funniest one.

## Architecture

```
joke-wall/
├── methods/guest/src/bin/joke_wall.rs   # On-chain program (5 instructions)
├── joke_wall_core/src/lib.rs            # Shared types (JokeEntry)
├── examples/src/bin/joke_wall_cli.rs    # CLI wrapper around spel
├── ui/ffi/src/lib.rs                    # C FFI for Qt/QML UI
├── joke-wall-idl.json                   # Program IDL (hand-crafted; regenerate with make idl)
├── spel.toml                            # IDL + binary paths for bare spel CLI
└── Makefile                             # Build targets
```

### On-chain state

One `SessionState` PDA per session, derived from `["session_v1", admin]`:

| Field         | Type            | Description                    |
|---------------|-----------------|--------------------------------|
| `admin`       | `[u8; 32]`      | Session creator's account ID   |
| `description` | `String`        | Human-readable session title   |
| `is_active`   | `bool`          | False after `close_session`    |
| `jokes`       | `Vec<JokeEntry>`| All submitted jokes with votes |

Each `JokeEntry` (stored inline):

| Field        | Type       | Description                    |
|--------------|------------|--------------------------------|
| `submitter`  | `[u8; 32]` | Who submitted the joke         |
| `content`    | `String`   | The joke text                  |
| `vote_count` | `u64`      | Number of votes received       |

### Instructions

| Instruction      | Signer    | Description                                  |
|------------------|-----------|----------------------------------------------|
| `create_session` | admin     | Creates a new session PDA                    |
| `submit_joke`    | submitter | Appends a joke to the session                |
| `vote`           | voter     | Increments vote_count of `jokes[joke_index]` |
| `close_session`  | admin     | Marks session inactive                       |
| `reveal`         | —         | Read-only; use with `spel inspect`           |

## Quick start

### 1. Build

Requires the RISC Zero toolchain (`cargo risczero`) and LEZ dev environment.

```bash
make build
```

### 2. Generate IDL

```bash
make idl
```

### 3. Deploy

```bash
make deploy
# Note the printed ProgramId (64-char hex)
export JOKE_WALL_PROGRAM_ID_HEX=<hex>
```

### 4. Create accounts

```bash
make setup
# Creates ADMIN_ID and VOTER_ID, saved to .joke_wall-state
```

### 5. Run a full demo

```bash
# Admin creates a session
make cli ARGS="create_session --description 'Best Jokes 2026' --admin Public/$ADMIN_ID"

# Two participants submit jokes
make cli ARGS="submit_joke --content 'Why do programmers prefer dark mode? Because light attracts bugs.' --submitter Public/$VOTER_ID --admin Public/$ADMIN_ID"
make cli ARGS="submit_joke --content 'A SQL query walks into a bar, walks up to two tables and asks... Can I join you?' --submitter Public/$ADMIN_ID --admin Public/$ADMIN_ID"

# Anyone votes
make cli ARGS="vote --joke_index 0 --voter Public/$VOTER_ID --admin Public/$ADMIN_ID"
make cli ARGS="vote --joke_index 1 --voter Public/$ADMIN_ID --admin Public/$ADMIN_ID"

# Inspect results
spel reveal --admin Public/$ADMIN_ID
spel inspect <session-pda> --type SessionState

# Admin closes session
make cli ARGS="close_session --admin Public/$ADMIN_ID"
```

## Environment variables

| Variable                    | Description                         |
|-----------------------------|-------------------------------------|
| `NSSA_WALLET_HOME_DIR`      | Path to wallet directory            |
| `NSSA_SEQUENCER_URL`        | LEZ sequencer RPC URL               |
| `JOKE_WALL_PROGRAM_ID_HEX`  | 64-char hex program ID after deploy |

## FFI (Qt UI)

The `ui/ffi` crate exports a C ABI for embedding in Qt/QML applications:

```c
char* joke_wall_create_session(const char* args_json);
char* joke_wall_submit_joke(const char* args_json);
char* joke_wall_vote(const char* args_json);
char* joke_wall_close_session(const char* args_json);
char* joke_wall_fetch_state_json(const char* args_json);
void  joke_wall_free_string(char* s);
```

Each function takes a JSON string and returns `{"success":true,...}` or `{"success":false,"error":"..."}`.

See [whisper-wall](https://github.com/logos-co/whisper-wall) for a complete Qt/QML UI implementation using the same FFI pattern.

## Notes

- **One session per admin**: The session PDA is seeded by the admin account, so each admin has exactly one active session address.
- **Inline joke storage**: All jokes are stored in the single session account. For production use with many jokes, consider a separate PDA per joke.
- **No double-vote prevention**: Voters can cast multiple votes. For a production app, add a vote tracking PDA.
- **IDL regeneration**: Run `make idl` after modifying instruction signatures to keep `joke-wall-idl.json` in sync.
