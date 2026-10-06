import type { Register } from 'claude-code'

const RAINBOW = ['#ff0000', '#ff8800', '#ffdd00', '#00cc44', '#0099ff', '#4455ff', '#aa44ff']
// An arc turning clockwise, quarter arcs and half circles alternating; played as a loop
const ARC = ['◜', '◠', '◝', '◞', '◡', '◟']
// The glyph is a 1x1 Raster repainted by $.ui.blit, which is not held to ui.render's 10 redraws a second
const ARC_MS = 100
const ARC_HUE_STEP = 6
const FRAME_MS = 100

const rainbow = (i: number, shift: number) => RAINBOW[(((i - shift) % RAINBOW.length) + RAINBOW.length) % RAINBOW.length]

const hueRgb = (deg: number) => {
  const f = (n: number) => {
    const k = (n + deg / 30) % 12
    return Math.round(255 * (0.5 - 0.5 * Math.max(-1, Math.min(k - 3, 9 - k, 1))))
  }
  return (f(0) << 16) | (f(8) << 8) | f(4)
}

const hex = (rgb: number) => `#${rgb.toString(16).padStart(6, '0')}`

const DEFAULT_COLOR = 0x01000000

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
// Raster cells are always 12 bytes here (one cell), a multiple of 3, so no padding case
const base64 = (bytes: Uint8Array) => {
  let out = ''
  for (let i = 0; i < bytes.length; i += 3) {
    const n = (bytes[i]! << 16) | (bytes[i + 1]! << 8) | bytes[i + 2]!
    out += B64[(n >> 18) & 63]! + B64[(n >> 12) & 63]! + B64[(n >> 6) & 63]! + B64[n & 63]!
  }
  return out
}

const duration = (ms: number) => {
  const s = Math.floor(ms / 1000)
  if (s < 60) return `${s}s`
  if (s < 3600) return `${Math.floor(s / 60)}m ${s % 60}s`
  return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`
}

const tokens = (n: number) =>
  new Intl.NumberFormat('en-US', n >= 1000 ? { notation: 'compact', maximumFractionDigits: 1 } : {}).format(n).toLowerCase()

const thinkingLabel = (ms: number) =>
  ms >= 45000 ? 'deep in thought' : ms >= 30000 ? 'thinking some more' : ms >= 20000 ? 'thinking more' : ms >= 10000 ? 'still thinking' : 'thinking'

export const register: Register = on => {
  let enabled = true
  let noColor = false
  const paint = (color: string | undefined) => (noColor ? undefined : color)
  let tick = 0
  let ticker: { cancel: () => void } | null = null
  let arc = 0
  let arcTicker: { cancel: () => void } | null = null
  const spinners = new Set<string>()

  const arcCells = () => {
    const fg = noColor ? DEFAULT_COLOR : hueRgb((arc * ARC_HUE_STEP) % 360)
    const words = Uint32Array.of(ARC[arc % ARC.length]!.codePointAt(0)!, fg, DEFAULT_COLOR)
    return base64(new Uint8Array(words.buffer))
  }
  let turnId = ''
  let turnStart: number | null = null
  let chars = 0
  let thinkStart: number | null = null
  let thoughtFor: { ms: number; until: number } | null = null

  on('session.start', async ($, e, next) => {
    enabled = (await $.store.get('enabled')) !== false
    noColor = Boolean(await $.env.get('NO_COLOR'))
    await $.command.register({ name: 'dopagaki', description: 'Rainbow mode: /dopagaki on | off (no argument toggles)' })
    return next(e)
  })

  on('command.run', { command: 'dopagaki' }, async ($, e) => {
    const arg = e.args.trim()
    enabled = arg === 'on' ? true : arg === 'off' ? false : !enabled
    await $.store.set('enabled', enabled)
    $.ui.invalidate('ui.render')
    return { text: `dopagaki: ${enabled ? 'on' : 'off'}` }
  })

  // Animate only while a turn runs, so an idle session redraws nothing
  on('turn.start', async ($, e, next) => {
    turnId = e.turnId
    turnStart = await $.clock.now()
    chars = 0
    thinkStart = null
    thoughtFor = null
    ticker?.cancel()
    ticker = $.clock.every(FRAME_MS, () => {
      tick += 1
      if (enabled) $.ui.invalidate('ui.render')
    })
    arcTicker?.cancel()
    arcTicker = $.clock.every(ARC_MS, () => {
      arc += 1
      if (!enabled) return
      for (const requestId of spinners) {
        $.ui.blit({ requestId, key: 'arc', cells: arcCells() }).then(
          r => {
            if ('deny' in r) spinners.delete(requestId)
          },
          () => spinners.delete(requestId),
        )
      }
    })
    return next(e)
  })

  on('turn.complete', ($, e, next) => {
    ticker?.cancel()
    ticker = null
    arcTicker?.cancel()
    arcTicker = null
    spinners.clear()
    $.ui.invalidate('ui.render')
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    const mine = e.turnId === turnId
    for await (const chunk of next(e)) {
      if (mine) {
        if (chunk.kind === 'text' || chunk.kind === 'thinking') chars += chunk.text.length
        if (chunk.kind === 'input') chars += chunk.json.length
        if (chunk.kind === 'thinking' && thinkStart === null) thinkStart = await $.clock.now()
        if (chunk.kind !== 'thinking' && chunk.kind !== 'engine' && thinkStart !== null) {
          const now = await $.clock.now()
          thoughtFor = { ms: now - thinkStart, until: now + 2000 }
          thinkStart = null
        }
      }
      yield chunk
    }
    return
  })

  on('ui.render', { component: 'Spinner' }, async ($, e, next) => {
    if (!enabled) return next(e)
    const now = await $.clock.now()
    const word = (e.props.message ?? e.props.word) + e.props.suffix
    const { Box, Text } = $.ui.resolve(e)
    let glyph = <Text color={paint(hex(hueRgb((arc * ARC_HUE_STEP) % 360)))}>{ARC[arc % ARC.length]}</Text>
    if (e.surface === 'terminal') {
      const { Raster } = $.ui.resolve(e)
      spinners.add(e.requestId)
      glyph = <Raster key="arc" columns={1} rows={1} cells={arcCells()} />
    }

    const elapsed = turnStart === null ? 0 : now - turnStart
    const est = Math.round(chars / 4)
    const thinking =
      e.props.mode === 'thinking'
        ? thinkingLabel(thinkStart === null ? 0 : now - thinkStart)
        : thoughtFor && now < thoughtFor.until
          ? `thought for ${Math.max(1, Math.round(thoughtFor.ms / 1000))}s`
          : null
    const showParen = thinking !== null || est > 0 || elapsed > 16000

    const tokenText = `↓ ${tokens(est)} tokens`
    const jitter = Math.floor(tick / 5) % 2
    const sway = Math.round((1 - Math.cos((2 * Math.PI * now) / 2000)) / 2)
    const swayGray = Math.round(153 + 32 * ((Math.sin((2 * Math.PI * now) / 2000) + 1) / 2))

    const parts = [
      elapsed > 0 && <Text dimColor>{duration(elapsed)}</Text>,
      est > 0 && (
        <Box width={tokenText.length + 1}>
          <Box marginLeft={jitter}>
            {[...tokenText].map((ch, i) => (
              <Text bold color={paint(rainbow(i, tick))}>{ch}</Text>
            ))}
          </Box>
        </Box>
      ),
      thinking && (
        <Box width={thinking.length + 1}>
          <Box marginLeft={sway}>
            <Text color={paint(`rgb(${swayGray},${swayGray},${swayGray})`)}>{thinking}</Text>
          </Box>
        </Box>
      ),
    ].filter(Boolean)

    return (
      <Box flexDirection="row" flexWrap="wrap" marginTop={1} width="100%">
        <Box width={2}>{glyph}</Box>
        {[...word].map((ch, i) => (
          <Text color={paint(rainbow(i + 1, tick))}>{ch}</Text>
        ))}
        {showParen && parts.length > 0 && (
          <Box>
            <Text dimColor> (</Text>
            {parts.flatMap((p, i) => (i === 0 ? [p] : [<Text dimColor> · </Text>, p]))}
            <Text dimColor>)</Text>
          </Box>
        )}
      </Box>
    )
  })

  // Same layout and dim text as the engine's line; only its glyph becomes a check mark
  on('ui.render', { component: 'TurnDuration' }, ($, e, next) => {
    if (!enabled) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="row" width="100%">
        <Box minWidth={2}>
          <Text color={paint(rainbow(0, tick))}>✔</Text>
        </Box>
        <Text dimColor>{`${e.props.word} for ${duration(e.props.durationMs)}`}</Text>
      </Box>
    )
  })

  // The prompt text stays in the normal color so it reads as before; only the marker is decorated
  on('ui.render', { component: 'UserMessage', props: { origin: { kind: 'composer' } } }, ($, e, next) => {
    if (!enabled || e.props.isExpanded) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="row" marginTop={1}>
        <Box width={2} flexShrink={0}>
          <Text bold color={paint(rainbow(e.props.text.length, tick))}>{'>'}</Text>
        </Box>
        <Text>{e.props.text}</Text>
      </Box>
    )
  })

  on('ui.render', { component: 'SessionMode' }, ($, e, next) => {
    if (!enabled || e.props.modes.length === 0) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box>
        {e.props.modes.map((mode, i) => (
          <Text color={paint(rainbow(i, tick))}>{i === 0 ? mode : ` · ${mode}`}</Text>
        ))}
      </Box>
    )
  })

  on('ui.render', { component: 'AbovePrompt' }, ($, e, next) => {
    if (!enabled || !e.props.isWorking || e.props.hasSurvey) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box>
        {Array.from({ length: Math.max(1, e.props.bodyColumns) }, (_, i) => (
          <Text color={paint(rainbow(Math.floor(i / 3), tick))}>━</Text>
        ))}
      </Box>
    )
  })
}
