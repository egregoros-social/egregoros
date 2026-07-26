# End-to-end encrypted (E2EE) direct messages — proposal

> **Status: parked / not implemented.** E2EE DMs were implemented and then
> removed ahead of the Pleroma-compatibility work (see
> `pleroma_migration_plan.md`); big experimental features don't fit that
> migration. This document is kept as the design record in case we revive
> the feature later. Nothing described below currently exists in the code.

This document proposes a pragmatic E2EE direct-message design for **Egregoros** (PostgreSQL + Elixir/OTP + Phoenix + LiveView), with **encryption/decryption happening in the browser** and **no plaintext keys ever sent to the server**.

It focuses on:
- sensible **key management** (with **passkeys** as the best default)
- a concrete **envelope format**
- how to **publish and discover** keys via ActivityPub actor documents
- **key rotation** and **TOFU/key-change warnings**
- suggested **UI flows**

## Goals

- E2EE direct messages between **two ActivityPub actors** (1:1), including across servers.
- The server stores/delivers **only ciphertext** (and metadata required for federation).
- Client-only private keys: the server must never see the E2EE private key in plaintext.
- Multi-device should be possible without unsafe key handling.
- Keep dependency count low; prefer **WebCrypto + WebAuthn** over new crypto deps.

## Non-goals (v1)

- Group chats / multi-recipient E2EE.
- Full Signal-style forward secrecy (double-ratchet, prekeys). We can add later.
- “Protect against the server operator shipping malicious JS” unless the frontend is independently distributed (see Threat model).

## Threat model (explicit)

E2EE protects against:
- database dumps/backups/logs containing message content
- other servers and intermediaries learning plaintext
- honest-but-curious infra reading plaintext

E2EE **does not** protect against:
- a malicious/compromised server **delivering altered frontend JS** that exfiltrates keys

If we want “E2EE even vs instance operator”, we need at least one of:
- independently hosted frontend (different trust domain)
- signed/pinned assets (SRI + out-of-band verification)
- packaged app (native/PWA) with update signing

This proposal assumes the standard fediverse trust model: the server is trusted to serve the UI honestly, but not trusted to store/read message plaintext.

## Cryptographic design (v1)

### Long-term E2EE identity key per actor (client-generated)

- **Algorithm:** ECDH P-256 (WebCrypto-supported everywhere) + HKDF-SHA256 + AES-256-GCM.
- Each local user has one (or more, for rotation) long-term E2EE keypair:
  - `E2EE_PRIV` (client-only)
  - `E2EE_PUB` (public, published in actor doc)

Why P-256: WebCrypto compatibility. X25519 is nicer but not universally available without additional deps/wasm.

### Message encryption (static-static ECDH, implicit sender auth)

For a DM from `alice` → `bob`:
- Shared secret: `SS = ECDH(alice_priv, bob_pub)`
- Derive a per-message AEAD key:
  - `K = HKDF(SS, salt = msg_salt, info = "egregoros:e2ee:dm:v1")`
- Encrypt with AES-GCM using a random 96-bit nonce.

**Authentication property:** only someone with `alice_priv` can compute `SS` that `bob` can decrypt using `bob_priv + alice_pub`. This gives “implicit sender auth” assuming key pinning (TOFU) prevents MITM key substitution.

### AAD (binding metadata)

Use AES-GCM additional authenticated data (AAD) to bind:
- `sender_ap_id`
- `recipient_ap_id`
- `sender_kid`, `recipient_kid`
- the ActivityPub object `id` (or a stable `conversation_id`)

If a server mutates addressing/identity metadata, decryption fails.

### Forward secrecy (later)

We can evolve to:
- sender ephemeral ECDH per message + sender signatures using ECDSA P-256
- or full double-ratchet

v1 deliberately prioritizes simplicity.

## Key management options (recommended default: passkeys)

We need:
- local storage of `E2EE_PRIV` (for normal use)
- a way to recover `E2EE_PRIV` on a new device
- protection against offline guessing

### Option A (recommended): Passkeys (WebAuthn PRF / hmac-secret) to wrap the E2EE private key

**Idea:** generate `E2EE_PRIV` randomly once; store it on the server only as an **encrypted blob**. The blob is encrypted client-side with a high-entropy secret derived from a passkey, so it’s recoverable across devices that have the passkey (synced passkeys).

Flow:
1. User enables “Encrypted DMs”.
2. Client creates a passkey credential (WebAuthn). Require PRF/hmac-secret support if available.
3. Client generates `E2EE` keypair (WebCrypto).
4. Client derives a wrapping key:
   - call WebAuthn `get()` with PRF/hmac-secret using a stored `prf_salt` input
   - derive `WRAP_KEY` with HKDF (domain-separated)
5. Client exports `E2EE_PRIV` (JWK), encrypts it with AES-GCM using `WRAP_KEY`, uploads:
   - `credential_id` (public)
   - `prf_salt` (public)
   - `wrapped_private_key` (ciphertext)
   - `public_key` + metadata (`kid`, fingerprint)

Properties:
- Server never receives plaintext `E2EE_PRIV`.
- No offline brute-force via password guessing (the secret comes from a passkey, not a low-entropy password).
- Multi-device works if passkeys are synced (platform dependent).

Fallback requirement: PRF/hmac-secret support is not universal, so we must offer a fallback (Option B/C).

### Option B: Client-encrypted key backup with a dedicated E2EE passphrase (fallback)

Same as Option A, but `WRAP_KEY` is derived from an E2EE passphrase:
- `WRAP_KEY = PBKDF2(password, salt, iterations) -> HKDF -> AES-GCM`

Warning: if an attacker obtains both `wrapped_private_key` and `E2EE_PUB` (published), they can attempt offline guessing. Mitigations:
- enforce long passphrases and high KDF cost
- optionally recommend password managers

### Option C: Recovery code/seed (best “no brute-force” fallback)

Generate a random 32-byte recovery secret, display it once, encourage storing in a password manager.
- Use it as the wrap secret (like Option B but high entropy, not guessable).

### “Multiple wrappers” (recommended UX)

Store multiple encrypted wrappers for the same underlying `E2EE_PRIV`:
- wrapper #1: passkey-derived
- wrapper #2: recovery code-derived
- optional wrapper #3: passphrase-derived

This avoids lockout if passkey sync fails and avoids weak passphrases being the only recovery path.

## Publishing keys in ActivityPub actor docs

We need to publish `E2EE_PUB` (and key id / version) in the actor document so other clients can encrypt to us.

### Proposed representation

Add an extension field on the actor:

```json
{
  "egregoros:e2ee": {
    "version": 1,
    "keys": [
      {
        "kid": "e2ee-2025-12-26T10:00:00Z",
        "kty": "EC",
        "crv": "P-256",
        "x": "…base64url…",
        "y": "…base64url…",
        "created_at": "2025-12-26T10:00:00Z",
        "fingerprint": "sha256:…base64url…"
      }
    ]
  }
}
```

Notes:
- Use a JWK-like shape so browsers can import easily.
- `fingerprint` is the SHA-256 of the canonicalized public key (define canonicalization).
- Keep `keys` as an array to support rotation. The first entry is “active”.

### Discovery

When sending a DM:
- fetch recipient actor doc (prefer signed fetch if enabled)
- extract `egregoros:e2ee.keys[0]` (or matching `kid`)
- apply TOFU pinning (below)

## TOFU key pinning and key-change warnings

Without a PKI, we need key continuity.

### First contact (TOFU)

On first successful encrypted DM exchange with an actor:
- store `{recipient_ap_id, kid, fingerprint, first_seen_at}`

### On key change

If `fingerprint` changes for an actor:
- block “silent” encryption to the new key
- show a warning:
  - “Key changed since last contact”
  - show old/new fingerprints
  - require explicit user confirmation (“trust new key”)

### Storage

Store pinned remote keys server-side (safe; they’re public) or client-side (privacy).

Recommendation:
- server-side storage in a dedicated table for usability across devices
- but keep it behind a behaviour so we can later move to client-only or different backends

## Message envelope format

Store ciphertext as an AP object field (not as the only `content`), so we can show placeholders to other clients.

### `egregoros:e2ee_dm` payload

```json
{
  "version": 1,
  "alg": "ECDH-P256+HKDF-SHA256+AES-256-GCM",
  "sender": {
    "ap_id": "https://example.com/users/alice",
    "kid": "e2ee-…"
  },
  "recipient": {
    "ap_id": "https://remote.example/users/bob",
    "kid": "e2ee-…"
  },
  "nonce": "…base64url(12 bytes)…",
  "salt": "…base64url(16–32 bytes)…",
  "aad": {
    "object_id": "https://example.com/objects/…",
    "context": "https://example.com/contexts/…"
  },
  "ciphertext": "…base64url…"
}
```

Encryption inputs:
- `salt` is HKDF salt (random per message)
- `nonce` is AES-GCM nonce (random per message)
- AAD bytes are a canonical JSON encoding of `sender/recipient/kid/object_id/context`

### ActivityPub object representation

Use a `Note` (or `ChatMessage`) with:
- `to: [recipient_ap_id]` and no Public address
- plaintext `content` is a placeholder (e.g. “Encrypted message”)
- encrypted payload stored under `egregoros:e2ee_dm`

Example (object):

```json
{
  "type": "Note",
  "id": "https://example.com/objects/…",
  "actor": "https://example.com/users/alice",
  "to": ["https://remote.example/users/bob"],
  "content": "<p><em>Encrypted message</em></p>",
  "egregoros:e2ee_dm": { "...": "..." }
}
```

### Rendering behavior

In Egregoros LiveView:
- if `egregoros:e2ee_dm` present and the viewer has an applicable `E2EE_PRIV`, attempt decrypt
- show decrypted plaintext content (sanitized / text-mode depending on local policy)
- if decrypt fails:
  - show placeholder + reason (“missing key”, “key changed”, “corrupt payload”)

## Key rotation

### Local rotation

Allow a user to:
- generate a new E2EE keypair client-side
- publish new `kid` + `E2EE_PUB`
- keep old private keys for decrypting old DMs

### Remote compatibility

When receiving an encrypted DM:
- select `recipient.kid` for which we have a private key
- if unknown `kid`, show “You need to sync your keys (new device?)” or “sender used an unknown recipient key”

## Suggested data model (server-side)

Add tables (names illustrative):

### `e2ee_keys` (local users)
- `user_id` (FK)
- `kid` (unique per user)
- `public_key_jwk` (jsonb)
- `fingerprint` (text)
- `active` (bool)
- `inserted_at`, `updated_at`

### `e2ee_key_wrappers` (optional, recommended)
- `user_id` (FK)
- `kid` (which E2EE key this wrapper unlocks)
- `type` (`webauthn_prf` | `recovery_code` | `passphrase`)
- `wrapped_private_key` (bytea or text)
- `params` (jsonb; includes `credential_id`, `prf_salt`, pbkdf2 params, etc.)

### `e2ee_pins` (TOFU)
- `owner_user_id` (FK; whose pin list)
- `remote_actor_ap_id`
- `kid`
- `fingerprint`
- `first_seen_at`
- `last_seen_at`
- unique `(owner_user_id, remote_actor_ap_id)`

All of this is public metadata or ciphertext blobs; no plaintext secrets.

## UI flows (LiveView + JS hooks)

### Enable E2EE
1. Settings → “Encrypted DMs” → Enable
2. Preferred: “Use passkey” (create passkey)
3. Generate E2EE keypair
4. Offer “Create recovery code” (recommended)
5. Confirm: “Encrypted DMs enabled”

### New device bootstrap
1. Login normally (server session)
2. Settings banner: “Encrypted DMs locked on this device”
3. Unlock via:
   - passkey (if wrapper exists), OR
   - recovery code, OR
   - passphrase
4. Store decrypted `E2EE_PRIV` locally (encrypted at rest with OS + optional local rewrap)

### Key change warning (TOFU)
1. User opens DM thread or composes a DM
2. Client fetches recipient actor doc; fingerprint differs from pinned
3. Modal: “Recipient encryption key changed”
   - show old/new fingerprint
   - actions: “Trust new key”, “Cancel”

### Rotate keys
1. Settings → “Encrypted DMs” → Rotate key
2. Warn: “Old messages require old keys; keep them”
3. Generate new keypair; publish new `kid` as active
4. (Optional) rewrap old keys under current wrappers

## Implementation plan (phased)

Phase 1 (local-only UX, no federation changes):
- Implement client key generation + local storage
- Implement envelope creation/decryption in JS
- Store ciphertext in objects `data` and render decrypted content only in LiveView

Phase 2 (publish keys, cross-server DMs):
- Add actor doc `egregoros:e2ee` field for local users
- Add remote key discovery + TOFU pins
- Encrypt outbound DMs to remote actors and decrypt inbound

Phase 3 (recovery/multi-device):
- Add passkey wrapper support (PRF/hmac-secret where available)
- Add recovery code wrappers
- Add “locked/unlocked” UI states

Phase 4 (hardening):
- richer key-change UX
- optional message-level signatures
- rate limiting / abuse considerations for DM payloads

## Appendix: Notes on the ActivityPub-MLS draft

There is an early draft exploring **Messaging Layer Security (MLS)** as an E2EE layer transported over ActivityPub: `https://swicg.github.io/activitypub-e2ee/mls`.

Key takeaways (for Egregoros):
- The document’s “ActivityPub envelope, MLS binary payload, app-data inside MLS” layering matches our direction: keep servers unaware of plaintext, but still use ActivityPub routing.
- It explicitly calls out **key substitution** as a core risk when servers publish user keys. This aligns with our TOFU + key-change warnings, but MLS implementations typically want a stronger verification story.
- It suggests a `keyPackages` actor property and lifecycle (Create/Add/Remove/Delete) that maps well to a **per-device key model** if we later choose to go beyond a single per-account key.

Where we should likely diverge (at least for v1):
- Full MLS support (RFC 9420) is a large implementation surface in the browser; for v1 1:1 DMs we should keep the simpler ECDH+AEAD design and keep “MLS later” as an evolution path.
- The draft’s “self-contained encrypted app data” approach discourages external URLs and suggests embedding binary content as base64; for real-world media this will be too heavy for federation and should be replaced with “encrypted blobs + separate fetch” designs.
