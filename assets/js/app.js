// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/egregoros"
import topbar from "../vendor/topbar"
import TimelineTopSentinel from "./hooks/timeline_top_sentinel"
import TimelineBottomSentinel from "./hooks/timeline_bottom_sentinel"
import ComposePanel from "./hooks/compose_panel"
import ComposeCharCounter from "./hooks/compose_char_counter"
import ComposeSettings from "./hooks/compose_settings"
import ComposeMentions from "./hooks/compose_mentions"
import EmojiPicker from "./hooks/emoji_picker"
import ReactionPicker from "./hooks/reaction_picker"
import MediaViewer from "./hooks/media_viewer"
import ReplyModal from "./hooks/reply_modal"
import ScrollRestore from "./hooks/scroll_restore"
import StatusAutoScroll from "./hooks/status_auto_scroll"
import DMChatScroller from "./hooks/dm_chat_scroller"
import AudioPlayer from "./hooks/audio_player"
import VideoPlayer from "./hooks/video_player"
import {initImageCropper} from "./hooks/image_cropper"
import {BIP39_ENGLISH_WORDS} from "./bip39_english_words"
import {decryptE2EEDM as decryptE2EEDMOffline, encryptE2EEDM} from "./lib/e2ee_dm.mjs"

const base64UrlEncode = bytes => {
  let binary = ""
  const len = bytes.length

  for (let i = 0; i < len; i++) binary += String.fromCharCode(bytes[i])

  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "")
}

const base64UrlDecode = value => {
  if (typeof value !== "string" || value.length === 0) return new Uint8Array(0)

  const base64 = value.replace(/-/g, "+").replace(/_/g, "/")
  const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), "=")
  const binary = atob(padded)

  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}

const utf8Bytes = value => new TextEncoder().encode(value)

const randomBytes = len => {
  const out = new Uint8Array(len)
  crypto.getRandomValues(out)
  return out
}

const bytesToBinary = bytes => Array.from(bytes).map(byte => byte.toString(2).padStart(8, "0")).join("")

const sha256Bytes = async bytes => {
  const digest = await crypto.subtle.digest("SHA-256", bytes)
  return new Uint8Array(digest)
}

const bip39WordIndex = new Map(BIP39_ENGLISH_WORDS.map((word, i) => [word, i]))

const entropyToMnemonic24 = async entropyBytes => {
  if (!(entropyBytes instanceof Uint8Array) || entropyBytes.length !== 32) {
    throw new Error("invalid_entropy")
  }

  const entropyBits = bytesToBinary(entropyBytes)
  const checksumBits = bytesToBinary(await sha256Bytes(entropyBytes)).slice(0, 8)
  const bits = entropyBits + checksumBits

  const words = []
  for (let i = 0; i < 24; i++) {
    const chunk = bits.slice(i * 11, i * 11 + 11)
    const index = Number.parseInt(chunk, 2)
    const word = BIP39_ENGLISH_WORDS[index]
    if (!word) throw new Error("invalid_word_index")
    words.push(word)
  }

  return words.join(" ")
}

const normalizeMnemonic = phrase => {
  if (typeof phrase !== "string") return ""
  return phrase
    .trim()
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean)
    .join(" ")
}

const mnemonic24ToEntropy = async phrase => {
  const normalized = normalizeMnemonic(phrase)
  if (!normalized) throw new Error("invalid_mnemonic")

  const words = normalized.split(" ")
  if (words.length !== 24) throw new Error("invalid_mnemonic_length")

  const bits = words
    .map(word => {
      const index = bip39WordIndex.get(word)
      if (typeof index !== "number") throw new Error("invalid_mnemonic_word")
      return index.toString(2).padStart(11, "0")
    })
    .join("")

  const entropyBits = bits.slice(0, 256)
  const checksumBits = bits.slice(256)

  const entropyBytes = new Uint8Array(32)
  for (let i = 0; i < 32; i++) {
    const byteBits = entropyBits.slice(i * 8, i * 8 + 8)
    entropyBytes[i] = Number.parseInt(byteBits, 2)
  }

  const checksumExpected = bytesToBinary(await sha256Bytes(entropyBytes)).slice(0, 8)
  if (checksumBits !== checksumExpected) throw new Error("invalid_mnemonic_checksum")

  return entropyBytes
}

const parseJsonBody = async response => response.json().catch(() => ({}))

const setE2EEFeedback = (section, message, variant) => {
  const feedback = section.querySelector("[data-role='e2ee-feedback']")
  if (!feedback) return

  feedback.textContent = message
  feedback.classList.remove("hidden")

  feedback.classList.remove(
    "text-rose-600",
    "dark:text-rose-400",
    "text-emerald-700",
    "dark:text-emerald-300",
    "text-slate-600",
    "dark:text-slate-300"
  )

  if (variant === "success") {
    feedback.classList.add("text-emerald-700", "dark:text-emerald-300")
  } else if (variant === "info") {
    feedback.classList.add("text-slate-600", "dark:text-slate-300")
  } else {
    feedback.classList.add("text-rose-600", "dark:text-rose-400")
  }
}

const setPasskeyFeedback = (feedback, message, variant) => {
  if (!feedback) return
  feedback.textContent = message
  feedback.classList.remove("hidden")

  feedback.classList.remove(
    "text-rose-600",
    "dark:text-rose-400",
    "text-emerald-700",
    "dark:text-emerald-300",
    "text-slate-600",
    "dark:text-slate-300"
  )

  if (variant === "success") {
    feedback.classList.add("text-emerald-700", "dark:text-emerald-300")
  } else if (variant === "info") {
    feedback.classList.add("text-slate-600", "dark:text-slate-300")
  } else {
    feedback.classList.add("text-rose-600", "dark:text-rose-400")
  }
}

const passkeysSupported = () =>
  !!(window.PublicKeyCredential && navigator.credentials?.create && navigator.credentials?.get)

const registerWithPasskey = async (form, button, feedback) => {
  if (!passkeysSupported()) {
    setPasskeyFeedback(feedback, "Passkeys (WebAuthn) are not supported in this browser.", "error")
    return
  }

  if (!window.isSecureContext) {
    setPasskeyFeedback(feedback, "Passkeys require HTTPS (secure context).", "error")
    return
  }

  const nicknameInput = form.querySelector("input[name='registration[nickname]']")
  const emailInput = form.querySelector("input[name='registration[email]']")
  const returnToInput = form.querySelector("input[name='registration[return_to]']")

  const nickname = nicknameInput?.value?.trim() || ""
  const email = emailInput?.value?.trim() || ""
  const returnTo = returnToInput?.value || ""

  if (!nickname) {
    setPasskeyFeedback(feedback, "Nickname can't be empty.", "error")
    nicknameInput?.focus?.()
    return
  }

  button.disabled = true
  setPasskeyFeedback(feedback, "Creating passkey…", "info")

  let optionsResponse
  try {
    optionsResponse = await fetch("/passkeys/registration/options", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "content-type": "application/json",
        accept: "application/json",
        "x-csrf-token": csrfToken,
      },
      body: JSON.stringify({nickname, email, return_to: returnTo}),
    })
  } catch (error) {
    console.error("passkey registration options failed", error)
    setPasskeyFeedback(feedback, "Could not start passkey registration (network error).", "error")
    button.disabled = false
    return
  }

  if (!optionsResponse.ok) {
    const body = await parseJsonBody(optionsResponse)
    const message =
      body?.error === "nickname_taken"
        ? "Nickname is already registered."
        : body?.error === "email_taken"
          ? "Email is already registered."
          : "Could not start passkey registration."

    setPasskeyFeedback(feedback, message, "error")
    button.disabled = false
    return
  }

  const optionsBody = await parseJsonBody(optionsResponse)
  const publicKey = optionsBody?.publicKey

  if (!publicKey?.challenge || !publicKey?.user?.id) {
    setPasskeyFeedback(feedback, "Passkey registration failed (invalid server response).", "error")
    button.disabled = false
    return
  }

  const creationOptions = {
    ...publicKey,
    challenge: base64UrlDecode(publicKey.challenge),
    user: {...publicKey.user, id: base64UrlDecode(publicKey.user.id)},
  }

  let created
  try {
    created = await navigator.credentials.create({publicKey: creationOptions})
  } catch (error) {
    console.error("passkey create failed", error)
    setPasskeyFeedback(feedback, "Could not create a passkey (cancelled or unsupported).", "error")
    button.disabled = false
    return
  }

  const credential = {
    id: base64UrlEncode(new Uint8Array(created.rawId)),
    rawId: base64UrlEncode(new Uint8Array(created.rawId)),
    type: created.type,
    response: {
      attestationObject: base64UrlEncode(new Uint8Array(created.response.attestationObject)),
      clientDataJSON: base64UrlEncode(new Uint8Array(created.response.clientDataJSON)),
    },
  }

  let finishResponse
  try {
    finishResponse = await fetch("/passkeys/registration/finish", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "content-type": "application/json",
        accept: "application/json",
        "x-csrf-token": csrfToken,
      },
      body: JSON.stringify({credential}),
    })
  } catch (error) {
    console.error("passkey registration finish failed", error)
    setPasskeyFeedback(feedback, "Could not finish passkey registration (network error).", "error")
    button.disabled = false
    return
  }

  if (!finishResponse.ok) {
    const body = await parseJsonBody(finishResponse)
    console.error("passkey registration finish response", finishResponse.status, body)
    setPasskeyFeedback(feedback, "Could not finish passkey registration.", "error")
    button.disabled = false
    return
  }

  const finishBody = await parseJsonBody(finishResponse)
  window.location.assign(finishBody?.redirect_to || "/")
}

const loginWithPasskey = async (form, button, feedback) => {
  if (!passkeysSupported()) {
    setPasskeyFeedback(feedback, "Passkeys (WebAuthn) are not supported in this browser.", "error")
    return
  }

  if (!window.isSecureContext) {
    setPasskeyFeedback(feedback, "Passkeys require HTTPS (secure context).", "error")
    return
  }

  const nicknameInput = form.querySelector("input[name='session[nickname]']")
  const returnToInput = form.querySelector("input[name='session[return_to]']")

  const nickname = nicknameInput?.value?.trim() || ""
  const returnTo = returnToInput?.value || ""

  if (!nickname) {
    setPasskeyFeedback(feedback, "Nickname can't be empty.", "error")
    nicknameInput?.focus?.()
    return
  }

  button.disabled = true
  setPasskeyFeedback(feedback, "Waiting for passkey…", "info")

  let optionsResponse
  try {
    optionsResponse = await fetch("/passkeys/authentication/options", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "content-type": "application/json",
        accept: "application/json",
        "x-csrf-token": csrfToken,
      },
      body: JSON.stringify({nickname, return_to: returnTo}),
    })
  } catch (error) {
    console.error("passkey authentication options failed", error)
    setPasskeyFeedback(feedback, "Could not start passkey login (network error).", "error")
    button.disabled = false
    return
  }

  if (!optionsResponse.ok) {
    setPasskeyFeedback(feedback, "No passkey credentials found for this nickname.", "error")
    button.disabled = false
    return
  }

  const optionsBody = await parseJsonBody(optionsResponse)
  const publicKey = optionsBody?.publicKey

  if (!publicKey?.challenge || !publicKey?.rpId) {
    setPasskeyFeedback(feedback, "Passkey login failed (invalid server response).", "error")
    button.disabled = false
    return
  }

  const allowCredentials = Array.isArray(publicKey.allowCredentials) ? publicKey.allowCredentials : []

  const assertionOptions = {
    ...publicKey,
    challenge: base64UrlDecode(publicKey.challenge),
    allowCredentials: allowCredentials.map(entry => ({
      ...entry,
      id: base64UrlDecode(entry.id),
    })),
  }

  let assertion
  try {
    assertion = await navigator.credentials.get({publicKey: assertionOptions})
  } catch (error) {
    console.error("passkey get failed", error)
    setPasskeyFeedback(feedback, "Could not use the passkey (cancelled or unsupported).", "error")
    button.disabled = false
    return
  }

  const credential = {
    id: base64UrlEncode(new Uint8Array(assertion.rawId)),
    rawId: base64UrlEncode(new Uint8Array(assertion.rawId)),
    type: assertion.type,
    response: {
      authenticatorData: base64UrlEncode(new Uint8Array(assertion.response.authenticatorData)),
      clientDataJSON: base64UrlEncode(new Uint8Array(assertion.response.clientDataJSON)),
      signature: base64UrlEncode(new Uint8Array(assertion.response.signature)),
    },
  }

  let finishResponse
  try {
    finishResponse = await fetch("/passkeys/authentication/finish", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "content-type": "application/json",
        accept: "application/json",
        "x-csrf-token": csrfToken,
      },
      body: JSON.stringify({credential}),
    })
  } catch (error) {
    console.error("passkey login finish failed", error)
    setPasskeyFeedback(feedback, "Could not finish passkey login (network error).", "error")
    button.disabled = false
    return
  }

  if (!finishResponse.ok) {
    setPasskeyFeedback(feedback, "Passkey login failed.", "error")
    button.disabled = false
    return
  }

  const finishBody = await parseJsonBody(finishResponse)
  window.location.assign(finishBody?.redirect_to || "/")
}

const initPasskeyAuth = () => {
  const registerButton = document.querySelector("[data-role='passkey-register-button']")
  if (registerButton && registerButton.dataset.passkeyInit !== "true") {
    registerButton.dataset.passkeyInit = "true"
    const form = registerButton.closest("form")
    const feedback = form?.querySelector("[data-role='passkey-register-feedback']")
    registerButton.addEventListener("click", () => form && registerWithPasskey(form, registerButton, feedback))
  }

  const loginButton = document.querySelector("[data-role='passkey-login-button']")
  if (loginButton && loginButton.dataset.passkeyInit !== "true") {
    loginButton.dataset.passkeyInit = "true"
    const form = loginButton.closest("form") || document.querySelector("form#login-form")
    const feedback =
      form?.querySelector("[data-role='passkey-login-feedback']") ||
      document.querySelector("[data-role='passkey-login-feedback']")
    loginButton.addEventListener("click", () => form && loginWithPasskey(form, loginButton, feedback))
  }
}

const enableE2EEWithMnemonic = async (section, button, csrfToken) => {
  if (!window.isSecureContext) {
    setE2EEFeedback(section, "Encrypted DMs require HTTPS (secure context).", "error")
    return
  }

  if (!window.crypto?.subtle) {
    setE2EEFeedback(section, "WebCrypto is not available in this browser.", "error")
    return
  }

  button.disabled = true
  setE2EEFeedback(section, "Generating a 24-word recovery phrase…", "info")

  let entropy
  let mnemonic

  try {
    entropy = randomBytes(32)
    mnemonic = await entropyToMnemonic24(entropy)
  } catch (error) {
    console.error("mnemonic generation failed", error)
    setE2EEFeedback(section, "Could not generate a recovery phrase.", "error")
    button.disabled = false
    return
  }

  const mnemonicBox = section.querySelector("[data-role='e2ee-mnemonic-box']")
  if (mnemonicBox) mnemonicBox.classList.remove("hidden")

  const mnemonicEl = section.querySelector("[data-role='e2ee-mnemonic']")
  if (mnemonicEl) {
    mnemonicEl.textContent = mnemonic
    mnemonicEl.classList.remove("hidden")
  }

  if (
    !window.confirm(
      "Write down these 24 words somewhere safe. They are the only way to unlock encrypted DMs on a new device.\n\nContinue?"
    )
  ) {
    setE2EEFeedback(section, "Cancelled.", "info")
    button.disabled = false
    return
  }

  setE2EEFeedback(section, "Generating E2EE identity key…", "info")

  const hkdfSalt = randomBytes(32)
  const infoStr = "egregoros:e2ee:wrap:mnemonic:v1"

  let wrapKey
  try {
    const secretKey = await crypto.subtle.importKey("raw", entropy, "HKDF", false, ["deriveKey"])

    wrapKey = await crypto.subtle.deriveKey(
      {name: "HKDF", hash: "SHA-256", salt: hkdfSalt, info: utf8Bytes(infoStr)},
      secretKey,
      {name: "AES-GCM", length: 256},
      false,
      ["encrypt", "decrypt"]
    )
  } catch (error) {
    console.error("hkdf derive failed", error)
    setE2EEFeedback(section, "Could not derive wrapping key.", "error")
    button.disabled = false
    return
  }

  let e2eeKeyPair
  try {
    e2eeKeyPair = await crypto.subtle.generateKey({name: "ECDH", namedCurve: "P-256"}, true, [
      "deriveBits",
    ])
  } catch (error) {
    console.error("generate E2EE keypair failed", error)
    setE2EEFeedback(section, "Could not generate E2EE keys.", "error")
    button.disabled = false
    return
  }

  const publicJwkFull = await crypto.subtle.exportKey("jwk", e2eeKeyPair.publicKey)
  const privateJwkFull = await crypto.subtle.exportKey("jwk", e2eeKeyPair.privateKey)

  const publicJwk = {
    kty: publicJwkFull.kty,
    crv: publicJwkFull.crv,
    x: publicJwkFull.x,
    y: publicJwkFull.y,
  }

  const kid = `e2ee-${new Date().toISOString()}`
  const plaintext = utf8Bytes(JSON.stringify(privateJwkFull))
  const iv = randomBytes(12)

  let ciphertext
  try {
    ciphertext = await crypto.subtle.encrypt({name: "AES-GCM", iv}, wrapKey, plaintext)
  } catch (error) {
    console.error("wrap encrypt failed", error)
    setE2EEFeedback(section, "Could not encrypt E2EE private key.", "error")
    button.disabled = false
    return
  }

  setE2EEFeedback(section, "Saving encrypted key material…", "info")

  const payload = {
    kid,
    public_key_jwk: publicJwk,
    wrapper: {
      type: "recovery_mnemonic_v1",
      wrapped_private_key: base64UrlEncode(new Uint8Array(ciphertext)),
      params: {
        hkdf_salt: base64UrlEncode(hkdfSalt),
        iv: base64UrlEncode(iv),
        alg: "A256GCM",
        kdf: "HKDF-SHA256",
        info: infoStr,
        wordlist: "bip39-en",
        words: 24,
      },
    },
  }

  let response
  try {
    response = await fetch("/settings/e2ee/mnemonic", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "content-type": "application/json",
        accept: "application/json",
        "x-csrf-token": csrfToken,
      },
      body: JSON.stringify(payload),
    })
  } catch (error) {
    console.error("save e2ee failed", error)
    setE2EEFeedback(section, "Could not save key material (network error).", "error")
    button.disabled = false
    return
  }

  if (!response.ok) {
    const body = await response.json().catch(() => ({}))
    console.error("save e2ee response", response.status, body)

    const message =
      body?.error === "already_enabled"
        ? "Encrypted DMs are already enabled."
        : "Could not enable encrypted DMs."

    setE2EEFeedback(section, message, "error")
    button.disabled = false
    return
  }

  const body = await response.json().catch(() => ({}))
  const statusEl = section.querySelector("[data-role='e2ee-status']")
  if (statusEl) statusEl.textContent = "Enabled"

  const fingerprintEl = section.querySelector("[data-role='e2ee-fingerprint']")
  if (fingerprintEl) {
    fingerprintEl.textContent = body.fingerprint
      ? `Fingerprint: ${body.fingerprint}`
      : "Fingerprint: (unknown)"
    fingerprintEl.classList.remove("hidden")
  }

  e2eeIdentity = {
    kid,
    publicKeyJwk: publicJwk,
    privateKey: e2eeKeyPair.privateKey,
  }

  window.egregorosE2EE = e2eeIdentity
  storeE2EEPrivateJwk(kid, privateJwkFull)
  window.dispatchEvent(new CustomEvent("egregoros:e2ee-unlocked", {detail: {kid}}))
  e2eeStatusCache = null

  setE2EEFeedback(section, "Encrypted DMs enabled. Store your recovery phrase somewhere safe.", "success")
  button.classList.add("hidden")
}

const initE2EESettings = () => {
  document.querySelectorAll("[data-role='e2ee-settings']").forEach(section => {
    if (section.dataset.e2eeInitialized === "true") return
    section.dataset.e2eeInitialized = "true"

    const copyButton = section.querySelector("[data-role='e2ee-mnemonic-copy']")
    if (copyButton) {
      copyButton.addEventListener("click", async () => {
        const mnemonic = section.querySelector("[data-role='e2ee-mnemonic']")?.textContent || ""
        if (!mnemonic) return

        try {
          if (!navigator.clipboard?.writeText) throw new Error("clipboard_unsupported")
          await navigator.clipboard.writeText(mnemonic)
          setE2EEFeedback(section, "Copied recovery phrase.", "success")
        } catch (error) {
          console.error("mnemonic copy failed", error)
          setE2EEFeedback(section, "Could not copy recovery phrase.", "error")
        }
      })
    }

    const button = section.querySelector("[data-role='e2ee-enable-mnemonic']")
    if (!button) return

    button.addEventListener("click", () => enableE2EEWithMnemonic(section, button, csrfToken))
  })
}

// ═══════════════════════════════════════════════════════════
// E2EE DIRECT MESSAGES (client-side encryption/decryption)
// ═══════════════════════════════════════════════════════════

let e2eeStatusCache = null
let e2eeStatusPromise = null

const fetchE2EEStatus = async () => {
  if (e2eeStatusCache) return e2eeStatusCache
  if (e2eeStatusPromise) return e2eeStatusPromise

  e2eeStatusPromise = fetch("/settings/e2ee", {
    method: "GET",
    credentials: "same-origin",
    headers: {accept: "application/json"},
  })
    .then(async response => {
      const body = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(body?.error || "e2ee_status_failed")
      e2eeStatusCache = body
      return body
    })
    .finally(() => {
      e2eeStatusPromise = null
    })

  return e2eeStatusPromise
}

const sliceArrayBuffer = bytes => {
  const buffer = bytes.buffer
  return buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)
}

let e2eeIdentity = null
let e2eeUnlockPromise = null

const e2eeIdentityStorageKey = kid => {
  if (!kid) return null
  return `egregoros:e2ee:identity:v1:${kid}`
}

const loadStoredE2EEPrivateJwk = kid => {
  const key = e2eeIdentityStorageKey(kid)
  if (!key) return null

  try {
    const raw = window.localStorage?.getItem?.(key)
    if (!raw) return null
    const decoded = JSON.parse(raw)
    if (!decoded?.private_jwk) return null
    return decoded.private_jwk
  } catch (_error) {
    return null
  }
}

const storeE2EEPrivateJwk = (kid, privateJwk) => {
  const key = e2eeIdentityStorageKey(kid)
  if (!key || !privateJwk) return

  try {
    window.localStorage?.setItem?.(
      key,
      JSON.stringify({kid, private_jwk: privateJwk, stored_at: new Date().toISOString()})
    )
  } catch (_error) {
    // ignore storage failures (private mode, quota, disabled storage)
  }
}

const clearStoredE2EEPrivateJwk = kid => {
  const key = e2eeIdentityStorageKey(kid)
  if (!key) return

  try {
    window.localStorage?.removeItem?.(key)
  } catch (_error) {
    // ignore storage failures
  }
}

let e2eeRestorePromise = null

const restoreE2EEIdentityFromStorage = async () => {
  if (e2eeIdentity?.privateKey) return e2eeIdentity
  if (e2eeRestorePromise) return e2eeRestorePromise

  e2eeRestorePromise = (async () => {
    let status
    try {
      status = await fetchE2EEStatus()
    } catch (_error) {
      return null
    }

    if (!status?.enabled || !status?.active_key?.kid) return null

    const kid = status.active_key.kid
    const stored = loadStoredE2EEPrivateJwk(kid)
    if (!stored) return null

    let privateKey
    try {
      privateKey = await crypto.subtle.importKey(
        "jwk",
        stored,
        {name: "ECDH", namedCurve: "P-256"},
        false,
        ["deriveBits"]
      )
    } catch (error) {
      console.error("stored e2ee identity import failed", error)
      clearStoredE2EEPrivateJwk(kid)
      return null
    }

    e2eeIdentity = {
      kid,
      publicKeyJwk: status.active_key.public_key_jwk,
      privateKey,
    }

    window.egregorosE2EE = e2eeIdentity
    window.dispatchEvent(new CustomEvent("egregoros:e2ee-unlocked", {detail: {kid}}))
    return e2eeIdentity
  })().finally(() => {
    e2eeRestorePromise = null
  })

  return e2eeRestorePromise
}

const unlockE2EEIdentity = async () => {
  if (e2eeIdentity?.privateKey) return e2eeIdentity
  if (e2eeUnlockPromise) return e2eeUnlockPromise

  e2eeUnlockPromise = (async () => {
    const status = await fetchE2EEStatus()

    if (!status?.enabled || !status?.active_key) throw new Error("e2ee_not_enabled")

    const stored = loadStoredE2EEPrivateJwk(status.active_key.kid)

    if (stored) {
      try {
        const privateKey = await crypto.subtle.importKey(
          "jwk",
          stored,
          {name: "ECDH", namedCurve: "P-256"},
          false,
          ["deriveBits"]
        )

        e2eeIdentity = {
          kid: status.active_key.kid,
          publicKeyJwk: status.active_key.public_key_jwk,
          privateKey,
        }

        window.egregorosE2EE = e2eeIdentity
        window.dispatchEvent(new CustomEvent("egregoros:e2ee-unlocked", {detail: {kid: e2eeIdentity.kid}}))
        return e2eeIdentity
      } catch (error) {
        console.error("stored e2ee identity unlock failed", error)
        clearStoredE2EEPrivateJwk(status.active_key.kid)
      }
    }

    const wrapper = (status?.wrappers || []).find(w => w?.type === "recovery_mnemonic_v1")
    if (!wrapper) throw new Error("e2ee_no_mnemonic_wrapper")

    const params = wrapper.params || {}
    const hkdfSalt = params.hkdf_salt
    const iv = params.iv
    const info = params.info || "egregoros:e2ee:wrap:mnemonic:v1"

    if (!hkdfSalt || !iv) throw new Error("e2ee_wrapper_invalid")

    const phrase = window.prompt("Enter your 24-word recovery phrase to unlock encrypted DMs:")
    if (!phrase) throw new Error("e2ee_mnemonic_cancelled")

    let entropy
    try {
      entropy = await mnemonic24ToEntropy(phrase)
    } catch (error) {
      console.error("mnemonic parse failed", error)
      throw new Error("e2ee_mnemonic_invalid")
    }

    const hkdfSaltBytes = base64UrlDecode(hkdfSalt)
    const ivBytes = base64UrlDecode(iv)
    const wrappedBytes = base64UrlDecode(wrapper.wrapped_private_key)

    const secretKey = await crypto.subtle.importKey("raw", entropy, "HKDF", false, ["deriveKey"])

    const wrapKey = await crypto.subtle.deriveKey(
      {name: "HKDF", hash: "SHA-256", salt: hkdfSaltBytes, info: utf8Bytes(info)},
      secretKey,
      {name: "AES-GCM", length: 256},
      false,
      ["decrypt"]
    )

    const plaintext = await crypto.subtle.decrypt(
      {name: "AES-GCM", iv: ivBytes},
      wrapKey,
      sliceArrayBuffer(wrappedBytes)
    )

    const jwkJson = new TextDecoder().decode(new Uint8Array(plaintext))
    const privateJwk = JSON.parse(jwkJson)

    const privateKey = await crypto.subtle.importKey(
      "jwk",
      privateJwk,
      {name: "ECDH", namedCurve: "P-256"},
      false,
      ["deriveBits"]
    )

    e2eeIdentity = {
      kid: status.active_key.kid,
      publicKeyJwk: status.active_key.public_key_jwk,
      privateKey,
    }

    window.egregorosE2EE = e2eeIdentity
    storeE2EEPrivateJwk(status.active_key.kid, privateJwk)
    window.dispatchEvent(new CustomEvent("egregoros:e2ee-unlocked", {detail: {kid: e2eeIdentity.kid}}))
    return e2eeIdentity
  })()
    .catch(error => {
      e2eeIdentity = null
      throw error
    })
    .finally(() => {
      e2eeUnlockPromise = null
    })

  return e2eeUnlockPromise
}

const localHostMatches = domain => {
  if (!domain) return false
  const normalized = domain.trim().toLowerCase()
  return normalized === window.location.host.toLowerCase() || normalized === window.location.hostname.toLowerCase()
}

const parseHandle = value => {
  if (typeof value !== "string") return {nickname: null, domain: null}
  const raw = value.trim().replace(/^@+/, "")
  if (!raw) return {nickname: null, domain: null}

  const [nickname, domain] = raw.split("@", 2)
  return {nickname: nickname || null, domain: domain || null}
}

const actorKeyCache = new Map()
const actorKeyRequestCache = new Map()
const handleE2EEKeyCache = new Map()
const handleE2EEKeyRequestCache = new Map()

const seedActorE2EEKeys = (actorApId, keys) => {
  if (typeof actorApId !== "string") return
  const normalized = actorApId.trim()
  if (!normalized) return
  if (!Array.isArray(keys)) return

  let firstKey = null

  for (const key of keys) {
    const kid = key?.kid
    const jwk = key?.jwk

    if (!kid || !jwk?.kty || !jwk?.crv || !jwk?.x || !jwk?.y) continue

    actorKeyCache.set(`${normalized}#${kid}`, key)
    if (!firstKey) firstKey = key
  }

  if (firstKey) actorKeyCache.set(`${normalized}#`, firstKey)
}

window.egregorosSeedActorE2EEKeys = seedActorE2EEKeys

const fetchActorE2EEKey = async (actorApId, kid) => {
  if (!actorApId) return null

  const cacheKey = `${actorApId}#${kid || ""}`
  if (actorKeyCache.has(cacheKey)) return actorKeyCache.get(cacheKey)
  if (actorKeyRequestCache.has(cacheKey)) return actorKeyRequestCache.get(cacheKey)

  const payload = {actor_ap_id: actorApId}
  if (kid) payload.kid = kid

  const requestPromise = (async () => {
    let response
    try {
      response = await fetch("/settings/e2ee/actor_key", {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "content-type": "application/json",
          accept: "application/json",
          "x-csrf-token": csrfToken,
        },
        body: JSON.stringify(payload),
      })
    } catch (error) {
      console.error("e2ee actor_key fetch failed", error)
      return null
    }

    if (!response.ok) return null

    const body = await response.json().catch(() => null)
    const key = body?.key

    if (!key?.kid || !key?.jwk?.kty || !key?.jwk?.crv || !key?.jwk?.x || !key?.jwk?.y) return null

    actorKeyCache.set(cacheKey, key)
    return key
  })()

  actorKeyRequestCache.set(cacheKey, requestPromise)

  try {
    return await requestPromise
  } finally {
    actorKeyRequestCache.delete(cacheKey)
  }
}

const resolveHandleE2EEKey = async handle => {
  if (typeof handle !== "string") return null

  const normalized = handle.trim()
  if (!normalized) return null

  const cachedResolved = handleE2EEKeyCache.get(normalized)
  if (cachedResolved) return cachedResolved
  const cachedPromise = handleE2EEKeyRequestCache.get(normalized)
  if (cachedPromise) return cachedPromise

  const requestPromise = (async () => {
    let response
    try {
      response = await fetch("/settings/e2ee/actor_key", {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "content-type": "application/json",
          accept: "application/json",
          "x-csrf-token": csrfToken,
        },
        body: JSON.stringify({handle: normalized}),
      })
    } catch (error) {
      console.error("e2ee actor_key handle fetch failed", error)
      return null
    }

    if (!response.ok) return null

    const body = await response.json().catch(() => null)
    const actorApId = body?.actor_ap_id
    const key = body?.key

    if (!actorApId || !key?.kid || !key?.jwk?.kty || !key?.jwk?.crv || !key?.jwk?.x || !key?.jwk?.y) {
      return null
    }

    actorKeyCache.set(`${actorApId}#${key.kid}`, key)
    actorKeyCache.set(`${actorApId}#`, key)

    return {actorApId, key}
  })()

  handleE2EEKeyRequestCache.set(normalized, requestPromise)

  try {
    const resolved = await requestPromise
    if (resolved) handleE2EEKeyCache.set(normalized, resolved)
    return resolved
  } finally {
    handleE2EEKeyRequestCache.delete(normalized)
  }
}

const decryptE2EEDM = async ({payload, myPrivateKey, otherApId, otherKid, myApId}) => {
  const otherKey = await fetchActorE2EEKey(otherApId, otherKid)
  if (!otherKey) throw new Error("e2ee_missing_sender_key")

  return decryptE2EEDMOffline({payload, myPrivateKey, otherPublicJwk: otherKey.jwk})
}

const setDmE2EEFeedback = (form, message) => {
  const el = form?.querySelector?.("[data-role='dm-e2ee-feedback']")
  if (!el) return
  el.textContent = message
  el.classList.remove("hidden")
}

const clearDmE2EEFeedback = form => {
  const el = form?.querySelector?.("[data-role='dm-e2ee-feedback']")
  if (!el) return
  el.textContent = ""
  el.classList.add("hidden")
}

const E2EEDMComposer = {
  mounted() {
    this.encrypting = false
    this.skipNextSubmit = false
    this.encryptEnabled = null
    this.lastPeerApId = (this.el.dataset.peerApId || "").trim()
    restoreE2EEIdentityFromStorage()

    this.readEncryptEnabled = () => {
      const encryptInput = this.el.querySelector("[data-role='dm-encrypt-enabled']")
      return ((encryptInput?.value || "true") + "").trim() !== "false"
    }

    this.syncEncryptUI = () => {
      const encryptInput = this.el.querySelector("[data-role='dm-encrypt-enabled']")
      const toggleButton = this.el.querySelector("[data-role='dm-encrypt-toggle']")
      const contentInput = this.el.querySelector("textarea[name='dm[content]']")
      const lockIcon = this.el.querySelector("[data-role='dm-composer-lock']")

      if (this.encryptEnabled === null) this.encryptEnabled = this.readEncryptEnabled()

      if (encryptInput) {
        encryptInput.value = this.encryptEnabled ? "true" : "false"
      }

      if (contentInput) {
        contentInput.placeholder = this.encryptEnabled
          ? "Type an encrypted message..."
          : "Type a message..."
      }

      if (lockIcon) lockIcon.classList.toggle("hidden", !this.encryptEnabled)

      if (toggleButton) {
        toggleButton.dataset.state = this.encryptEnabled ? "encrypted" : "plain"

        toggleButton
          .querySelector("[data-role='dm-encrypt-icon-encrypted']")
          ?.classList?.toggle("hidden", !this.encryptEnabled)
        toggleButton
          .querySelector("[data-role='dm-encrypt-icon-plain']")
          ?.classList?.toggle("hidden", this.encryptEnabled)

        toggleButton
          .querySelector("[data-role='dm-encrypt-label-encrypted']")
          ?.classList?.toggle("hidden", !this.encryptEnabled)
        toggleButton
          .querySelector("[data-role='dm-encrypt-label-plain']")
          ?.classList?.toggle("hidden", this.encryptEnabled)
      } else {
        this.encryptEnabled = false
        if (encryptInput) encryptInput.value = "false"
        if (lockIcon) lockIcon.classList.add("hidden")
      }
    }

    this.toggleEncryptEnabled = () => {
      this.encryptEnabled = !this.readEncryptEnabled()
      this.syncEncryptUI()
    }

    this.onClick = e => {
      const target = e?.target
      if (!(target instanceof HTMLElement)) return

      const toggle = target.closest?.("[data-role='dm-encrypt-toggle']")
      if (!toggle || !this.el.contains(toggle)) return

      e.preventDefault()
      this.toggleEncryptEnabled()
    }

    this.onSubmit = async e => {
      if (this.skipNextSubmit) {
        this.skipNextSubmit = false
        return
      }

      const recipientInput = this.el.querySelector("input[name='dm[recipient]']")
      const contentInput = this.el.querySelector("textarea[name='dm[content]']")
      const payloadInput = this.el.querySelector("[data-role='dm-e2ee-payload']")
      const encryptInput = this.el.querySelector("[data-role='dm-encrypt-enabled']")

      if (!recipientInput || !contentInput || !payloadInput) return

      clearDmE2EEFeedback(this.el)

      this.syncEncryptUI()
      const encryptEnabled = ((encryptInput?.value || "true") + "").trim() !== "false"
      const recipientRaw = (recipientInput.value || "").trim()
      const plaintext = (contentInput.value || "").trim()
      if (!recipientRaw || !plaintext) return
      if (!encryptEnabled) {
        payloadInput.value = ""
        return
      }

      const {nickname, domain} = parseHandle(recipientRaw)
      if (!nickname) return

      e.preventDefault()
      e.stopPropagation()
      e.stopImmediatePropagation()

      if (this.encrypting) return

      this.encrypting = true
      payloadInput.value = ""

      let status
      try {
        status = await fetchE2EEStatus()
      } catch (error) {
        console.error("e2ee status fetch failed", error)
        setDmE2EEFeedback(this.el, "Could not check encrypted DM status.")
        this.encrypting = false
        return
      }

      if (!status?.enabled) {
        setDmE2EEFeedback(this.el, "Encrypted DMs are not enabled.")
        this.encrypting = false
        return
      }

      setDmE2EEFeedback(this.el, "Encrypting…")

      try {
        let recipientApId
        let recipientKey

        const peerApId = (this.el.dataset.peerApId || "").trim()

        if (peerApId) {
          recipientApId = peerApId
          recipientKey = await fetchActorE2EEKey(recipientApId, null)
          if (!recipientKey) throw new Error("e2ee_recipient_no_key")
        } else if (domain && !localHostMatches(domain)) {
          const resolved = await resolveHandleE2EEKey(recipientRaw)
          if (!resolved?.actorApId || !resolved?.key) throw new Error("e2ee_recipient_no_key")
          recipientApId = resolved.actorApId
          recipientKey = resolved.key
        } else {
          recipientApId = `${window.location.origin}/users/${nickname}`
          recipientKey = await fetchActorE2EEKey(recipientApId, null)
          if (!recipientKey) throw new Error("e2ee_recipient_no_key")
        }

        const identity = await unlockE2EEIdentity()

        const payload = await encryptE2EEDM({
          plaintext,
          senderApId: this.el.dataset.userApId || "",
          senderKid: identity.kid,
          senderPrivateKey: identity.privateKey,
          recipientApId,
          recipientKid: recipientKey.kid,
          recipientJwk: recipientKey.jwk,
        })

        payloadInput.value = JSON.stringify(payload)
        contentInput.value = "Encrypted message"
        setDmE2EEFeedback(this.el, "Encrypted. Sending…")

        this.encrypting = false
        this.skipNextSubmit = true
        this.el.requestSubmit()
      } catch (error) {
        console.error("e2ee dm encrypt failed", error)
        const message =
          error?.message === "e2ee_recipient_no_key"
            ? "Recipient does not support encrypted DMs."
            : error?.message === "e2ee_not_enabled"
              ? "Encrypted DMs are not enabled."
            : error?.message === "e2ee_no_mnemonic_wrapper"
              ? "Encrypted DMs are locked on this device."
            : error?.message === "e2ee_mnemonic_cancelled"
              ? "Unlock cancelled."
            : error?.message === "e2ee_mnemonic_invalid"
              ? "Invalid recovery phrase."
            : "Could not encrypt this message."

        setDmE2EEFeedback(this.el, message)
        this.encrypting = false
      }
    }

    this.encryptEnabled = this.readEncryptEnabled()
    this.syncEncryptUI()

    this.el.addEventListener("click", this.onClick)
    this.el.addEventListener("submit", this.onSubmit)
  },

  updated() {
    const peerApId = (this.el.dataset.peerApId || "").trim()
    if (peerApId !== this.lastPeerApId) {
      this.lastPeerApId = peerApId
      this.encryptEnabled = this.readEncryptEnabled()
    }

    this.syncEncryptUI()
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
    this.el.removeEventListener("submit", this.onSubmit)
  },
}

const E2EEDMMessage = {
  mounted() {
    this.decrypted = false
    this.decrypting = false

    restoreE2EEIdentityFromStorage()

    this.onUnlock = async e => {
      e.preventDefault()
      try {
        await unlockE2EEIdentity()
        await this.tryDecrypt(true)
      } catch (error) {
        console.error("e2ee dm unlock failed", error)
      }
    }

    this.onUnlocked = () => {
      this.tryDecrypt(false)
    }

    this.syncElements()

    window.addEventListener("egregoros:e2ee-unlocked", this.onUnlocked)

    this.tryDecrypt(false)
  },

  updated() {
    this.syncElements()
    this.tryDecrypt(false)
  },

  destroyed() {
    window.removeEventListener("egregoros:e2ee-unlocked", this.onUnlocked)
    if (this.unlockButton) this.unlockButton.removeEventListener("click", this.onUnlock)
  },

  syncElements() {
    this.bodyEl = this.el.querySelector("[data-role='e2ee-dm-body']")
    this.actionsEl = this.el.querySelector("[data-role='e2ee-dm-actions']")
    this.decryptingEl = this.el.querySelector("[data-role='e2ee-dm-decrypting']")
    this.placeholderEl = this.el.querySelector("[data-role='e2ee-dm-placeholder']")

    const nextUnlockButton = this.el.querySelector("[data-role='e2ee-dm-unlock']")
    if (nextUnlockButton === this.unlockButton) return

    if (this.unlockButton) this.unlockButton.removeEventListener("click", this.onUnlock)
    this.unlockButton = nextUnlockButton
    if (this.unlockButton) this.unlockButton.addEventListener("click", this.onUnlock)
  },

  readPayload() {
    const raw = this.el.dataset.e2eeDm
    if (!raw) return null

    try {
      return JSON.parse(raw)
    } catch (_error) {
      return null
    }
  },

  setDecrypting(nextDecrypting) {
    if (this.decryptingEl) this.decryptingEl.classList.toggle("hidden", !nextDecrypting)
    if (this.placeholderEl) this.placeholderEl.classList.toggle("hidden", nextDecrypting)
  },

  async tryDecrypt(triggeredByUser) {
    if (!this.bodyEl) return

    const payload = this.readPayload()
    if (!payload?.sender?.ap_id || !payload?.recipient?.ap_id) return

    const myApId = this.el.dataset.currentUserApId || ""
    if (!myApId) return

    const identity = window.egregorosE2EE
    if (!identity?.privateKey) return

    const iAmSender = payload.sender.ap_id === myApId
    const iAmRecipient = payload.recipient.ap_id === myApId

    if (!iAmSender && !iAmRecipient) return

    const other = iAmSender ? payload.recipient : payload.sender

    if (this.decrypted && this.actionsEl?.classList?.contains("hidden")) return

    if (this.decrypting) return

    this.decrypting = true
    this.setDecrypting(true)

    try {
      const plaintext = await decryptE2EEDM({
        payload,
        myPrivateKey: identity.privateKey,
        otherApId: other.ap_id,
        otherKid: other.kid,
        myApId,
      })

      this.bodyEl.textContent = plaintext
      if (this.actionsEl) this.actionsEl.classList.add("hidden")
      this.decrypted = true
    } catch (error) {
      if (triggeredByUser) console.error("e2ee dm decrypt failed", error)
    } finally {
      this.decrypting = false
      this.setDecrypting(false)
    }
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {
    ...colocatedHooks,
    TimelineTopSentinel,
    TimelineBottomSentinel,
    ComposePanel,
    ComposeCharCounter,
    ComposeSettings,
    ComposeMentions,
    EmojiPicker,
    ReactionPicker,
    MediaViewer,
    ReplyModal,
    ScrollRestore,
    StatusAutoScroll,
    DMChatScroller,
    AudioPlayer,
    VideoPlayer,
    E2EEDMComposer,
    E2EEDMMessage,
  },
})

document.addEventListener("DOMContentLoaded", initE2EESettings)
window.addEventListener("phx:page-loading-stop", initE2EESettings)
document.addEventListener("DOMContentLoaded", initPasskeyAuth)
window.addEventListener("phx:page-loading-stop", initPasskeyAuth)
document.addEventListener("DOMContentLoaded", initImageCropper)
window.addEventListener("phx:page-loading-stop", initImageCropper)

window.addEventListener("egregoros:scroll-top", () => {
  window.scrollTo({top: 0, behavior: "smooth"})
})

const copyToClipboard = async text => {
  if (!text) return false

  if (navigator.clipboard && window.isSecureContext) {
    await navigator.clipboard.writeText(text)
    return true
  }

  const textarea = document.createElement("textarea")
  textarea.value = text
  textarea.setAttribute("readonly", "")
  textarea.style.position = "fixed"
  textarea.style.top = "0"
  textarea.style.left = "-9999px"
  document.body.appendChild(textarea)
  textarea.select()

  const ok = document.execCommand("copy")
  document.body.removeChild(textarea)
  return ok
}

window.addEventListener("egregoros:copy", async e => {
  const text = e.target?.dataset?.copyText
  if (!text) return

  try {
    await copyToClipboard(text)
  } catch (_error) {
    // ignore clipboard errors; LiveView shows feedback separately
  }
})

const togglePressedAttrs = (el, nextPressed) => {
  if (!el) return
  const value = nextPressed ? "true" : "false"
  el.setAttribute("aria-pressed", value)
  el.setAttribute("data-pressed", value)
}

const updateCounter = (buttonEl, delta) => {
  if (!buttonEl) return
  const counter = buttonEl.querySelector("span.tabular-nums")
  if (!counter) return

  const current = parseInt(String(counter.textContent || "0").trim(), 10)
  if (!Number.isFinite(current)) return

  const next = Math.max(0, current + delta)
  counter.textContent = String(next)
}

const updateSrLabel = (buttonEl, text) => {
  if (!buttonEl) return
  const label = buttonEl.querySelector("span.sr-only")
  if (!label) return
  label.textContent = text
}

const initBadgeIssueForm = () => {
  const form = document.getElementById("badge-issue-form")
  if (!form || form.dataset.initialized === "true") return

  const badgeSelect = form.querySelector("#badge-issue-badge-type")
  const recipientInput = form.querySelector("#badge-issue-recipient")
  const submitButton = form.querySelector("#badge-issue-submit")
  if (!(badgeSelect instanceof HTMLSelectElement)) return
  if (!(recipientInput instanceof HTMLInputElement)) return
  if (!(submitButton instanceof HTMLButtonElement)) return

  form.dataset.initialized = "true"

  const updateSubmitState = () => {
    const hasBadge = badgeSelect.value.trim().length > 0
    const hasRecipient = recipientInput.value.trim().length > 0
    const enabled = hasBadge && hasRecipient

    submitButton.disabled = !enabled
    submitButton.setAttribute("aria-disabled", enabled ? "false" : "true")
  }

  updateSubmitState()
  badgeSelect.addEventListener("change", updateSubmitState)
  recipientInput.addEventListener("input", updateSubmitState)
}

window.addEventListener("egregoros:optimistic-toggle", e => {
  const kind = e?.detail?.kind
  const target = e?.target
  if (!kind || !(target instanceof HTMLElement)) return

  if (kind === "like") {
    const button = target.closest("button[data-role='like']")
    if (!button) return

    const pressed = button.getAttribute("data-pressed") === "true"
    const nextPressed = !pressed
    togglePressedAttrs(button, nextPressed)
    updateSrLabel(button, nextPressed ? "Unlike" : "Like")
    updateCounter(button, nextPressed ? 1 : -1)
    return
  }

  if (kind === "repost") {
    const button = target.closest("button[data-role='repost']")
    if (!button) return

    const pressed = button.getAttribute("data-pressed") === "true"
    const nextPressed = !pressed
    togglePressedAttrs(button, nextPressed)
    updateSrLabel(button, nextPressed ? "Unrepost" : "Repost")
    updateCounter(button, nextPressed ? 1 : -1)
    return
  }

  if (kind === "reaction") {
    const source = target.closest("[data-emoji]")
    const emoji = source?.dataset?.emoji
    if (!emoji) return

    const card = target.closest("article[data-role='status-card']")
    const button = card?.querySelector(`button[data-role='reaction'][data-emoji='${CSS.escape(emoji)}']`)

    if (!button) return

    const pressed = button.getAttribute("data-pressed") === "true"
    const nextPressed = !pressed
    togglePressedAttrs(button, nextPressed)
    updateCounter(button, nextPressed ? 1 : -1)
  }
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

document.addEventListener("DOMContentLoaded", initBadgeIssueForm)
window.addEventListener("phx:page-loading-stop", initBadgeIssueForm)

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
