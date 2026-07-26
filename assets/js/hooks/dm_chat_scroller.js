const DMChatScroller = {
  mounted() {
    this.threshold = 80
    this.peer = (this.el?.dataset?.peer || "").trim()
    this.wasNearBottom = true

    this.onScroll = () => {
      this.wasNearBottom = this.isNearBottom()
    }

    this.el.addEventListener("scroll", this.onScroll, {passive: true})

    requestAnimationFrame(() => requestAnimationFrame(() => this.scrollToBottom()))
  },

  beforeUpdate() {
    this.wasNearBottom = this.isNearBottom()
  },

  updated() {
    const nextPeer = (this.el?.dataset?.peer || "").trim()

    if (nextPeer !== this.peer) {
      this.peer = nextPeer
      requestAnimationFrame(() => requestAnimationFrame(() => this.scrollToBottom()))
      return
    }

    if (this.wasNearBottom) {
      requestAnimationFrame(() => this.scrollToBottom())
    }
  },

  destroyed() {
    this.el.removeEventListener("scroll", this.onScroll)
  },

  isNearBottom() {
    if (!this.el) return true
    const {scrollTop, scrollHeight, clientHeight} = this.el
    return scrollHeight - (scrollTop + clientHeight) < this.threshold
  },

  scrollToBottom() {
    if (!this.el) return
    this.el.scrollTop = this.el.scrollHeight
  },
}

export default DMChatScroller
