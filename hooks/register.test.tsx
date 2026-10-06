import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { expect, mock, test } from 'claude-code/testing'

const SPINNER = { word: 'Sauteing', message: null, suffix: '…', mode: 'responding' } as const
const COMPOSER = { kind: 'composer' } as const

// Stands in for the engine's own drawing, so a test can tell when the plugin passed
const engineDraws = (on: On) =>
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>ENGINE</Text>
  })

const run = async ($: Engine, args: string) =>
  $.command.run({ command: 'dopagaki', args, origin: COMPOSER, presentation: { isFullscreen: false, columns: 80 } })

const textOf = async (ui: { findAll: (q: { type: string }) => Promise<{ text: string }[]> }) =>
  (await ui.findAll({ type: 'Text' })).map(t => t.text).join('')

const startSession = async ($: Engine, on: On) => {
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
}

const arcCells = async ($: Engine) => {
  const ui = await $.ui.mount({ plugin: 'dopagaki', surface: 'terminal', component: 'Spinner', props: SPINNER })
  const [raster] = await ui.findAll({ type: 'Raster' })
  return raster?.props.cells
}

// [codePoint, foreground, background] as little-endian u32, base64
const ARC0_RED = '3CUAAAAA/wAAAAAB' // ◜ hue 0
const ARC1_HUE6 = '4CUAAAAZ/wAAAAAB' // ◠ hue 6
const ARC0_HUE36 = '3CUAAACZ/wAAAAAB' // ◜ again after 6 frames, hue 36
const ARC0_DEFAULT = '3CUAAAAAAAEAAAAB' // ◜ in the terminal's default color

test('spinner arc is repainted every 100ms, looping forward with the hue turning 6 degrees a frame', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  mock.env(on, {})
  engineDraws(on)
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  const blits: string[] = []
  on('ui.blit', (_$, e) => {
    if ('cells' in e && e.cells) blits.push(e.cells)
    return { value: {} }
  })
  await startSession($, on)
  await $.turn.start({ turnId: 't1', text: 'hi' })

  expect(await arcCells($)).toBe(ARC0_RED)
  await clock.advance(100)
  expect(blits.at(-1)).toBe(ARC1_HUE6)
  await clock.advance(500)
  expect(blits.at(-1)).toBe(ARC0_HUE36)
})

test('spinner keeps the word whole', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  engineDraws(on)
  const ui = await $.ui.mount({ plugin: 'dopagaki', surface: 'terminal', component: 'Spinner', props: SPINNER })

  const texts = (await ui.findAll({ type: 'Text' })).map(t => t.text)
  expect(texts.join('')).toBe('Sauteing…')
})

test('NO_COLOR keeps the arc but drops every color', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  mock.env(on, { NO_COLOR: '1' })
  engineDraws(on)
  await startSession($, on)

  expect(await arcCells($)).toBe(ARC0_DEFAULT)
  const ui = await $.ui.mount({ plugin: 'dopagaki', surface: 'terminal', component: 'Spinner', props: SPINNER })
  const texts = await ui.findAll({ type: 'Text' })
  expect(texts.every(t => t.props.color === undefined)).toBe(true)
})

test('spinner shows elapsed time and the thinking label while thinking', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  engineDraws(on)
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  await $.turn.start({ turnId: 't1', text: 'hi' })
  await clock.advance(20000)

  const ui = await $.ui.mount({
    plugin: 'dopagaki',
    surface: 'terminal',
    component: 'Spinner',
    props: { ...SPINNER, mode: 'thinking' },
  })

  expect(await textOf(ui)).toContain('(20s · thinking)')
})

test('turn duration keeps its word and time behind a check mark', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  engineDraws(on)
  const ui = await $.ui.mount({
    plugin: 'dopagaki',
    surface: 'terminal',
    component: 'TurnDuration',
    props: { word: 'Baked', durationMs: 64000 },
  })

  expect(await textOf(ui)).toBe('✔Baked for 1m 4s')
  const [check] = await ui.findAll({ type: 'Text' })
  expect(check?.props.color).toMatch(/^#/)
})

test('user prompt keeps its text whole; expanded view is the engine own', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  engineDraws(on)
  const props = { text: 'fix the bug\nin two lines', origin: COMPOSER, isExpanded: false }
  const ui = await $.ui.mount({ plugin: 'dopagaki', surface: 'terminal', component: 'UserMessage', props })
  expect(await textOf(ui)).toBe('>fix the bug\nin two lines')

  const expanded = await $.ui.mount({
    plugin: 'dopagaki',
    surface: 'terminal',
    component: 'UserMessage',
    props: { ...props, isExpanded: true },
  })
  expect(await textOf(expanded)).toBe('ENGINE')
})

test('rainbow bar shows above the prompt only while working', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  engineDraws(on)
  const base = { hasSurvey: false, maxRows: 5, bodyColumns: 6, scroll: { top: 0 }, view: {} }

  const idle = await $.ui.mount({
    plugin: 'dopagaki',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { ...base, isWorking: false } as never,
  })
  expect(await textOf(idle)).toBe('ENGINE')

  const working = await $.ui.mount({
    plugin: 'dopagaki',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { ...base, isWorking: true } as never,
  })
  expect(await textOf(working)).toBe('━━━━━━')
})

test('/dopagaki off hands every site back to the engine', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  engineDraws(on)

  expect(await run($, 'off')).toMatchObject({ text: 'dopagaki: off' })
  const ui = await $.ui.mount({ plugin: 'dopagaki', surface: 'terminal', component: 'Spinner', props: SPINNER })
  expect(await textOf(ui)).toBe('ENGINE')


  expect(await run($, '')).toMatchObject({ text: 'dopagaki: on' })
})
