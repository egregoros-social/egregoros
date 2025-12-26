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

const TimelineTopSentinel = {
  mounted() {
    this.lastAtTop = null
    this.observer = new IntersectionObserver(entries => {
      const entry = entries[0]
      if (!entry) return

      const atTop = entry.isIntersecting
      if (this.lastAtTop === atTop) return

      this.lastAtTop = atTop
      this.pushEvent("timeline_at_top", {at_top: atTop})
    })

    this.observer.observe(this.el)
  },

  destroyed() {
    if (this.observer) this.observer.disconnect()
  },
}

const TimelineBottomSentinel = {
  mounted() {
    this.loading = false

    this.observer = new IntersectionObserver(
      entries => {
        const entry = entries[0]
        if (!entry || !entry.isIntersecting) return
        this.loadMore()
      },
      {rootMargin: "400px 0px"}
    )

    this.observer.observe(this.el)
  },

  destroyed() {
    if (this.observer) this.observer.disconnect()
  },

  loadMore() {
    if (this.loading) return

    this.loading = true
    this.pushEvent("load_more", {}, () => {
      this.loading = false
      if (!this.el.isConnected) return

      requestAnimationFrame(() => {
        if (this.isInView()) this.loadMore()
      })
    })
  },

  isInView() {
    const rect = this.el.getBoundingClientRect()
    return rect.top <= (window.innerHeight || document.documentElement.clientHeight)
  },
}

const ComposeCharCounter = {
  mounted() {
    this.maxChars = this.readMaxChars()
    this.counter = this.findCounter()
    this.submitButton = this.findSubmitButton()
    this.segmenter = this.buildSegmenter()

    this.onInput = () => this.update()
    this.el.addEventListener("input", this.onInput)
    this.update()
  },

  updated() {
    this.update()
  },

  destroyed() {
    this.el.removeEventListener("input", this.onInput)
  },

  readMaxChars() {
    const raw = this.el.dataset.maxChars
    const parsed = parseInt(raw || "0", 10)
    if (Number.isFinite(parsed) && parsed > 0) return parsed
    return 0
  },

  buildSegmenter() {
    if (!window.Intl || !Intl.Segmenter) return null
    try {
      return new Intl.Segmenter(undefined, {granularity: "grapheme"})
    } catch (_error) {
      return null
    }
  },

  countChars(text) {
    if (!text) return 0

    if (this.segmenter) {
      let count = 0
      for (const _segment of this.segmenter.segment(text)) count++
      return count
    }

    return Array.from(text).length
  },

  findCounter() {
    const form = this.el.closest("form")
    if (!form) return null
    return form.querySelector("[data-role='compose-char-counter']")
  },

  findSubmitButton() {
    const form = this.el.closest("form")
    if (!form) return null
    return form.querySelector("[data-role='compose-submit']")
  },

  update() {
    const form = this.el.closest("form")
    if (!form) return

    if (!this.counter || !this.counter.isConnected) this.counter = this.findCounter()
    if (!this.submitButton || !this.submitButton.isConnected) this.submitButton = this.findSubmitButton()

    const remaining = this.maxChars ? this.maxChars - this.countChars(this.el.value || "") : null

    if (this.counter && this.counter.isConnected && remaining !== null) {
      this.counter.textContent = String(remaining)

      const overLimit = remaining < 0
      this.counter.classList.toggle("text-rose-600", overLimit)
      this.counter.classList.toggle("dark:text-rose-400", overLimit)
      this.counter.classList.toggle("text-slate-500", !overLimit)
      this.counter.classList.toggle("dark:text-slate-400", !overLimit)
    }

    this.updateSubmitDisabled(form, remaining)
  },

  updateSubmitDisabled(form, remaining) {
    if (!this.submitButton || !this.submitButton.isConnected) return

    const contentBlank = !String(this.el.value || "").trim()
    const hasMedia = form.querySelector("[data-role='media-entry'], [data-role='reply-media-entry']") !== null
    const hasUploadError =
      form.querySelector("[data-role='upload-error'], [data-role='reply-upload-error']") !== null

    const uploadPending = Array.from(
      form.querySelectorAll("[data-role='media-progress'], [data-role='reply-media-progress']")
    ).some(node => {
      const pct = parseInt(node.textContent || "0", 10)
      return Number.isFinite(pct) && pct < 100
    })

    const overLimit = remaining !== null && remaining < 0
    const disabled = overLimit || (contentBlank && !hasMedia) || uploadPending || hasUploadError

    this.submitButton.disabled = disabled
  },
}

const ComposeMentions = {
  mounted() {
    this.scope = this.el.dataset.mentionScope || ""
    this.input = this.findInput()
    this.debounceTimer = null
    this.currentQuery = null
    this.activeMention = null

    if (!this.input) return

    this.onInput = () => this.handleInput()
    this.onCursor = () => this.handleInput()

    this.onMentionSelect = e => {
      const handle = e?.detail?.handle
      if (!handle || !this.input) return

      const mention = this.extractMentionAtCursor() || this.activeMention
      if (!mention) return

      const value = this.input.value || ""
      const before = value.slice(0, mention.start)
      const after = value.slice(mention.end)
      const insertion = `${handle} `

      this.input.value = before + insertion + after
      const newPos = before.length + insertion.length
      this.input.selectionStart = newPos
      this.input.selectionEnd = newPos
      this.input.focus()
      this.input.dispatchEvent(new Event("input", {bubbles: true}))

      this.clearSuggestions()
    }

    this.input.addEventListener("input", this.onInput)
    this.input.addEventListener("keyup", this.onCursor)
    this.input.addEventListener("click", this.onCursor)
    this.el.addEventListener("egregoros:mention-select", this.onMentionSelect)

    this.handleInput()
  },

  updated() {
    const nextInput = this.findInput()
    if (nextInput !== this.input) {
      if (this.input) {
        this.input.removeEventListener("input", this.onInput)
        this.input.removeEventListener("keyup", this.onCursor)
        this.input.removeEventListener("click", this.onCursor)
      }

      this.input = nextInput
      if (this.input) {
        this.input.addEventListener("input", this.onInput)
        this.input.addEventListener("keyup", this.onCursor)
        this.input.addEventListener("click", this.onCursor)
      }
    }
  },

  destroyed() {
    clearTimeout(this.debounceTimer)

    if (this.input) {
      this.input.removeEventListener("input", this.onInput)
      this.input.removeEventListener("keyup", this.onCursor)
      this.input.removeEventListener("click", this.onCursor)
    }

    this.el.removeEventListener("egregoros:mention-select", this.onMentionSelect)
  },

  findInput() {
    return this.el.querySelector("textarea[data-role='compose-content']")
  },

  handleInput() {
    if (!this.input) return

    const mention = this.extractMentionAtCursor()

    if (!mention) {
      this.clearSuggestions()
      return
    }

    if (mention.query === this.currentQuery) {
      this.activeMention = mention
      return
    }

    this.activeMention = mention
    this.currentQuery = mention.query
    this.requestSearch(mention.query)
  },

  requestSearch(query) {
    clearTimeout(this.debounceTimer)

    this.debounceTimer = setTimeout(() => {
      if (!this.scope) return
      this.pushEvent("mention_search", {q: query, scope: this.scope})
    }, 120)
  },

  clearSuggestions() {
    if (!this.scope) return
    if (this.currentQuery === null) return

    this.currentQuery = null
    this.activeMention = null
    clearTimeout(this.debounceTimer)
    this.pushEvent("mention_clear", {scope: this.scope})
  },

  extractMentionAtCursor() {
    if (!this.input) return null

    const value = this.input.value || ""
    const pos = typeof this.input.selectionStart === "number" ? this.input.selectionStart : value.length

    if (!pos) return null

    let i = pos - 1
    while (i >= 0) {
      const ch = value[i]
      if (ch === "@") break
      if (/\s/.test(ch)) return null
      i -= 1
    }

    if (i < 0) return null
    if (i > 0 && !/\s/.test(value[i - 1])) return null

    const raw = value.slice(i + 1, pos)
    if (!raw) return null

    if (!/^[A-Za-z0-9_.-]{1,64}(@[A-Za-z0-9.:-]{0,255})?$/.test(raw)) return null

    return {start: i, end: pos, query: raw}
  },
}

const EmojiPicker = {
  mounted() {
    this.menu = this.findMenu()
    this.toggleButton = this.findToggle()

    this.onClick = e => {
      const option = e.target?.closest?.("[data-role='compose-emoji-option']")
      if (option && this.el.contains(option)) {
        e.preventDefault()
        this.insertEmoji(option.dataset.emoji || option.textContent || "")
        this.setOpen(false)
        return
      }

      const toggle = e.target?.closest?.("[data-role='compose-emoji']")
      if (toggle && this.el.contains(toggle)) {
        e.preventDefault()
        this.setOpen(!this.isOpen())
      }
    }

    this.onDocumentClick = e => {
      if (!this.isOpen()) return
      if (e.target && this.el.contains(e.target)) return
      this.setOpen(false)
    }

    this.onKeydown = e => {
      if (!this.isOpen()) return
      if (e.key === "Escape" || e.key === "Esc") {
        this.setOpen(false)
        this.toggleButton?.focus?.({preventScroll: true})
      }
    }

    this.el.addEventListener("click", this.onClick)
    document.addEventListener("click", this.onDocumentClick)
    window.addEventListener("keydown", this.onKeydown)

    this.setOpen(false)
  },

  updated() {
    this.menu = this.findMenu()
    this.toggleButton = this.findToggle()
    this.syncAria()
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
    document.removeEventListener("click", this.onDocumentClick)
    window.removeEventListener("keydown", this.onKeydown)
  },

  findMenu() {
    return this.el.querySelector("[data-role='compose-emoji-menu']")
  },

  findToggle() {
    return this.el.querySelector("[data-role='compose-emoji']")
  },

  isOpen() {
    if (!this.menu) return false
    return !this.menu.classList.contains("hidden") && this.menu.dataset.state === "open"
  },

  setOpen(open) {
    if (!this.menu) return

    const isOpen = !!open
    this.menu.dataset.state = isOpen ? "open" : "closed"
    this.menu.classList.toggle("hidden", !isOpen)
    this.menu.setAttribute("aria-hidden", isOpen ? "false" : "true")

    if (this.toggleButton) {
      this.toggleButton.setAttribute("aria-expanded", isOpen ? "true" : "false")
    }
  },

  syncAria() {
    if (!this.menu || !this.toggleButton) return
    const isOpen = this.isOpen()
    this.menu.setAttribute("aria-hidden", isOpen ? "false" : "true")
    this.toggleButton.setAttribute("aria-expanded", isOpen ? "true" : "false")
  },

  insertEmoji(emoji) {
    const value = String(emoji || "")
    if (!value) return

    const textarea = this.findTextarea()
    if (!textarea) return

    const start = textarea.selectionStart ?? textarea.value.length
    const end = textarea.selectionEnd ?? textarea.value.length

    try {
      textarea.setRangeText(value, start, end, "end")
    } catch (_error) {
      textarea.value = `${textarea.value || ""}${value}`
    }

    textarea.dispatchEvent(new Event("input", {bubbles: true}))
    textarea.focus({preventScroll: true})
  },

  findTextarea() {
    const form = this.el.closest("form")
    if (!form) return null
    return form.querySelector("textarea[data-role='compose-content']")
  },
}

const MediaViewer = {
  mounted() {
    this.index = this.readIndex()
    this.lastFocused = null

    this.onOpen = e => {
      const dispatcher = e.detail?.dispatcher
      if (!dispatcher) return

      this.lastFocused = document.activeElement

      const buttons = this.mediaButtons(dispatcher)
      if (buttons.length === 0) return

      const items = buttons.map(btn => this.itemFromButton(btn)).filter(Boolean)
      if (items.length === 0) return

      const selectedIndex = buttons.findIndex(btn => btn === dispatcher)
      this.setSlides(items)
      this.open()
      this.applyIndex(selectedIndex)
    }

    this.onNext = () => this.bump(1)
    this.onPrev = () => this.bump(-1)
    this.onClose = () => this.close()

    this.el.addEventListener("egregoros:media-open", this.onOpen)
    this.el.addEventListener("egregoros:media-next", this.onNext)
    this.el.addEventListener("egregoros:media-prev", this.onPrev)
    this.el.addEventListener("egregoros:media-close", this.onClose)

    this.onKeydown = e => {
      if (!this.el.isConnected) return
      if (e.defaultPrevented) return
      if (!this.isOpen()) return

      const target = e.target
      if (target && (target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName))) {
        return
      }

      if (e.key === "Escape" || e.key === "Esc") {
        this.close()
        return
      }

      if (e.key === "ArrowRight") {
        this.bump(1)
        e.preventDefault()
        return
      }

      if (e.key === "ArrowLeft") {
        this.bump(-1)
        e.preventDefault()
      }
    }

    window.addEventListener("keydown", this.onKeydown)
    this.applyIndex(this.index)
  },

  updated() {
    if (!this.isOpen()) return
    this.applyIndex(this.index)
  },

  destroyed() {
    this.el.removeEventListener("egregoros:media-open", this.onOpen)
    this.el.removeEventListener("egregoros:media-next", this.onNext)
    this.el.removeEventListener("egregoros:media-prev", this.onPrev)
    this.el.removeEventListener("egregoros:media-close", this.onClose)
    window.removeEventListener("keydown", this.onKeydown)
  },

  readIndex() {
    const index = parseInt(this.el.dataset.index || "0", 10)
    return Number.isFinite(index) ? index : 0
  },

  isOpen() {
    return this.el.dataset.state === "open" && !this.el.classList.contains("hidden")
  },

  open() {
    this.el.classList.remove("hidden")
    this.el.dataset.state = "open"
    this.el.setAttribute("aria-hidden", "false")

    const closeButton = this.el.querySelector("[data-role='media-viewer-close']")
    if (closeButton) closeButton.focus({preventScroll: true})
  },

  close() {
    this.el.classList.add("hidden")
    this.el.dataset.state = "closed"
    this.el.setAttribute("aria-hidden", "true")
    this.clearSlides()
    this.restoreFocus()
  },

  restoreFocus() {
    if (!this.lastFocused) return
    const target = this.lastFocused
    this.lastFocused = null
    if (target.isConnected && typeof target.focus === "function") target.focus({preventScroll: true})
  },

  slides() {
    return Array.from(this.el.querySelectorAll("[data-role='media-viewer-slide']"))
  },

  mediaButtons(dispatcher) {
    const post = dispatcher.closest("article[id^='post-']")
    if (!post) return []

    return Array.from(post.querySelectorAll("button[data-role='attachment-open']")).sort((a, b) => {
      const aIndex = parseInt(a.dataset.index || "0", 10)
      const bIndex = parseInt(b.dataset.index || "0", 10)
      return aIndex - bIndex
    })
  },

  itemFromButton(button) {
    const img = button.querySelector("img[data-role='attachment'][data-kind='image']")
    if (img) {
      return {
        kind: "image",
        href: img.getAttribute("src") || "",
        description: img.getAttribute("alt") || "",
      }
    }

    const container = button.parentElement || button

    const video = container.querySelector("video[data-role='attachment'][data-kind='video']")
    if (video) {
      const source = video.querySelector("source")
      return {
        kind: "video",
        href: source?.getAttribute("src") || "",
        sourceType: source?.getAttribute("type") || "",
        description: video.getAttribute("aria-label") || "",
      }
    }

    const audio = container.querySelector("audio[data-role='attachment'][data-kind='audio']")
    if (audio) {
      const source = audio.querySelector("source")
      return {
        kind: "audio",
        href: source?.getAttribute("src") || "",
        sourceType: source?.getAttribute("type") || "",
        description: audio.getAttribute("aria-label") || "",
      }
    }

    return null
  },

  slidesContainer() {
    return this.el.querySelector("[data-role='media-viewer-slides']")
  },

  clearSlides() {
    const container = this.slidesContainer()
    if (container) container.replaceChildren()
    this.el.dataset.count = "0"
    this.updateControls(0)
  },

  setSlides(items) {
    const container = this.slidesContainer()
    if (!container) return

    container.replaceChildren(...items.map((item, index) => this.renderSlide(item, index)))
    this.el.dataset.count = String(items.length)
    this.updateControls(items.length)
  },

  updateControls(count) {
    const prev = this.el.querySelector("[data-role='media-viewer-prev']")
    const next = this.el.querySelector("[data-role='media-viewer-next']")

    const showNav = count > 1
    if (prev) prev.classList.toggle("hidden", !showNav)
    if (next) next.classList.toggle("hidden", !showNav)
  },

  renderSlide(item, index) {
    const slide = document.createElement("div")
    slide.dataset.role = "media-viewer-slide"
    slide.dataset.index = String(index)
    slide.dataset.state = "inactive"
    slide.setAttribute("aria-hidden", "true")
    slide.className = "w-full hidden"

    if (item.kind === "video") {
      const video = document.createElement("video")
      video.dataset.role = "media-viewer-item"
      video.controls = true
      video.preload = "metadata"
      video.playsInline = true
      video.className = "max-h-[85vh] w-full bg-black"
      if (item.description) video.setAttribute("aria-label", item.description)

      const source = document.createElement("source")
      source.setAttribute("src", item.href)
      if (item.sourceType) source.setAttribute("type", item.sourceType)
      video.appendChild(source)
      slide.appendChild(video)
      return slide
    }

    if (item.kind === "audio") {
      const wrapper = document.createElement("div")
      wrapper.className = "flex max-h-[85vh] w-full items-center justify-center bg-black/90 px-6 py-10"

      const audio = document.createElement("audio")
      audio.dataset.role = "media-viewer-item"
      audio.controls = true
      audio.preload = "metadata"
      audio.className = "w-full"
      if (item.description) audio.setAttribute("aria-label", item.description)

      const source = document.createElement("source")
      source.setAttribute("src", item.href)
      if (item.sourceType) source.setAttribute("type", item.sourceType)
      audio.appendChild(source)

      wrapper.appendChild(audio)
      slide.appendChild(wrapper)
      return slide
    }

    const img = document.createElement("img")
    img.dataset.role = "media-viewer-item"
    img.setAttribute("src", item.href)
    img.setAttribute("alt", item.description || "")
    img.loading = "lazy"
    img.className = "max-h-[85vh] w-full object-contain"
    slide.appendChild(img)
    return slide
  },

  bump(delta) {
    const slides = this.slides()
    if (slides.length < 2) return

    const count = slides.length
    const next = (this.index + delta + count) % count
    this.index = next
    this.el.dataset.index = String(next)

    this.applyIndex(next)
  },

  applyIndex(index) {
    const slides = this.slides()
    if (slides.length === 0) return

    const normalized = ((index % slides.length) + slides.length) % slides.length
    this.index = normalized
    this.el.dataset.index = String(normalized)

    slides.forEach(slide => {
      const slideIndex = parseInt(slide.dataset.index || "0", 10)
      const isActive = slideIndex === normalized
      slide.dataset.state = isActive ? "active" : "inactive"
      slide.classList.toggle("hidden", !isActive)
      slide.setAttribute("aria-hidden", isActive ? "false" : "true")
    })
  },
}

const ReplyModal = {
  mounted() {
    this.lastFocused = null

    this.onOpen = () => {
      this.lastFocused = document.activeElement
      this.open()
      this.focusTextarea()
    }

    this.onClose = () => {
      this.close()
    }

    this.el.addEventListener("egregoros:reply-open", this.onOpen)
    this.el.addEventListener("egregoros:reply-close", this.onClose)

    this.onKeydown = e => {
      if (!this.el.isConnected) return
      if (e.defaultPrevented) return
      if (!this.isOpen()) return

      if (e.key === "Escape" || e.key === "Esc") {
        this.close()
        this.pushEvent("close_reply_modal", {})
        e.preventDefault()
      }
    }

    window.addEventListener("keydown", this.onKeydown)
    this.handleEvent("reply_modal_close", () => this.close())
  },

  destroyed() {
    this.el.removeEventListener("egregoros:reply-open", this.onOpen)
    this.el.removeEventListener("egregoros:reply-close", this.onClose)
    window.removeEventListener("keydown", this.onKeydown)
  },

  isOpen() {
    return this.el.dataset.state === "open" && !this.el.classList.contains("hidden")
  },

  open() {
    this.el.classList.remove("hidden")
    this.el.dataset.state = "open"
    this.el.setAttribute("aria-hidden", "false")
  },

  close() {
    this.el.classList.add("hidden")
    this.el.dataset.state = "closed"
    this.el.setAttribute("aria-hidden", "true")
    this.restoreFocus()
  },

  restoreFocus() {
    if (!this.lastFocused) return
    const target = this.lastFocused
    this.lastFocused = null
    if (target.isConnected && typeof target.focus === "function") target.focus({preventScroll: true})
  },

  focusTextarea() {
    const textarea = this.el.querySelector("textarea[data-role='compose-content']")
    if (textarea) textarea.focus({preventScroll: true})
  },
}

const base64UrlEncode = bytes => {
  let binary = ""
  const len = bytes.length

  for (let i = 0; i < len; i++) binary += String.fromCharCode(bytes[i])

  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "")
}

const utf8Bytes = value => new TextEncoder().encode(value)

const randomBytes = len => {
  const out = new Uint8Array(len)
  crypto.getRandomValues(out)
  return out
}

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

const enableE2EEWithPasskey = async (section, button, csrfToken) => {
  if (!window.PublicKeyCredential || !navigator.credentials?.create || !navigator.credentials?.get) {
    setE2EEFeedback(section, "Passkeys (WebAuthn) are not supported in this browser.", "error")
    return
  }

  if (!window.isSecureContext) {
    setE2EEFeedback(section, "Passkeys require HTTPS (secure context).", "error")
    return
  }

  if (!window.crypto?.subtle) {
    setE2EEFeedback(section, "WebCrypto is not available in this browser.", "error")
    return
  }

  const userId = section.dataset.userId
  const nickname = section.dataset.nickname

  if (!userId || !nickname) {
    setE2EEFeedback(section, "Missing user metadata for passkey registration.", "error")
    return
  }

  button.disabled = true
  setE2EEFeedback(section, "Creating passkey…", "info")

  const userHandle = utf8Bytes(`egregoros:user:${userId}`)
  const prfSalt = randomBytes(32)

  const creationOptions = {
    challenge: randomBytes(32),
    rp: {name: "Egregoros", id: window.location.hostname},
    user: {
      id: userHandle,
      name: nickname,
      displayName: nickname,
    },
    pubKeyCredParams: [{type: "public-key", alg: -7}],
    timeout: 60_000,
    attestation: "none",
    authenticatorSelection: {
      residentKey: "required",
      userVerification: "required",
    },
    extensions: {hmacCreateSecret: true, prf: {eval: {first: prfSalt}}},
  }

  let created
  try {
    created = await navigator.credentials.create({publicKey: creationOptions})
  } catch (error) {
    console.error("passkey create failed", error)
    setE2EEFeedback(section, "Could not create a passkey (cancelled or unsupported).", "error")
    button.disabled = false
    return
  }

  const createExt = created?.getClientExtensionResults?.() || {}
  setE2EEFeedback(section, "Deriving recovery key from passkey…", "info")

  const assertionOptions = {
    challenge: randomBytes(32),
    rpId: window.location.hostname,
    allowCredentials: [{type: "public-key", id: created.rawId}],
    userVerification: "required",
    extensions: {hmacGetSecret: {salt1: prfSalt}, prf: {eval: {first: prfSalt}}},
  }

  let assertion
  try {
    assertion = await navigator.credentials.get({publicKey: assertionOptions})
  } catch (error) {
    console.error("passkey get failed", error)
    setE2EEFeedback(section, "Could not use the passkey to derive a wrapping key.", "error")
    button.disabled = false
    return
  }

  const getExt = assertion?.getClientExtensionResults?.() || {}
  const prfOutput = getExt.prf?.results?.first || getExt.hmacGetSecret?.output1

  if (!prfOutput) {
    console.error("passkey extension results", {createExt, getExt})
    setE2EEFeedback(
      section,
      "This passkey provider does not support the WebAuthn PRF / hmac-secret extensions, so it can’t be used for encrypted DM key recovery. Try a platform passkey provider (iCloud Keychain / Google Password Manager) or use a recovery code instead.",
      "error"
    )
    button.disabled = false
    return
  }

  const hkdfSalt = randomBytes(32)
  const info = utf8Bytes("egregoros:e2ee:wrap:v1")

  let wrapKey
  try {
    const prfKey = await crypto.subtle.importKey("raw", prfOutput, "HKDF", false, ["deriveKey"])

    wrapKey = await crypto.subtle.deriveKey(
      {name: "HKDF", hash: "SHA-256", salt: hkdfSalt, info},
      prfKey,
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

  setE2EEFeedback(section, "Generating E2EE identity key…", "info")

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
      type: "webauthn_hmac_secret",
      wrapped_private_key: base64UrlEncode(new Uint8Array(ciphertext)),
      params: {
        credential_id: base64UrlEncode(new Uint8Array(created.rawId)),
        prf_salt: base64UrlEncode(prfSalt),
        hkdf_salt: base64UrlEncode(hkdfSalt),
        iv: base64UrlEncode(iv),
        alg: "A256GCM",
        kdf: "HKDF-SHA256",
        info: "egregoros:e2ee:wrap:v1",
      },
    },
  }

  let response
  try {
    response = await fetch("/settings/e2ee/passkey", {
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
    fingerprintEl.textContent = body.fingerprint ? `Fingerprint: ${body.fingerprint}` : "Fingerprint: (unknown)"
    fingerprintEl.classList.remove("hidden")
  }

  setE2EEFeedback(section, "Encrypted DMs enabled.", "success")
  button.classList.add("hidden")
}

const initE2EESettings = () => {
  document.querySelectorAll("[data-role='e2ee-settings']").forEach(section => {
    if (section.dataset.e2eeInitialized === "true") return
    section.dataset.e2eeInitialized = "true"

    const button = section.querySelector("[data-role='e2ee-enable-passkey']")
    if (!button) return

    button.addEventListener("click", () => enableE2EEWithPasskey(section, button, csrfToken))
  })
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {
    ...colocatedHooks,
    TimelineTopSentinel,
    TimelineBottomSentinel,
    ComposeCharCounter,
    ComposeMentions,
    EmojiPicker,
    MediaViewer,
    ReplyModal,
  },
})

document.addEventListener("DOMContentLoaded", initE2EESettings)
window.addEventListener("phx:page-loading-stop", initE2EESettings)

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

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

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
