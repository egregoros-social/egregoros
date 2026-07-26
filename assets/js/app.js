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

const parseJsonBody = async response => response.json().catch(() => ({}))

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
  },
})

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
