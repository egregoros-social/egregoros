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
import {hooks as colocatedHooks} from "phoenix-colocated/pleroma_redux"
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
    const hasMedia = form.querySelector("[data-role='media-entry']") !== null
    const hasUploadError = form.querySelector("[data-role='upload-error']") !== null

    const uploadPending = Array.from(form.querySelectorAll("[data-role='media-progress']")).some(node => {
      const pct = parseInt(node.textContent || "0", 10)
      return Number.isFinite(pct) && pct < 100
    })

    const overLimit = remaining !== null && remaining < 0
    const disabled = overLimit || (contentBlank && !hasMedia) || uploadPending || hasUploadError

    this.submitButton.disabled = disabled
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

    this.el.addEventListener("predux:media-open", this.onOpen)
    this.el.addEventListener("predux:media-next", this.onNext)
    this.el.addEventListener("predux:media-prev", this.onPrev)
    this.el.addEventListener("predux:media-close", this.onClose)

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
        this.pushEvent("close_media", {})
        return
      }

      if (e.key === "ArrowRight") {
        this.bump(1)
        this.pushEvent("media_next", {})
        e.preventDefault()
        return
      }

      if (e.key === "ArrowLeft") {
        this.bump(-1)
        this.pushEvent("media_prev", {})
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
    this.el.removeEventListener("predux:media-open", this.onOpen)
    this.el.removeEventListener("predux:media-next", this.onNext)
    this.el.removeEventListener("predux:media-prev", this.onPrev)
    this.el.removeEventListener("predux:media-close", this.onClose)
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
  },

  setSlides(items) {
    const container = this.slidesContainer()
    if (!container) return

    container.replaceChildren(...items.map((item, index) => this.renderSlide(item, index)))
    this.el.dataset.count = String(items.length)
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

  close() {
    this.el.classList.add("hidden")
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, TimelineTopSentinel, TimelineBottomSentinel, ComposeCharCounter, MediaViewer},
})

window.addEventListener("predux:scroll-top", () => {
  window.scrollTo({top: 0, behavior: "smooth"})
})

async function copyToClipboard(text) {
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

window.addEventListener("predux:copy", async e => {
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
